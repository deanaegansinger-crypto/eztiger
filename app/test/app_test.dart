import 'dart:io';

import 'package:eztiger/app_state.dart';
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

  setUp(() async {
    lib = makeLibrary();
    db = await EztigerDatabase.open(databaseFactoryFfiNoIsolate, inMemoryDatabasePath);
    backend = FakeBackend();
    state = AppState(db, KaraokeEngine(backend));
  });

  tearDown(() async {
    await db.close();
    lib.deleteSync(recursive: true);
  });

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

  testWidgets('shows the library, searches and queues a song', (tester) async {
    await pumpApp(tester);
    expect(find.text('EZTIGER'), findsWidgets);
    expect(find.text('Waterloo'), findsOneWidget);
    expect(find.text('Bohemian Rhapsody'), findsOneWidget);
    expect(find.textContaining('3 matches'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'prayer');
    await tester.pump(const Duration(milliseconds: 200)); // the search debounce
    await tester.runAsync(state.refreshResults);
    await tester.pump();
    expect(find.textContaining('1 match'), findsOneWidget);
    expect(find.text('Livin On A Prayer'), findsOneWidget);

    await tester.runAsync(() => state.enqueue(state.results.first.primary));
    await tester.pump();
    expect(find.textContaining('QUEUE · 1 SONG'), findsOneWidget);
    // Autocue loads the first song paused.
    expect(state.engine.current?.title, 'Livin On A Prayer');
    expect(backend.calls, contains('pause'));
  });

  testWidgets('next marks the song sung and plays the next one', (tester) async {
    await pumpApp(tester);
    final tracks = state.results.map((g) => g.primary).toList();
    await tester.runAsync(() async {
      await state.enqueue(tracks[0], singer: 'Dean');
      await state.enqueue(tracks[1]);
      await state.playPause();
      await state.next();
    });
    await tester.pump();
    expect(state.queue.length, 1);
    expect(state.engine.current?.id, tracks[1].id);
    final sung = await tester.runAsync(() => db.history.recent());
    expect(sung!.single.singer, 'Dean');
  });

  testWidgets('autoplay starts the next song when one finishes', (tester) async {
    await pumpApp(tester);
    final tracks = state.results.map((g) => g.primary).toList();
    state.setMode(PlayMode.autoplay);
    await tester.runAsync(() async {
      await state.enqueue(tracks[0]);
      await state.enqueue(tracks[1]);
      await state.playEntry(state.queue.first);
      backend.calls.clear();
      backend.finish();
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    expect(state.engine.current?.id, tracks[1].id);
    expect(backend.calls.last, 'play');
  });

  testWidgets('edit tags saves a new title', (tester) async {
    await pumpApp(tester);
    final t = state.results.firstWhere((g) => g.primary.title == 'Waterloo').primary;
    await tester.runAsync(() => state.editTags(t, title: 'Waterloo (Live)', artist: 'ABBA', type: TrackType.cdg));
    await tester.pump();
    expect(find.text('Waterloo (Live)'), findsOneWidget);
    expect(find.text('ABBA'), findsOneWidget);
  });

  testWidgets('light mode switches the theme', (tester) async {
    await pumpApp(tester);
    await tester.tap(find.text('Light'));
    await tester.pump();
    expect(state.dark, isFalse);
  });
}
