import 'dart:convert';
import 'dart:io';

import 'package:eztiger/app_state.dart';
import 'package:eztiger/edition.dart';
import 'package:eztiger/player.dart';
import 'package:eztiger/playlist_transfer.dart';
import 'package:eztiger_core/eztiger_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'fakes.dart';

void main() {
  sqfliteFfiInit();
  late Directory lib, out, tabletDir;
  late EztigerDatabase pcDb, tabDb;
  late AppState pc, tablet;
  late PlaylistPackage pkg;

  setUp(() async {
    isPro = true;
    // Real network calls in the Wi-Fi test.
    final saved = HttpOverrides.current;
    HttpOverrides.global = null;
    addTearDown(() => HttpOverrides.global = saved);

    lib = makeLibrary();
    out = Directory.systemTemp.createTempSync('ezt_export');
    tabletDir = Directory.systemTemp.createTempSync('ezt_tablet');
    pcDb = await EztigerDatabase.open(databaseFactoryFfiNoIsolate, inMemoryDatabasePath);
    tabDb = await EztigerDatabase.open(databaseFactoryFfiNoIsolate, inMemoryDatabasePath);
    pc = AppState(pcDb, KaraokeEngine(FakeBackend(), scanEdges: (_) async => null));
    tablet = AppState(tabDb, KaraokeEngine(FakeBackend(), scanEdges: (_) async => null));
    await pc.init(rescanLibrary: false);
    await pc.addRootFolder(lib.path);
    await tablet.init(rescanLibrary: false);
    tablet.importsRootOverride = p.join(tabletDir.path, 'EZTiger imports');

    final all = {for (final g in pc.results) g.primary.fileName: g.primary};
    final waterloo = all['Abba - Waterloo.mp3']!, prayer = all['Bon Jovi - Livin On A Prayer.mp3']!;
    final video = all['Queen - Bohemian Rhapsody.mp4']!;
    final id = await pc.createPlaylist('Friday / Late', tracks: [prayer, waterloo, video]);
    pc.keyShifts[waterloo.path] = -2;
    final pl = pc.playlists.firstWhere((x) => x.id == id);
    pkg = await PlaylistPackage.fromPlaylist(pcDb, pl, keyShifts: pc.keyShifts);
  });

  tearDown(() async {
    pc.dispose();
    tablet.dispose();
    await pcDb.close();
    await tabDb.close();
    for (final d in [lib, out, tabletDir]) {
      if (d.existsSync()) d.deleteSync(recursive: true);
    }
  });

  /// The tablet's playlist: the songs in order, with their keys.
  Future<List<String>> tabletPlaylist() async {
    final pl = tablet.playlists.single;
    expect(pl.name, 'Friday / Late');
    return [
      for (final t in await tabDb.playlists.tracks(pl.id)) '${t.title}${tablet.keyShifts[t.path] != null ? ' ${tablet.keyShifts[t.path]}' : ''}',
    ];
  }

  const expected = ['Livin On A Prayer', 'Waterloo -2', 'Bohemian Rhapsody'];

  test('the package: every song file, its CDG, and the key', () {
    expect(pkg.songs.map((s) => s.play), ['Bon Jovi - Livin On A Prayer.mp3', 'Abba - Waterloo.mp3', 'Queen - Bohemian Rhapsody.mp4']);
    expect(pkg.songs[1].files, ['Abba - Waterloo.mp3', 'Abba - Waterloo.cdg']);
    expect(pkg.songs[1].key, -2);
    expect(pkg.totalBytes, greaterThan(24 * 300));
    expect(exportName(pkg), 'EZTiger export - Friday Late');
  });

  test('a folder on a USB stick: exported on the PC, imported on the tablet', () async {
    final folder = await exportToFolder(pkg, out.path);
    expect(File(p.join(folder, manifestName)).existsSync(), isTrue);
    expect(File(p.join(folder, 'songs', 'Abba - Waterloo.cdg')).lengthSync(), 24 * 300);
    expect(isPackage(folder), isTrue);

    final (got, dest) = await importPackage(folder, tablet.importFolderFor, workDir: tablet.importsRoot);
    expect(dest, p.join(tabletDir.path, 'EZTiger imports', 'Friday Late'));
    final line = await tablet.addImportedPlaylist(got, dest);
    expect(line, contains('3 songs'));
    expect(await tabletPlaylist(), expected);
    // EZTiger imports is in the tablet's library now.
    expect(tablet.roots.map((r) => p.basename(r.path)), contains('EZTiger imports'));
    // Imported again: the playlist is replaced, not doubled.
    final (again, dest2) = await importPackage(folder, tablet.importFolderFor, workDir: tablet.importsRoot);
    await tablet.addImportedPlaylist(again, dest2);
    expect(tablet.playlists, hasLength(1));
  });

  test('one zip for Dropbox: exported, then unpacked on the tablet', () async {
    final zip = await exportToZip(pkg, out.path);
    expect(p.basename(zip), 'EZTiger export - Friday Late.zip');
    expect(isPackage(zip), isTrue);
    final (got, dest) = await importPackage(zip, tablet.importFolderFor, workDir: tablet.importsRoot);
    expect(File(p.join(dest, 'songs', 'Queen - Bohemian Rhapsody.mp4')).existsSync(), isTrue);
    await tablet.addImportedPlaylist(got, dest);
    expect(await tabletPlaylist(), expected);
    // Nothing half-unpacked is left behind.
    expect(Directory(tablet.importsRoot).listSync().map((e) => p.basename(e.path)), isNot(contains(startsWith('.incoming'))));
  });

  test('over the Wi-Fi: the PC sends, the tablet receives with the code', () async {
    final sender = PlaylistSender(pkg, port: 0, code: '4821');
    await sender.start();
    addTearDown(sender.stop);
    await expectLater(
      receivePackage('127.0.0.1', '1111', tablet.importFolderFor, port: sender.boundPort),
      throwsA(isA<TransferException>()),
    );
    final seen = <String>[];
    final (got, dest) = await receivePackage('127.0.0.1', '4821', tablet.importFolderFor,
        port: sender.boundPort, onProgress: (d, t, f) => seen.add(f));
    expect(seen, contains('Abba - Waterloo.cdg'));
    expect(sender.bytesSent, pkg.totalBytes);
    expect(File(p.join(dest, manifestName)).existsSync(), isTrue);
    expect(Directory(p.join(dest, 'songs')).listSync().where((f) => f.path.endsWith('.part')), isEmpty);
    await tablet.addImportedPlaylist(got, dest);
    expect(await tabletPlaylist(), expected);
    expect(jsonDecode(File(p.join(dest, manifestName)).readAsStringSync())['eztiger_playlist'], 1);
  });
}
