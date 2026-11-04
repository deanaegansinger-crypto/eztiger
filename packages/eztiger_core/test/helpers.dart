import 'dart:io';

import 'package:archive/archive.dart';
import 'package:eztiger_core/eztiger_core.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// A throwaway library folder plus database for one test.
class TestLibrary {
  TestLibrary._(this.dir, this.root, this.db);

  final Directory dir;
  final String root;
  final EztigerDatabase db;
  late final LibraryScanner scanner = LibraryScanner(db);

  static Future<TestLibrary> create({bool disableFts = false}) async {
    sqfliteFfiInit();
    final dir = Directory.systemTemp.createTempSync('eztiger_test_');
    final root = p.join(dir.path, 'backing 2024 april');
    Directory(root).createSync();
    final db = await EztigerDatabase.open(databaseFactoryFfiNoIsolate, p.join(dir.path, 'test.db'),
        disableFts: disableFts);
    await db.folders.addRoot(root);
    return TestLibrary._(dir, root, db);
  }

  String path(String rel) => p.joinAll([root, ...rel.split('/')]);

  /// Creates a file with [bytes] bytes of content. A fixed [mtime] lets a
  /// test prove that freshness doesn't rely on timestamps alone.
  File touch(String rel, {int bytes = 10, DateTime? mtime, String? text}) {
    final f = File(path(rel));
    f.parent.createSync(recursive: true);
    if (text != null) {
      f.writeAsStringSync(text);
    } else {
      f.writeAsBytesSync(List.filled(bytes, 0));
    }
    f.setLastModifiedSync(mtime ?? DateTime(2024, 4, 1));
    return f;
  }

  void zip(String rel, List<String> innerNames) {
    final a = Archive();
    for (final n in innerNames) {
      a.addFile(ArchiveFile.bytes(n, List.filled(20, 1)));
    }
    final f = File(path(rel));
    f.parent.createSync(recursive: true);
    f.writeAsBytesSync(ZipEncoder().encode(a));
    f.setLastModifiedSync(DateTime(2024, 4, 1));
  }

  void delete(String rel) => File(path(rel)).deleteSync();

  Future<ScanReport> scan() => scanner.scanAll();

  Future<Track> track(String rel) async => (await db.tracks.byPath(path(rel)))!;

  Future<List<String>> titles(String query, {int? folderId, TrackType? type}) async =>
      (await db.search.search(query, folderId: folderId, type: type)).map((g) => g.primary.title).toList();

  Future<void> dispose() async {
    await db.close();
    dir.deleteSync(recursive: true);
  }
}
