import 'package:sqflite_common/sqlite_api.dart';

import '../text.dart';
import 'models.dart';
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

  Future<Track?> byId(int id) async {
    final rows = await db.rawQuery('$trackSelect WHERE t.id = ?', [id]);
    return rows.isEmpty ? null : Track.fromRow(rows.first);
  }

  Future<Track?> byPath(String path) async {
    final rows = await db.rawQuery('$trackSelect WHERE t.path = ?', [path]);
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
SELECT t.*, f.path AS folder_path, q.id AS q_id, q.singer AS q_singer, q.position AS q_position
FROM queue q JOIN tracks t ON t.id = q.track_id JOIN folders f ON f.id = t.folder_id
ORDER BY q.position''');
    return rows
        .map((r) => QueueEntry(
            id: r['q_id'] as int,
            position: r['q_position'] as int,
            singer: r['q_singer'] as String?,
            track: Track.fromRow(r)))
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

  /// Call when a queued song has been sung: logs it to history and takes it
  /// off the queue, in one step.
  Future<void> markSung(int queueId, {DateTime? at}) => db.transaction((txn) async {
        final rows = await txn.query('queue', where: 'id = ?', whereArgs: [queueId]);
        if (rows.isEmpty) return;
        await txn.insert('singer_history', {
          'track_id': rows.first['track_id'],
          'singer': rows.first['singer'],
          'sung_at': (at ?? DateTime.now()).millisecondsSinceEpoch,
        });
        await txn.delete('queue', where: 'id = ?', whereArgs: [queueId]);
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
