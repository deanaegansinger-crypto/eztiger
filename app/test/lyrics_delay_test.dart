import 'dart:io';

import 'package:eztiger/app_state.dart';
import 'package:eztiger/edition.dart';
import 'package:eztiger/player.dart';
import 'package:eztiger/ui/app.dart';
import 'package:eztiger_core/eztiger_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'fakes.dart';

void main() {
  sqfliteFfiInit();
  late Directory lib;
  late EztigerDatabase db;
  late FakeBackend backend;
  late AppState state;
  Future<AudioEdges?> scan(String path) async => null;

  setUp(() async {
    isPro = true;
    lib = makeLibrary();
    db = await EztigerDatabase.open(databaseFactoryFfiNoIsolate, inMemoryDatabasePath);
    backend = FakeBackend();
    state = AppState(db, KaraokeEngine(backend, scanEdges: scan));
  });

  tearDown(() async {
    await db.close();
    lib.deleteSync(recursive: true);
  });

  Track song(String name) => state.results.map((g) => g.primary).firstWhere((t) => t.fileName.contains(name));

  Future<void> pumpApp(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1400, 860);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.runAsync(() async {
      await state.init();
      await state.addRootFolder(lib.path);
    });
    await tester.pumpWidget(EztigerApp(state: state));
    await tester.pump();
  }

  testWidgets('the CDG lyrics follow the sound, held back by the delay', (tester) => tester.runAsync(() async {
    await state.init();
    await state.addRootFolder(lib.path);
    await state.playNow(song('Waterloo'), autostart: false);
    final e = state.engine;
    backend.at(const Duration(seconds: 10));
    await Future<void>.delayed(Duration.zero);
    expect(e.lyricsPosition, const Duration(seconds: 10)); // off: in step

    state.setLyricsDelayMs(250);
    await Future<void>.delayed(Duration.zero);
    expect(state.lyricsDelayOn, isTrue);
    expect(e.lyricsPosition, const Duration(milliseconds: 9750));
    expect(backend.videoDelay, Duration.zero); // a CDG song: the player's picture isn't touched

    // Near the start it never goes before the beginning.
    backend.at(const Duration(milliseconds: 100));
    await Future<void>.delayed(Duration.zero);
    expect(e.lyricsPosition, Duration.zero);

    // Off keeps the time set, for switching on again.
    state.setLyricsDelayOn(false);
    await Future<void>.delayed(Duration.zero);
    expect(e.lyricsDelay, Duration.zero);
    expect(state.lyricsDelayMs, 250);
  }));

  testWidgets('a video is held back by the player, and only while the delay is on', (tester) => tester.runAsync(() async {
    await state.init();
    await state.addRootFolder(lib.path);
    state.setLyricsDelayMs(300);
    await state.playNow(song('Bohemian'), autostart: false);
    expect(backend.videoDelay, const Duration(milliseconds: 300));
    state.setLyricsDelayOn(false);
    await Future<void>.delayed(Duration.zero);
    expect(backend.videoDelay, Duration.zero);
    state.setLyricsDelayOn(true);
    await Future<void>.delayed(Duration.zero);
    expect(backend.videoDelay, const Duration(milliseconds: 300));

    // An audio song after it puts the player back in step.
    await state.playNow(song('Waterloo'), autostart: false);
    expect(backend.videoDelay, Duration.zero);
  }));

  testWidgets('the time stays between 0 and 1 second', (tester) => tester.runAsync(() async {
    await state.init();
    state.setLyricsDelayMs(5000);
    expect(state.lyricsDelayMs, AppState.maxLyricsDelayMs);
    state.setLyricsDelayMs(-20);
    expect(state.lyricsDelayMs, 0);
  }));

  testWidgets('the button by the volume switches it, and it is remembered', (tester) async {
    await pumpApp(tester);
    expect(find.text('Delay'), findsWidgets);
    await tester.tap(find.byKey(const Key('lyrics-delay')));
    await tester.pump();
    expect(state.lyricsDelayOn, isTrue);
    expect(find.text('+0.20s'), findsOneWidget);

    // Press and hold to set the time.
    await tester.longPress(find.byKey(const Key('lyrics-delay')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('lyrics-delay-value')), findsOneWidget);
    await tester.tap(find.byKey(const Key('lyrics-delay-step50')));
    await tester.tap(find.byKey(const Key('lyrics-delay-step10')));
    await tester.pump();
    expect(state.lyricsDelayMs, 260);
    expect(find.text('0.26 s'), findsOneWidget);
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(find.text('+0.26s'), findsOneWidget);

    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 50));
      final again = AppState(db, KaraokeEngine(FakeBackend(), scanEdges: scan));
      await again.init(rescanLibrary: false);
      expect(again.lyricsDelayOn, isTrue);
      expect(again.lyricsDelayMs, 260);
      expect(again.engine.lyricsDelay, const Duration(milliseconds: 260));
    });

    // A tap switches it off again, keeping the time.
    await tester.tap(find.byKey(const Key('lyrics-delay')));
    await tester.pump();
    expect(state.lyricsDelayOn, isFalse);
    expect(state.lyricsDelayMs, 260);
    expect(find.text('Delay'), findsWidgets);
  });
}
