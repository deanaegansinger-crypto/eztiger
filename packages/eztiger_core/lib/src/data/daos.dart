import 'package:sqflite_common/sqlite_api.dart';

import '../text.dart';
import '../audio/track_analysis.dart';
import 'models.dart';
import 'schema.dart' show trackAnalysisStatement;
import 'search.dart';

const String trackSelect = 'SELECT t.*, f.path AS folder_path FROM tracks t JOIN folders f ON f.id = t.folder_id';

int _now() => DateTime.now().millisecondsSinceEpoch;

// ------------------------------------------------------------------ folders

class FolderDao {
  FolderDao(this.db);
  final Database db;

  static const _select = '''
SELECT f.*, EXISTS(SELECT 1 FROM folders c WHERE c.parent_id = f.id) AS has_children
FROM folders f''';

  /// Adds a folder to the library as a root and returns its id. Run the
  /// scanner afterwards to index it. If the folder is already known as a
  /// subfolder of another root it is simply marked as a root too.
  Future<int> addRoot(String path) async {
    final existing = await db.query('folders', where: 'path = ?', whereArgs: [path]);
    if (existing.isNotEmpty) {
      final id = existing.first['id'] as int;
      await db.update('folders', {'is_root': 1, 'included': 1}, where: 'id = ?', whereArgs: [id]);
      return id;
    }
    return db.insert('folders', {
      'path': path,
      'parent_id': null,
      'name': _baseName(path),
      'is_root': 1,
    });
  }

  /// Removes a root and everything indexed under it. This also removes
  /// those songs from playlists, the queue and history.
  Future<void> removeRoot(int id) => db.delete('folders', where: 'id = ?', whereArgs: [id]);

  /// "Add to / remove from searchable library" on a folder. Excluded
  /// folders are hidden from search and skipped by the scanner, but their
  /// tracks are kept, so playlists that use them are not touched.
  Future<void> setIncluded(int id, bool included) => db.rawUpdate('''
WITH RECURSIVE sub(id) AS (
  SELECT ? UNION ALL SELECT f.id FROM folders f JOIN sub ON f.parent_id = sub.id
)
UPDATE folders SET included = ? WHERE id IN (SELECT id FROM sub)''', [id, included ? 1 : 0]);

  Future<List<Folder>> roots() async =>
      (await db.rawQuery('$_select WHERE f.is_root = 1 ORDER BY f.name COLLATE NOCASE')).map(Folder.fromRow).toList();

  Future<List<Folder>> children(int parentId) async =>
      (await db.rawQuery('$_select WHERE f.parent_id = ? ORDER BY f.name COLLATE NOCASE', [parentId]))
          .map(Folder.fromRow)
          .toList();

  Future<Folder?> byId(int id) async {
    final rows = await db.rawQuery('$_select WHERE f.id = ?', [id]);
    return rows.isEmpty ? null : Folder.fromRow(rows.first);
  }

  Future<Folder?> byPath(String path) async {
    final rows = await db.rawQuery('$_select WHERE f.path = ?', [path]);
    return rows.isEmpty ? null : Folder.fromRow(rows.first);
  }
}

String _baseName(String path) {
  final parts = path.split(RegExp(r'[\\/]')).where((p) => p.isNotEmpty).toList();
  return parts.isEmpty ? path : parts.last;
}

// ------------------------------------------------------------------- tracks

class TrackDao {
  TrackDao(this.db, this.hasFts);
  final Database db;
  final bool hasFts;

  /// Every song in the searchable library, once each (several versions of a
  /// song count once), for the audience songbook: by artist, then title.
  Future<List<SongbookEntry>> songbook() async {
    final rows = await db.rawQuery('''
SELECT COALESCE(t.user_title, t.title) AS title, COALESCE(t.user_artist, t.artist) AS artist
FROM tracks t JOIN folders f ON f.id = t.folder_id
WHERE f.included = 1''');
    final seen = <String>{};
    final songs = <SongbookEntry>[];
    for (final r in rows) {
      final title = (r['title'] as String).trim();
      final artist = (r['artist'] as String?)?.trim() ?? '';
      if (title.isEmpty) continue;
      if (seen.add('${normalize(artist)}|${normalize(title)}')) {
        songs.add((title: title, artist: artist));
      }
    }
    int by(String a, String b) => a.toLowerCase().compareTo(b.toLowerCase());
    songs.sort((a, b) {
      final c = by(a.artist, b.artist);
      return c != 0 ? c : by(a.title, b.title);
    });
    return songs;
  }

