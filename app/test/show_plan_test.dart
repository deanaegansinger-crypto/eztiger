import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:eztiger/app_state.dart';
import 'package:eztiger/edition.dart';
import 'package:eztiger/player.dart';
import 'package:eztiger/playlist_transfer.dart';
import 'package:eztiger/preview.dart';
import 'package:eztiger/show_plan.dart';
import 'package:eztiger/ui/app.dart';
import 'package:eztiger/ui/show_planner.dart';
import 'package:eztiger_core/eztiger_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'fakes.dart';

class FakePreview implements PreviewOutput {
  final played = <String>[];
  final keys = <int>[];
  String device = 'auto';
  final _dur = StreamController<Duration>.broadcast();
  final _playing = StreamController<bool>.broadcast();

  @override
  Future<List<PreviewDevice>> devices() async => const [(id: 'auto', name: 'Windows sound output'), (id: 'wasapi/phones', name: 'Headphones')];
  @override
  Future<void> setDevice(String id) async => device = id;
  @override
  Future<void> play(String path, {int key = 0, Duration start = Duration.zero}) async {
    played.add(p.basename(path));
    keys.add(key);
    _playing.add(true);
    _dur.add(const Duration(minutes: 4, seconds: 2));
  }

  @override
  Future<void> stop() async => _playing.add(false);
  @override
  Stream<Duration> get duration => _dur.stream;
  @override
  Stream<bool> get playing => _playing.stream;
  @override
  Future<void> dispose() async {}
}

