// Command-line harness: index a folder and search it, without the app.
//
//   dart run eztiger_core:scan --db eztiger.db --add "C:\Users\deane\Desktop\backing 2024 april"
//   dart run eztiger_core:scan --db eztiger.db              (rescan every root)
//   dart run eztiger_core:scan --db eztiger.db --search "sweet caroline"
//   dart run eztiger_core:scan --db eztiger.db --report report.tsv
import 'dart:io';

import 'package:eztiger_core/eztiger_core.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Future<void> main(List<String> args) async {
  String dbPath = 'eztiger.db';
  final add = <String>[];
  final searches = <String>[];
  String? reportPath;
  for (var i = 0; i < args.length; i++) {
    switch (args[i]) {
      case '--db':
        dbPath = args[++i];
      case '--add':
        add.add(args[++i]);
      case '--search':
        searches.add(args[++i]);
      case '--report':
        reportPath = args[++i];
      case '-h' || '--help':
        stdout.writeln('Usage: scan [--db file] [--add folder]... [--search text]... [--report out.tsv]');
        return;
      default:
        add.add(args[i]);
    }
  }

  sqfliteFfiInit();
  final db = await EztigerDatabase.open(databaseFactoryFfi, File(dbPath).absolute.path);
  stdout.writeln('Database: $dbPath (full-text search: ${db.hasFts ? 'FTS5' : 'LIKE fallback'})');
  for (final folder in add) {
    await db.folders.addRoot(Directory(folder).absolute.path);
  }

  if (searches.isEmpty || add.isNotEmpty) {
    final scanner = LibraryScanner(db);
    final report = await scanner.scanAll(onProgress: (n, dir) {
      if (n % 25 == 0) stdout.write('\r  $n folders...');
    });
    stdout.writeln('\rScan: $report');
    for (final r in report.missingRoots) {
      stdout.writeln('  Not found (nothing was changed): $r');
    }
    for (final o in report.orphanCdgs.take(20)) {
      stdout.writeln('  CDG with no audio: $o');
    }
    for (final e in report.errors.take(20)) {
      stdout.writeln('  $e');
    }
  }

  for (final q in searches) {
    final groups = await db.search.search(q, limit: 25);
    stdout.writeln('\n"$q": ${groups.length} songs');
    for (final g in groups) {
      final t = g.primary;
      final extra = [
        if (t.version != null) t.version!,
        if (t.hasLyricSheet) 'lyric sheet',
        if (t.hasStems) 'stems',
        if (g.versions.length > 1) '${g.versions.length} copies',
      ].join(', ');
      stdout.writeln('  ${t.type.label}  ${t.title} — ${t.artist ?? '?'}'
          '${extra.isEmpty ? '' : '  ($extra)'}\n        ${t.path}');
    }
  }

  if (reportPath != null) {
    // Every track with what the parser made of it, for checking by eye.
    final rows = await db.db
        .rawQuery('SELECT kind, title, artist, version, catalogue_code, path FROM tracks ORDER BY path');
    final out = StringBuffer('type\ttitle\tartist\tversion\tcode\tpath\n');
    for (final r in rows) {
      out.writeln([
        r['kind'],
        r['title'],
        r['artist'] ?? '',
        r['version'] ?? '',
        r['catalogue_code'] ?? '',
        r['path']
      ].join('\t'));
    }
    File(reportPath).writeAsStringSync(out.toString());
    stdout.writeln('Wrote ${rows.length} rows to $reportPath');
  }
  await db.close();
}
