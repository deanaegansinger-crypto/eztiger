import 'package:sqflite_common/sqlite_api.dart';

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
        search = SearchDao(db, hasFts);

  final Database db;

  /// False if this SQLite build has no FTS5. Search then falls back to LIKE.
  final bool hasFts;

  final FolderDao folders;
  final TrackDao tracks;
  final PlaylistDao playlists;
  final QueueDao queue;
  final HistoryDao history;
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
}