void main() {
  sqfliteFfiInit();

  group('the plan', () {
    ShowPlan plan() => ShowPlan(start: '9pm', items: [
          ShowItem.song('/m/a.mp3', note: 'warm up'),
          ShowItem.song('/m/b.mp3'),
          ShowItem.interval(minutes: 20, music: ['/m/break.mp3']),
          ShowItem.song('/m/c.mp3'),
          ShowItem.song('/m/d.mp3', note: 'big finish'),
        ]);

    test('matched to the playlist: notes stay with songs, intervals after theirs', () {
      // b came off, e went on the end, d moved to the top.
      final x = plan().matchedTo(['/m/d.mp3', '/m/a.mp3', '/m/c.mp3', '/m/e.mp3']);
      expect([for (final i in x.items) i.isBreak ? 'break' : p.basename(i.path!)],
          ['d.mp3', 'a.mp3', 'break', 'c.mp3', 'e.mp3']);
      expect(x.items[0].note, 'big finish');
      expect(x.items[1].note, 'warm up');
      expect(x.items[2].music, ['/m/break.mp3']);
      expect(x.start, '9pm');
    });

    test('a song in the show twice keeps each copy\'s note', () {
      final x = ShowPlan(items: [ShowItem.song('/m/a.mp3', note: 'one'), ShowItem.song('/m/a.mp3', note: 'two')])
          .matchedTo(['/m/a.mp3', '/m/a.mp3']);
      expect(x.items.map((i) => i.note), ['one', 'two']);
    });

    test('times, sets and the finish', () {
      final x = plan();
      final t = x.times((path) => path.endsWith('c.mp3') ? null : const Duration(minutes: 3));
      expect(t.clockAt(0), '9:00 pm');
      expect(t.clockAt(2), '9:06 pm'); // the interval
      expect(t.clockAt(3), '9:26 pm');
      expect(t.guessed, [false, false, false, true, false]);
      expect(t.total, const Duration(minutes: 3 * 3 + 20 + 3, seconds: 30)); // c guessed at 3:30
      expect(t.finish, '9:32 pm');
      expect(x.sets, [1, 1, 2, 2, 2]);
      expect(x.setCount, 2);
      expect(x.songCount, 4);
    });

    test('start times as people type them', () {
      expect(parseStartTime('9pm'), const Duration(hours: 21));
      expect(parseStartTime('9:15 PM'), const Duration(hours: 21, minutes: 15));
      expect(parseStartTime('21.30'), const Duration(hours: 21, minutes: 30));
      expect(parseStartTime('12am'), Duration.zero);
      expect(parseStartTime('soon'), isNull);
      expect(parseStartTime('13pm'), isNull);
      expect(clockTime(const Duration(hours: 23, minutes: 50) + const Duration(minutes: 20)), '12:10 am');
      expect(showLengthWords(const Duration(minutes: 85)), '1 hr 25 min');
    });

    test('saved and read back', () {
      final x = ShowPlan.fromJson(plan().toJson());
      expect(x.start, '9pm');
      expect(x.items[2].isBreak, isTrue);
      expect(x.items[2].music, ['/m/break.mp3']);
      expect(x.items[4].note, 'big finish');
    });
  });

  group('song lengths from the files', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('ezt_lengths'));
    tearDown(() => dir.deleteSync(recursive: true));

    test('a CDG: 300 packets of 24 bytes a second', () {
      final mp3 = File(p.join(dir.path, 'a.mp3'))..writeAsBytesSync([0]);
      File(p.join(dir.path, 'a.cdg')).writeAsBytesSync(Uint8List(24 * 300 * 65));
      expect(estimateLength(mp3.path), const Duration(seconds: 65));
    });

    test('an MP3 at a steady bit rate', () {
      final b = Uint8List(16000);
      b.setAll(0, [0xff, 0xfb, 0x90, 0x00]); // MPEG-1 layer III, 128 kbit/s, 44.1 kHz
      final f = File(p.join(dir.path, 'b.mp3'))..writeAsBytesSync(b);
      expect(estimateLength(f.path), const Duration(seconds: 1));
    });

    test('a VBR MP3, from its Xing header', () {
      final b = Uint8List(5000);
      b.setAll(0, [0xff, 0xfb, 0x90, 0x00]);
      b.setAll(36, 'Xing'.codeUnits);
      b.setAll(40, [0, 0, 0, 1]); // frame count present
      b.setAll(44, [0, 0, 0x03, 0xe8]); // 1000 frames of 1152 samples
      final f = File(p.join(dir.path, 'c.mp3'))..writeAsBytesSync(b);
      expect(estimateLength(f.path)!.inMilliseconds, 26122);
    });

    test('a WAV', () {
      final d = ByteData(44 + 176400);
      void tag(int at, String s) => Uint8List.sublistView(d).setAll(at, s.codeUnits);
      tag(0, 'RIFF');
      tag(8, 'WAVE');
      tag(12, 'fmt ');
      d.setUint32(16, 16, Endian.little);
      d.setUint32(28, 176400, Endian.little);
      tag(36, 'data');
      d.setUint32(40, 176400, Endian.little);
      final f = File(p.join(dir.path, 'd.wav'))..writeAsBytesSync(d.buffer.asUint8List());
      expect(estimateLength(f.path), const Duration(seconds: 1));
    });

    test('a video: not known', () {
      final f = File(p.join(dir.path, 'e.mp4'))..writeAsBytesSync([1, 2, 3]);
      expect(estimateLength(f.path), isNull);
    });
  });

  group('a planned show, PC to tablet', () {
    late Directory lib, out, tabletDir;
    late EztigerDatabase pcDb, tabDb;
    late AppState pc, tablet;
    late Map<String, Track> all;
    late int id;

    setUp(() async {
      isPro = true;
      lib = makeLibrary();
      File(p.join(lib.path, 'Breaks', 'Elevator Music.mp3'))
        ..parent.createSync(recursive: true)
        ..writeAsBytesSync(List.filled(30, 0));
      out = Directory.systemTemp.createTempSync('ezt_show_export');
      tabletDir = Directory.systemTemp.createTempSync('ezt_show_tablet');
      pcDb = await EztigerDatabase.open(databaseFactoryFfiNoIsolate, inMemoryDatabasePath);
      tabDb = await EztigerDatabase.open(databaseFactoryFfiNoIsolate, inMemoryDatabasePath);
      pc = AppState(pcDb, KaraokeEngine(FakeBackend(), scanEdges: (_) async => null));
      tablet = AppState(tabDb, KaraokeEngine(FakeBackend(), scanEdges: (_) async => null));
      await pc.init(rescanLibrary: false);
      await pc.addRootFolder(lib.path);
      await tablet.init(rescanLibrary: false);
      tablet.importsRootOverride = p.join(tabletDir.path, 'EZTiger imports');
      all = {for (final g in pc.results) g.primary.fileName: g.primary};
      final waterloo = all['Abba - Waterloo.mp3']!, prayer = all['Bon Jovi - Livin On A Prayer.mp3']!;
      final queen = all['Queen - Bohemian Rhapsody.mp4']!;
      id = (await pc.createPlaylist('Saturday', tracks: [waterloo, prayer, queen]))!;
      final plan = await pc.planFor(id);
      plan.start = '8:30 pm';
      plan.items[0].note = 'Say hello first';
      plan.items.insert(2, ShowItem.interval(minutes: 15, label: 'Bingo', music: [all['Elevator Music.mp3']!.path]));
      await pc.savePlan(id, plan, [waterloo, prayer, queen]);
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

    test('the PC keeps the plan, and Tonight\'s playlist gets the break music in its place', () async {
      expect(pc.showPlans[id]!.items[2].label, 'Bingo');
      expect(pc.noteFor(all['Abba - Waterloo.mp3']!), 'Say hello first');
      expect(pc.intervalOf(all['Elevator Music.mp3']!), 'Bingo · 15 min');
      expect((await pc.showTracks(id)).map((t) => t.title), ['Waterloo', 'Livin On A Prayer', 'Elevator Music', 'Bohemian Rhapsody']);
      // The playlist itself holds just the songs.
      expect((await pcDb.playlists.tracks(id)).map((t) => t.title), ['Waterloo', 'Livin On A Prayer', 'Bohemian Rhapsody']);

      await pc.loadPlaylistIntoQueue(id);
      expect(pc.queue.map((e) => e.track.title), ['Waterloo', 'Livin On A Prayer', 'Elevator Music', 'Bohemian Rhapsody']);
      // Saving the queue back keeps the break music out of the songs.
      await pc.replacePlaylistWithQueue(id);
      expect((await pcDb.playlists.tracks(id)).map((t) => t.title), ['Waterloo', 'Livin On A Prayer', 'Bohemian Rhapsody']);
    });

    test('a song taken off on the PC (not in the planner) leaves the plan tidy', () async {
      await pcDb.playlists.removeAt(id, 1); // Livin On A Prayer
      final x = await pc.planFor(id);
      expect([for (final i in x.items) i.isBreak ? i.label : p.basenameWithoutExtension(i.path!)],
          ['Abba - Waterloo', 'Bingo', 'Queen - Bohemian Rhapsody']);
    });

    test('exported and imported: the tablet gets the songs, the break music, the notes and the times', () async {
      final pkg = await pc.packageFor(pc.playlists.firstWhere((x) => x.id == id));
      expect(pkg.fileNames, contains('Elevator Music.mp3'));
      expect(pkg.songs.first.note, 'Say hello first');
      expect(pkg.songs.first.length, const Duration(seconds: 1)); // its CDG: 300 packets
      final folder = await exportToFolder(pkg, out.path);
      final r = await importPackage(folder, (x) async => tablet.importPlan(x));
      await tablet.addImportedPlaylist(r);

      final tid = tablet.playlists.single.id;
      expect((await tabDb.playlists.tracks(tid)).map((t) => t.title), ['Waterloo', 'Livin On A Prayer', 'Bohemian Rhapsody']);
      final plan = tablet.showPlans[tid]!;
      expect(plan.start, '8:30 pm');
      expect(plan.items[2].label, 'Bingo');
      expect(p.basename(plan.items[2].music.single), 'Elevator Music.mp3');
      expect(File(plan.items[2].music.single).existsSync(), isTrue);
      expect((await tablet.showTracks(tid)).map((t) => t.title), ['Waterloo', 'Livin On A Prayer', 'Elevator Music', 'Bohemian Rhapsody']);
      final waterloo = (await tabDb.playlists.tracks(tid)).first;
      expect(tablet.noteFor(waterloo), 'Say hello first');
      expect(tablet.lengthOfPath(waterloo.path), const Duration(seconds: 1));
      final times = plan.times(tablet.lengthOfPath);
      expect(times.clockAt(0), '8:30 pm');
      expect(times.clockAt(3), '8:48 pm'); // after 0:01 + 3:30 guessed + 15 min

      // Sent again with one song gone: only the plan changes, nothing is copied.
      await pc.savePlan(id, (await pc.planFor(id))..items.removeAt(1), [all['Abba - Waterloo.mp3']!, all['Queen - Bohemian Rhapsody.mp4']!]);
      out.deleteSync(recursive: true);
      out.createSync();
      final again = await importPackage(
        await exportToFolder(await pc.packageFor(pc.playlists.firstWhere((x) => x.id == id)), out.path),
        (x) async => tablet.importPlan(x),
      );
      expect(again.copied, 0);
      await tablet.addImportedPlaylist(again);
      final tid2 = tablet.playlists.single.id;
      expect(tablet.showPlans[tid2]!.songCount, 2);
      expect(tablet.showPlans.length, 1, reason: 'the old plan went with the old playlist');
    });

    test('a playlist deleted takes its plan with it', () async {
      await pc.deletePlaylist(pc.playlists.firstWhere((x) => x.id == id));
      expect(pc.showPlans, isEmpty);
      expect(pc.intervalOf(all['Elevator Music.mp3']!), isNull);
    });

    test('preview: in the planned key, and its length remembered', () async {
      final fake = FakePreview();
      pc.attachPreview(fake);
      final waterloo = all['Abba - Waterloo.mp3']!;
      pc.setKeyForPath(waterloo.path, 2);
      await pc.togglePreview(waterloo.path);
      await Future<void>.delayed(Duration.zero);
      expect(fake.played, ['Abba - Waterloo.mp3']);
      expect(fake.keys, [2]);
      expect(pc.previewing, waterloo.path);
      expect(pc.lengthOfPath(waterloo.path), const Duration(minutes: 4, seconds: 2));
      await pc.togglePreview(waterloo.path); // again: stops
      expect(pc.previewing, isNull);
      await pc.setPreviewDevice('wasapi/phones');
      expect(fake.device, 'wasapi/phones');
    });
  });

  testWidgets('the planner: add an interval, change a key, take a song out', (tester) async {
    isPro = true;
    tester.view.physicalSize = const Size(1400, 860);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final lib = makeLibrary();
    final db = await tester.runAsync(() => EztigerDatabase.open(databaseFactoryFfiNoIsolate, inMemoryDatabasePath));
    final s = AppState(db!, KaraokeEngine(FakeBackend(), scanEdges: (_) async => null));
    final fake = FakePreview();
    late int id;
    await tester.runAsync(() async {
      await s.init(rescanLibrary: false);
      await s.addRootFolder(lib.path);
      s.attachPreview(fake);
      final all = {for (final g in s.results) g.primary.fileName: g.primary};
      id = (await s.createPlaylist('Friday', tracks: [all['Abba - Waterloo.mp3']!, all['Bon Jovi - Livin On A Prayer.mp3']!]))!;
    });
    addTearDown(() async {
      await tester.runAsync(() async {
        s.dispose();
        await db.close();
        lib.deleteSync(recursive: true);
      });
    });
    await tester.pumpWidget(EztigerApp(state: s));
    await tester.pump();

    final pl = s.playlists.firstWhere((x) => x.id == id);
    unawaited(showShowPlanner(tester.element(find.byType(Scaffold).first), pl));
    Future<void> settle() async {
      for (var i = 0; i < 3; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
        await tester.pump(const Duration(milliseconds: 500));
      }
    }

    await settle();
    expect(find.byKey(const Key('show-planner')), findsOneWidget);
    expect(find.byKey(const Key('planner-row-1')), findsOneWidget);

    // An interval after the first song.
    await tester.tap(find.byKey(const Key('planner-row-0')));
    // (A song row waits to see if it's a double-click, for its note.)
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.byKey(const Key('planner-add-interval')));
    await settle();
    expect(s.showPlans[id]!.items[1].isBreak, isTrue);
    expect(tester.widget<Text>(find.byKey(const Key('planner-summary'))).data, contains('2 sets'));

    // The last song a key up, then heard in that key.
    await tester.tap(find.byKey(const Key('planner-key-up-2')));
    await tester.pump();
    expect(tester.widget<Text>(find.byKey(const Key('planner-key-2'))).data, '+1');

    // Taken out.
    await tester.tap(find.byKey(const Key('planner-remove-2')));
    await settle();
    expect(s.showPlans[id]!.songCount, 1);
    final left = await tester.runAsync(() => db.playlists.tracks(id));
    expect(left!.map((t) => t.title), ['Waterloo']);

    await tester.tap(find.byKey(const Key('planner-done')));
    await settle();
    expect(find.byKey(const Key('show-planner')), findsNothing);
  });
}