  Future<Track?> byId(int id) async {
    final rows = await db.rawQuery('$trackSelect WHERE t.id = ?', [id]);
    return rows.isEmpty ? null : Track.fromRow(rows.first);
  }

  Future<Track?> byPath(String path) async {
    final rows = await db.rawQuery('$trackSelect WHERE t.path = ?', [path]);
    return rows.isEmpty ? null : Track.fromRow(rows.first);
  }

  /// The song whose file is [tail] inside some folder, such as
  /// `Sunfly/SF001/SF001-01 - Abba - Waterloo.mp3`, ignoring case and `/` or
  /// `\`: for a song named by another computer, whose library is somewhere
  /// else. Null if there is none.
  Future<Track?> byPathEnding(String tail) async {
    final t = '/${tail.replaceAll('\\', '/').replaceFirst(RegExp(r'^/+'), '')}';
    if (t.length < 2) return null;
    final rows = await db.rawQuery(
        "$trackSelect WHERE substr(REPLACE(LOWER(t.path), '\\', '/'), -?) = LOWER(?) LIMIT 1", [t.length, t]);
    return rows.isEmpty ? null : Track.fromRow(rows.first);
  }

  /// Tracks directly in a folder, for browsing.
  Future<List<Track>> inFolder(int folderId) async => (await db.rawQuery(
          '$trackSelect WHERE t.folder_id = ? '
          'ORDER BY COALESCE(t.user_title, t.title) COLLATE NOCASE',
          [folderId]))
      .map(Track.fromRow)
      .toList();

  Future<String?> lyrics(int id) async {
    final rows = await db.query('tracks', columns: ['lyrics_text'], where: 'id = ?', whereArgs: [id]);
    return rows.isEmpty ? null : rows.first['lyrics_text'] as String?;
  }

  /// "Edit tags" from the app. Pass null to leave a field as it is, and an
  /// empty string to go back to what the file name says. Rescans never
  /// overwrite these edits.
  Future<void> editTags(int id, {String? title, String? artist, TrackType? type, bool clearType = false}) async {
    final current = await byId(id);
    if (current == null) return;
    final values = <String, Object?>{};
    if (title != null) values['user_title'] = title.trim().isEmpty ? null : title.trim();
    if (artist != null) values['user_artist'] = artist.trim().isEmpty ? null : artist.trim();
    if (type != null) values['user_kind'] = type.label;
    if (clearType) values['user_kind'] = null;
    final newTitle = values.containsKey('user_title') ? values['user_title'] as String? : current.userTitle;
    final newArtist = values.containsKey('user_artist') ? values['user_artist'] as String? : current.userArtist;
    values['group_key'] = groupKey(newTitle ?? current.parsedTitle, newArtist ?? current.parsedArtist);
    await db.update('tracks', values, where: 'id = ?', whereArgs: [id]);
    if (hasFts) await indexTracks(db, [id]);
  }
}

// ---------------------------------------------------------------- playlists

class PlaylistDao {
  PlaylistDao(this.db);
  final Database db;

  Future<int> create(String name) => db.insert('playlists', {'name': name.trim(), 'created_at': _now()});

  Future<void> rename(int id, String name) =>
      db.update('playlists', {'name': name.trim()}, where: 'id = ?', whereArgs: [id]);

  Future<void> delete(int id) => db.delete('playlists', where: 'id = ?', whereArgs: [id]);

  Future<List<Playlist>> all() async {
    final rows = await db.rawQuery('''
SELECT p.id, p.name, COUNT(pt.track_id) AS n
FROM playlists p LEFT JOIN playlist_tracks pt ON pt.playlist_id = p.id
GROUP BY p.id ORDER BY p.name COLLATE NOCASE''');
    return rows.map((r) => Playlist(id: r['id'] as int, name: r['name'] as String, trackCount: r['n'] as int)).toList();
  }

  Future<List<Track>> tracks(int playlistId) async => (await db.rawQuery('''
$trackSelect JOIN playlist_tracks pt ON pt.track_id = t.id
WHERE pt.playlist_id = ? ORDER BY pt.position''', [playlistId])).map(Track.fromRow).toList();

