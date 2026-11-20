import 'package:sqflite_common/sqlite_api.dart';

import '../text.dart';
import 'daos.dart';
import 'schema.dart';
import 'search.dart';

/// The EZtiger library database.
///
/// Takes an injected [DatabaseFactory], so the same code runs on Windows and
/// the command line (`databaseFactoryFfi` from sqflite_common_ffi) and on
/// Android (the sqflite plugin's `databaseFactory`).
class EztigerDatabase {
  EztigerDatabase._(this.db, this.hasFts)
      : folders = FolderDao(db),
        tracks = TrackDao(db, hasFts),
        playlists = PlaylistDao(db),
        queue = QueueDao(db),
        history = HistoryDao(db),
        analysis = AnalysisDao(db),
        search = SearchDao(db, hasFts);

  final Database db;

  /// False if this SQLite build has no FTS5. Search then falls back to LIKE.
  final bool hasFts;

  final FolderDao folders;
  final TrackDao tracks;
  final PlaylistDao playlists;
  final QueueDao queue;
  final HistoryDao history;
  final AnalysisDao analysis;
  final SearchDao search;

  /// Opens (creating if needed) the database at [path]. Use
  /// `inMemoryDatabasePath` for tests. [disableFts] forces the LIKE fallback.
  static Future<EztigerDatabase> open(DatabaseFactory factory, String path, {bool disableFts = false}) async {
    final db = await factory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: schemaVersion,
        onConfigure: (db) async {
          await db.execute('PRAGMA foreign_keys = ON');
        },
        onUpgrade: (db, from, to) async {
          if (from < 2) await db.execute('ALTER TABLE queue ADD COLUMN played_at INTEGER');
          if (from < 3) await db.execute(trackAnalysisStatement);
          if (from < 4) await regroupTracks(db);
          if (from < 5) {
            Future<Set<String>> cols(String table) async =>
                {for (final r in await db.rawQuery('PRAGMA table_info($table)')) r['name'] as String};
            final have = {'tracks': await cols('tracks'), 'folders': await cols('folders')};
            for (final sql in namesColumnsStatements) {
              final m = RegExp(r'ALTER TABLE (\w+) ADD COLUMN (\w+)').firstMatch(sql);
              if (m == null || !have[m.group(1)]!.contains(m.group(2))) await db.execute(sql);
            }
          }
          if (from < 6) {
            final cols = {for (final r in await db.rawQuery('PRAGMA table_info(folders)')) r['name'] as String};
            if (!cols.contains('songbook_private')) await db.execute(songbookPrivateStatement);
          }
        },
        onCreate: (db, version) async {
          final batch = db.batch();
          for (final sql in schemaStatements) {
            batch.execute(sql);
          }
          await batch.commit(noResult: true);
          var fts = false;
          if (!disableFts) {
            try {
              await db.execute(ftsStatement);
              fts = true;
            } on DatabaseException {
              fts = false; // SQLite built without FTS5.
            }
          }
          await db.insert('meta', {'key': 'fts', 'value': fts ? '1' : '0'});
          await db.insert('meta', {'key': 'parser_version', 'value': '$parserVersion'});
        },
      ),
    );
    final rows = await db.query('meta', where: 'key = ?', whereArgs: ['fts']);
    final hasFts = rows.isNotEmpty && rows.first['value'] == '1';
    return EztigerDatabase._(db, hasFts);
  }

  Future<String?> getMeta(String key) async {
    final rows = await db.query('meta', where: 'key = ?', whereArgs: [key]);
    return rows.isEmpty ? null : rows.first['value'] as String;
  }

  Future<void> setMeta(String key, String value) => db.rawInsert(
      'INSERT INTO meta(key, value) VALUES(?, ?) '
      'ON CONFLICT(key) DO UPDATE SET value = excluded.value',
      [key, value]);

  Future<void> close() => db.close();

  /// Where the library's titles and artists come from: 'tags' (the ID3 or
  /// MP4 tags, falling back to the file name for a blank tag) or 'files'
  /// (the file names only).
  Future<String> namesFrom() async => (await getMeta('names_from')) == 'files' ? 'files' : 'tags';

  /// Switches the library between tag names and file names: every song's
  /// title and artist, its grouping and the search index are rewritten from
  /// what the last scan read, with no rescan.
  Future<void> setNamesFrom(String from) async {
    await setMeta('names_from', from == 'files' ? 'files' : 'tags');
    await applyNames();
  }

  /// One folder's own Song names setting ('tags', 'files', or null to follow
  /// the folder above it); it covers the folders inside it too.
  Future<void> setFolderNamesFrom(int folderId, String? from) async {
    await db.update('folders', {'names_from': from == null ? null : (from == 'files' ? 'files' : 'tags')},
        where: 'id = ?', whereArgs: [folderId]);
    await applyNames();
  }

  /// Whether each folder uses tag names: its own setting, or the nearest
  /// folder above it with one, or the library's.
  Future<Map<int, bool>> folderUsesTags() async {
    final libTags = await namesFrom() == 'tags';
    final rows = await db.rawQuery('SELECT id, parent_id, names_from FROM folders');
    final parent = {for (final r in rows) r['id'] as int: r['parent_id'] as int?};
    final own = {for (final r in rows) r['id'] as int: r['names_from'] as String?};
    final out = <int, bool>{};
    bool resolve(int id) {
      final known = out[id];
      if (known != null) return known;
      final o = own[id];
      final up = parent[id];
      return out[id] = o != null ? o == 'tags' : (up == null ? libTags : resolve(up));
    }

    for (final id in own.keys) {
      resolve(id);
    }
    return out;
  }

  /// Rewrites every song's title and artist from its tag and file names,
  /// following the library's and each folder's Song names setting, then its
  /// grouping and (when [index]) the search index. No rescan needed.
  Future<void> applyNames({bool index = true}) async {
    final uses = await folderUsesTags();
    final files = [for (final e in uses.entries) if (!e.value) e.key];
    await db.transaction((txn) async {
      await txn.execute('UPDATE tracks SET title = COALESCE(tag_title, file_title, title), artist = COALESCE(tag_artist, file_artist)');
      for (var i = 0; i < files.length; i += 500) {
        final part = files.sublist(i, i + 500 > files.length ? files.length : i + 500);
        await txn.rawUpdate(
            'UPDATE tracks SET title = COALESCE(file_title, title), artist = file_artist WHERE folder_id IN (${List.filled(part.length, '?').join(',')})',
            part);
      }
      await regroupTracks(txn);
      if (index && hasFts) await rebuildIndex(txn);
    });
  }
}

/// Works out every track's group_key again with today's [groupKey] (for an
/// upgrade that changes how copies of a song are grouped). Only rows whose
/// key changes are written.
Future<void> regroupTracks(DatabaseExecutor db) async {
  final rows = await db.query('tracks', columns: ['id', 'title', 'artist', 'user_title', 'user_artist', 'group_key']);
  final batch = db.batch();
  for (final r in rows) {
    final key = groupKey(
      (r['user_title'] as String?) ?? r['title'] as String,
      (r['user_artist'] as String?) ?? r['artist'] as String?,
    );
    if (key != r['group_key']) batch.update('tracks', {'group_key': key}, where: 'id = ?', whereArgs: [r['id']]);
  }
  await batch.commit(noResult: true);
}
