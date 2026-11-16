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

  Future<ImportPlan?> update(PlaylistPackage x) async => tablet.importPlan(x);
  Future<ImportPlan?> keepBoth(PlaylistPackage x) async => tablet.importPlan(x, keepBoth: true, now: DateTime(2026, 11, 16));

  test('a folder on a USB stick: exported on the PC, imported on the tablet', () async {
    final folder = await exportToFolder(pkg, out.path);
    expect(File(p.join(folder, manifestName)).existsSync(), isTrue);
    expect(File(p.join(folder, 'songs', 'Abba - Waterloo.cdg')).lengthSync(), 24 * 300);
    expect(isPackage(folder), isTrue);

    final r = await importPackage(folder, update);
    expect(r.plan.folder, p.join(tabletDir.path, 'EZTiger imports', 'Friday Late'));
    expect(r.plan.update, isFalse); // nothing of that name yet
    expect((r.copied, r.kept), (4, 0));
    final line = await tablet.addImportedPlaylist(r);
    expect(line, contains('3 songs'));
    expect(await tabletPlaylist(), expected);
    // EZTiger imports is in the tablet's library now.
    expect(tablet.roots.map((r) => p.basename(r.path)), contains('EZTiger imports'));

    // Imported again: an update. Nothing is copied again and the playlist
    // isn't doubled.
    final again = await importPackage(folder, update);
    expect(again.plan.update, isTrue);
    expect((again.copied, again.kept), (0, 4));
    expect(await tablet.addImportedPlaylist(again), contains('updated'));
    expect(tablet.playlists, hasLength(1));
  });

  test('update: only new or changed songs are copied, and dropped ones go', () async {
    await tablet.addImportedPlaylist(await importPackage(await exportToFolder(pkg, out.path), update));

    // The next export: Bohemian Rhapsody has come off the list, and
    // Waterloo's MP3 is a different recording.
    final smaller = PlaylistPackage(
      name: pkg.name,
      songs: pkg.songs.take(2).toList(),
      sizes: {for (final s in pkg.songs.take(2)) for (final f in s.files) f: pkg.sizes[f]!},
      sources: pkg.sources,
    );
    out.deleteSync(recursive: true);
    out.createSync();
    final exported = await exportToFolder(smaller, out.path);
    final waterloo = File(p.join(exported, 'songs', 'Abba - Waterloo.mp3'))..writeAsBytesSync(List.filled(500, 1));
    final r = await importPackage(exported, update);
    expect((r.copied, r.kept), (1, 2)); // just the new Waterloo
    await tablet.addImportedPlaylist(r);
    final songs = Directory(p.join(r.plan.folder, 'songs'));
    expect(File(p.join(songs.path, 'Abba - Waterloo.mp3')).lengthSync(), waterloo.lengthSync());
    expect(File(p.join(songs.path, 'Queen - Bohemian Rhapsody.mp4')).existsSync(), isFalse);
    expect(await tabletPlaylist(), ['Livin On A Prayer', 'Waterloo -2']);
  });

  test('keep both: the new one comes in beside it, with the date on', () async {
    final folder = await exportToFolder(pkg, out.path);
    await tablet.addImportedPlaylist(await importPackage(folder, update));
    final r = await importPackage(folder, keepBoth);
    expect(r.plan.name, 'Friday / Late (16 Nov)');
    expect(r.plan.update, isFalse);
    expect(r.plan.folder, p.join(tabletDir.path, 'EZTiger imports', 'Friday Late (16 Nov)'));
    expect(await tablet.addImportedPlaylist(r), contains('added'));
    expect(tablet.playlists.map((x) => x.name), containsAll(['Friday / Late', 'Friday / Late (16 Nov)']));
    // A third the same day gets a number.
    expect(tablet.labelledName('Friday / Late', DateTime(2026, 11, 16)), 'Friday / Late (16 Nov 2)');
  });

  test('cancelled at "Update or keep both?": nothing is copied', () async {
    final folder = await exportToFolder(pkg, out.path);
    await expectLater(importPackage(folder, (_) async => null), throwsA(isA<TransferCancelled>()));
    expect(Directory(tablet.importsRoot).existsSync(), isFalse);
  });

  test('one zip for Dropbox: exported, then unpacked on the tablet', () async {
    final zip = await exportToZip(pkg, out.path);
    expect(p.basename(zip), 'EZTiger export - Friday Late.zip');
    expect(isPackage(zip), isTrue);
    final r = await importPackage(zip, update);
    expect(File(p.join(r.plan.folder, 'songs', 'Queen - Bohemian Rhapsody.mp4')).existsSync(), isTrue);
    expect(File(p.join(r.plan.folder, manifestName)).existsSync(), isTrue);
    await tablet.addImportedPlaylist(r);
    expect(await tabletPlaylist(), expected);
    // The same zip again: an update, with nothing to unpack.
    final again = await importPackage(zip, update);
    expect((again.copied, again.kept), (0, 4));
  });

  test('over the Wi-Fi: the PC sends, the tablet receives with the code', () async {
    final sender = PlaylistSender(pkg, port: 0, code: '4821');
    await sender.start();
    addTearDown(sender.stop);
    await expectLater(
      receivePackage('127.0.0.1', '1111', update, port: sender.boundPort),
      throwsA(isA<TransferException>()),
    );
    final seen = <String>[];
    final r = await receivePackage('127.0.0.1', '4821', update,
        port: sender.boundPort, onProgress: (d, t, f) => seen.add(f));
    expect(seen, contains('Abba - Waterloo.cdg'));
    expect(sender.bytesSent, pkg.totalBytes);
    expect(sender.finished, isTrue);
    expect(File(p.join(r.plan.folder, manifestName)).existsSync(), isTrue);
    expect(Directory(p.join(r.plan.folder, 'songs')).listSync().where((f) => f.path.endsWith('.part')), isEmpty);
    await tablet.addImportedPlaylist(r);
    expect(await tabletPlaylist(), expected);
    expect(jsonDecode(File(p.join(r.plan.folder, manifestName)).readAsStringSync())['eztiger_playlist'], 1);

    // Sent again: the tablet already has every song, so none is sent.
    final sent = sender.bytesSent;
    final again = await receivePackage('127.0.0.1', '4821', update, port: sender.boundPort);
    expect((again.copied, again.kept), (0, 4));
    expect(sender.bytesSent, sent); // marked done, nothing more sent
  });
}