  Future<void> add(int playlistId, int trackId) => db.rawInsert('''
INSERT INTO playlist_tracks(playlist_id, track_id, position)
VALUES(?, ?, (SELECT COALESCE(MAX(position), -1) + 1 FROM playlist_tracks WHERE playlist_id = ?))''',
      [playlistId, trackId, playlistId]);

  /// Adds several songs to the end of a playlist, in order.
  Future<void> addAll(int playlistId, Iterable<int> trackIds) => db.transaction((txn) async {
        final r = await txn.rawQuery(
            'SELECT COALESCE(MAX(position), -1) + 1 AS n FROM playlist_tracks WHERE playlist_id = ?', [playlistId]);
        var pos = r.first['n'] as int;
        for (final id in trackIds) {
          await txn.insert('playlist_tracks', {'playlist_id': playlistId, 'track_id': id, 'position': pos++});
        }
      });

  /// Inserts songs before position [at] (0-based; past the end adds them at
  /// the bottom).
  Future<void> insertAll(int playlistId, Iterable<int> trackIds, {required int at}) => db.transaction((txn) async {
        final ids = await _ids(txn, playlistId);
        ids.insertAll(at.clamp(0, ids.length), trackIds);
        await _write(txn, playlistId, ids);
      });

  /// Moves the songs at [positions] so they sit together before what was
  /// position [to] (counted before the move), keeping their order.
  Future<void> moveBlock(int playlistId, Iterable<int> positions, int to) => db.transaction((txn) async {
        final ids = await _ids(txn, playlistId);
        await _write(txn, playlistId, moveBlockIn(ids, positions, to));
      });

  Future<List<int>> _ids(Transaction txn, int playlistId) async =>
      (await txn.query('playlist_tracks', where: 'playlist_id = ?', whereArgs: [playlistId], orderBy: 'position'))
          .map((r) => r['track_id'] as int)
          .toList();

  Future<void> _write(Transaction txn, int playlistId, List<int> ids) async {
    await txn.delete('playlist_tracks', where: 'playlist_id = ?', whereArgs: [playlistId]);
    for (var i = 0; i < ids.length; i++) {
      await txn.insert('playlist_tracks', {'playlist_id': playlistId, 'track_id': ids[i], 'position': i});
    }
  }

  /// Removes the songs at [positions] (0-based) in one go.
  Future<void> removePositions(int playlistId, Iterable<int> positions) => db.transaction((txn) async {
        for (final p in positions) {
          await txn.delete('playlist_tracks', where: 'playlist_id = ? AND position = ?', whereArgs: [playlistId, p]);
        }
        await _renumber(txn, playlistId);
      });

  /// Saves the current queue as a playlist ("drag songs from the queue onto
  /// a folder to save them for next time").
  Future<void> addQueue(int playlistId) async {
    final q = await db.query('queue', orderBy: 'position');
    for (final r in q) {
      await add(playlistId, r['track_id'] as int);
    }
  }

  Future<void> removeAt(int playlistId, int position) => db.transaction((txn) async {
        await txn
            .delete('playlist_tracks', where: 'playlist_id = ? AND position = ?', whereArgs: [playlistId, position]);
        await _renumber(txn, playlistId);
      });

  Future<void> move(int playlistId, int from, int to) => db.transaction((txn) async {
        final ids =
            (await txn.query('playlist_tracks', where: 'playlist_id = ?', whereArgs: [playlistId], orderBy: 'position'))
                .map((r) => r['track_id'] as int)
                .toList();
        if (from < 0 || from >= ids.length) return;
        final id = ids.removeAt(from);
        ids.insert(to.clamp(0, ids.length), id);
        await txn.delete('playlist_tracks', where: 'playlist_id = ?', whereArgs: [playlistId]);
        for (var i = 0; i < ids.length; i++) {
          await txn.insert('playlist_tracks', {'playlist_id': playlistId, 'track_id': ids[i], 'position': i});
        }
      });

  Future<void> _renumber(Transaction txn, int playlistId) async {
    final ids =
        (await txn.query('playlist_tracks', where: 'playlist_id = ?', whereArgs: [playlistId], orderBy: 'position'))
            .map((r) => r['track_id'] as int)
            .toList();
    await txn.delete('playlist_tracks', where: 'playlist_id = ?', whereArgs: [playlistId]);
    for (var i = 0; i < ids.length; i++) {
      await txn.insert('playlist_tracks', {'playlist_id': playlistId, 'track_id': ids[i], 'position': i});
    }
  }
}

// -------------------------------------------------------------------- queue

class QueueDao {
  QueueDao(this.db);
  final Database db;

  Future<int> add(int trackId, {String? singer}) => db.rawInsert('''
INSERT INTO queue(track_id, singer, position)
VALUES(?, ?, (SELECT COALESCE(MAX(position), -1) + 1 FROM queue))''', [trackId, singer]);

  Future<List<QueueEntry>> all() async {
    final rows = await db.rawQuery('''
SELECT t.*, f.path AS folder_path, q.id AS q_id, q.singer AS q_singer, q.position AS q_position,
  q.played_at AS q_played, (SELECT MAX(h.sung_at) FROM singer_history h WHERE h.track_id = q.track_id) AS q_last
FROM queue q JOIN tracks t ON t.id = q.track_id JOIN folders f ON f.id = t.folder_id
ORDER BY q.position''');
    return rows
        .map((r) => QueueEntry(
            id: r['q_id'] as int,
            position: r['q_position'] as int,
            singer: r['q_singer'] as String?,
            track: Track.fromRow(r),
            playedAt: _time(r['q_played']),
            lastSung: _time(r['q_last'])))
        .toList();
  }

  Future<void> remove(int queueId) => db.transaction((txn) async {
        await txn.delete('queue', where: 'id = ?', whereArgs: [queueId]);
        await _renumber(txn);
      });

  Future<void> setSinger(int queueId, String? singer) =>
      db.update('queue', {'singer': singer}, where: 'id = ?', whereArgs: [queueId]);

  Future<void> move(int queueId, int newIndex) => db.transaction((txn) async {
        final ids = (await txn.query('queue', orderBy: 'position')).map((r) => r['id'] as int).toList();
        if (!ids.remove(queueId)) return;
        ids.insert(newIndex.clamp(0, ids.length), queueId);
        for (var i = 0; i < ids.length; i++) {
          await txn.update('queue', {'position': i}, where: 'id = ?', whereArgs: [ids[i]]);
        }
      });

  /// Adds songs to the queue before position [at] (past the end adds them at
  /// the bottom). Returns the new queue ids.
  Future<List<int>> insertAll(Iterable<int> trackIds, {required int at}) => db.transaction((txn) async {
        final ids = (await txn.query('queue', orderBy: 'position')).map((r) => r['id'] as int).toList();
        final added = <int>[];
        for (final t in trackIds) {
          added.add(await txn.insert('queue', {'track_id': t, 'position': ids.length + added.length}));
        }
        ids.insertAll(at.clamp(0, ids.length), added);
        for (var i = 0; i < ids.length; i++) {
          await txn.update('queue', {'position': i}, where: 'id = ?', whereArgs: [ids[i]]);
        }
        return added;
      });

  /// Moves the queue entries [queueIds] together before what was position
  /// [to], keeping their order.
  Future<void> moveBlock(Iterable<int> queueIds, int to) => db.transaction((txn) async {
        final ids = (await txn.query('queue', orderBy: 'position')).map((r) => r['id'] as int).toList();
        final positions = [for (final q in queueIds) ids.indexOf(q)]..removeWhere((p) => p < 0);
        final moved = moveBlockIn(ids, positions, to);
        for (var i = 0; i < moved.length; i++) {
          await txn.update('queue', {'position': i}, where: 'id = ?', whereArgs: [moved[i]]);
        }
      });

  static DateTime? _time(Object? ms) => ms is int ? DateTime.fromMillisecondsSinceEpoch(ms) : null;

  /// Call when a queued song has been sung: logs it to history and marks it
  /// played. It stays in the queue (see [clearPlayed]).
  Future<void> markSung(int queueId, {DateTime? at}) => db.transaction((txn) async {
        final rows = await txn.query('queue', where: 'id = ?', whereArgs: [queueId]);
        if (rows.isEmpty) return;
        final when = (at ?? DateTime.now()).millisecondsSinceEpoch;
        await txn.insert('singer_history', {
          'track_id': rows.first['track_id'],
          'singer': rows.first['singer'],
          'sung_at': when,
        });
        await txn.update('queue', {'played_at': when}, where: 'id = ?', whereArgs: [queueId]);
      });

  /// Takes the played songs off the queue.
  Future<void> clearPlayed() => db.transaction((txn) async {
        await txn.delete('queue', where: 'played_at IS NOT NULL');
        await _renumber(txn);
      });

  Future<void> clear() => db.delete('queue');

  Future<void> _renumber(Transaction txn) async {
    final ids = (await txn.query('queue', orderBy: 'position')).map((r) => r['id'] as int).toList();
    for (var i = 0; i < ids.length; i++) {
      await txn.update('queue', {'position': i}, where: 'id = ?', whereArgs: [ids[i]]);
    }
  }
}

// ------------------------------------------------------------------ history

class HistoryDao {
  HistoryDao(this.db);
  final Database db;

  Future<void> log(int trackId, {String? singer, DateTime? at}) => db.insert('singer_history', {
        'track_id': trackId,
        'singer': singer,
        'sung_at': (at ?? DateTime.now()).millisecondsSinceEpoch,
      });

  Future<List<HistoryEntry>> recent({int limit = 200, String? singer}) async {
    final rows = await db.rawQuery('''
SELECT t.*, f.path AS folder_path, h.id AS h_id, h.singer AS h_singer, h.sung_at AS h_at
FROM singer_history h JOIN tracks t ON t.id = h.track_id JOIN folders f ON f.id = t.folder_id
${singer == null ? '' : 'WHERE h.singer = ? COLLATE NOCASE'}
ORDER BY h.sung_at DESC, h.id DESC LIMIT ?''', [if (singer != null) singer, limit]);
    return rows
        .map((r) => HistoryEntry(
            id: r['h_id'] as int,
            singer: r['h_singer'] as String?,
            sungAt: DateTime.fromMillisecondsSinceEpoch(r['h_at'] as int),
            track: Track.fromRow(r)))
        .toList();
  }

  Future<List<String>> singers() async => (await db.rawQuery(
          'SELECT DISTINCT singer FROM singer_history WHERE singer IS NOT NULL ORDER BY singer COLLATE NOCASE'))
      .map((r) => r['singer'] as String)
      .toList();
}

/// [list] with the items at [positions] lifted out and put back together
/// before what was index [to].
List<T> moveBlockIn<T>(List<T> list, Iterable<int> positions, int to) {
  final pos = positions.toSet().where((p) => p >= 0 && p < list.length).toList()..sort();
  final block = [for (final p in pos) list[p]];
  final rest = [
    for (var i = 0; i < list.length; i++)
      if (!pos.contains(i)) list[i]
  ];
  final before = pos.where((p) => p < to).length;
  rest.insertAll((to - before).clamp(0, rest.length), block);
  return rest;
}

/// The key and tempo saved for each song (see [trackAnalysisStatement]).
class AnalysisDao {
  AnalysisDao(this.db);
  final Database db;

  /// What was saved for [track], or null when it hasn't been analysed or the
  /// file has changed since. A saved row with no key means the analysis was
  /// tried and couldn't tell, so it isn't tried again on every load.
  Future<({TrackAnalysis? result})?> forTrack(Track track) async {
    final rows = await db.query('track_analysis', where: 'path = ?', whereArgs: [track.path]);
    if (rows.isEmpty) return null;
    final r = rows.first;
    if (r['size'] != track.size || r['mtime'] != track.mtime) return null;
    final key = parseKeyName(r['musical_key'] as String?);
    final bpm = (r['bpm'] as num?)?.toDouble();
    if (key == null || bpm == null) return (result: null);
    return (result: TrackAnalysis(pitchClass: key.$1, minor: key.$2, bpm: bpm));
  }

  /// Saves [result] for [track] (null: it couldn't tell).
  Future<void> save(Track track, TrackAnalysis? result) => db.rawInsert(
    'INSERT INTO track_analysis(path, size, mtime, musical_key, bpm, analysed_at) VALUES(?, ?, ?, ?, ?, ?) '
    'ON CONFLICT(path) DO UPDATE SET size = excluded.size, mtime = excluded.mtime, '
    'musical_key = excluded.musical_key, bpm = excluded.bpm, analysed_at = excluded.analysed_at',
    [track.path, track.size, track.mtime, result?.key, result?.bpm, _now()],
  );
}
