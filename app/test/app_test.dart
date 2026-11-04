import 'dart:io';

import 'package:eztiger/app_state.dart';
import 'package:eztiger/player.dart';
import 'package:eztiger/ui/app.dart';
import 'package:eztiger/ui/common.dart';
import 'package:eztiger/ui/queue_panel.dart';
import 'package:eztiger/ui/rack.dart';
import 'package:eztiger_core/eztiger_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

  testWidgets('shift-click selects a block, and dragging it queues them all', (tester) async {
    await pumpApp(tester);
    final rows = find.byType(ResultRow);
    await tester.tap(rows.at(0));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.tap(rows.at(2));
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pump(const Duration(milliseconds: 400));
    expect(state.selection, {0, 1, 2});
    expect(find.textContaining('3 selected'), findsOneWidget);

    final g = await tester.startGesture(tester.getCenter(rows.at(1)));
    await tester.pump();
    await g.moveBy(const Offset(400, -200));
    await tester.pump();
    await g.moveTo(tester.getCenter(find.byType(QueuePanel)));
    await tester.pump();
    await tester.runAsync(() async {
      await g.up();
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pump();
    expect(state.queue.length, 3);
    // The block stays selected after a drag.
    expect(state.selection, {0, 1, 2});
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('a block becomes a new playlist, and copy and paste fills another', (tester) async {
    await pumpApp(tester);
    state.selectRow(0);
    state.selectRow(2, shift: true);
    final block = state.selectedTracks();
    expect(block, hasLength(3));
    await tester.runAsync(() => state.createPlaylist('Friday', tracks: block));
    expect(state.playlists.single.trackCount, 3);

    final text = state.copy(block.sublist(0, 2));
    final pasted = await tester.runAsync(() => state.songsFromClipboard(text.replaceAll('\r\n', '\n')));
    expect(pasted, block.sublist(0, 2));

    final id = await tester.runAsync(() => state.createPlaylist('Set list'));
    await tester.runAsync(() => state.paste(id!, '1. Waterloo\n2. Nothing called this\n3. bohemian rhapsody'));
    final list = await tester.runAsync(() => db.playlists.tracks(id!));
    expect(list!.map((t) => t.title), ['Waterloo', 'Bohemian Rhapsody']);
    expect(state.status, 'Pasted 2 of 3 lines · not found: Nothing called this');

    await tester.runAsync(() => state.openPlaylist(state.playlists.firstWhere((p) => p.name == 'Friday')));
    state.selectRow(0);
    state.selectRow(1, ctrl: true);
    await tester.runAsync(state.removeSelectedFromPlaylist);
    expect(state.results, hasLength(1));
  });

  testWidgets('the seek bar skips through the song', (tester) async {
    await pumpApp(tester);
    await tester.runAsync(() => state.playNow(state.results.first.primary));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pump();
    expect(state.engine.duration, const Duration(minutes: 3));
    final bar = find.byKey(const Key('seek'));
    final box = tester.getRect(bar);
    await tester.runAsync(() async {
      await tester.tapAt(Offset(box.left + box.width * 0.5, box.center.dy));
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pump();
    final at = backend.seeks.last;
    expect(at.inSeconds, inInclusiveRange(80, 100)); // about half way through 3:00
  });

  testWidgets('dropping songs on the player loads the first paused and queues the rest next', (tester) async {
    await pumpApp(tester);
    final tracks = state.results.map((g) => g.primary).toList();
    await tester.runAsync(() async {
      await state.enqueue(tracks[0]);
      await state.dropOnPlayer(SongDrag([tracks[1], tracks[2]]));
    });
    expect(state.engine.current?.id, tracks[1].id);
    expect(backend.calls.last, 'pause'); // loaded paused, ready to go
    expect(state.queue.map((e) => e.track.id), [tracks[2].id, tracks[0].id]);

    // A drag from the results onto the player.
    await tester.pump();
    final g = await tester.startGesture(tester.getCenter(find.byType(ResultRow).at(0)));
    await tester.pump();
    await g.moveBy(const Offset(30, -30));
    await tester.pump();
    await g.moveTo(tester.getCenter(find.byType(PlayerStrip)) - const Offset(80, 0));
    await tester.pump();
    expect(find.text('DROP TO PLAY NOW'), findsOneWidget);
    await tester.runAsync(() async {
      await g.up();
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pump(const Duration(seconds: 1));
    expect(state.engine.current?.id, tracks[0].id);
  });

  testWidgets('songs drop into a playlist or the queue at a chosen spot', (tester) async {
    await pumpApp(tester);
    final tracks = state.results.map((g) => g.primary).toList();
    final id = await tester.runAsync(() => state.createPlaylist('Set', tracks: [tracks[0], tracks[1]]));
    await tester.runAsync(() => state.dropIntoPlaylist(id!, SongDrag([tracks[2]]), 1));
    var list = await tester.runAsync(() => db.playlists.tracks(id!));
    expect(list!.map((t) => t.id), [tracks[0].id, tracks[2].id, tracks[1].id]);
    // Dragging within the playlist moves instead of copying.
    await tester.runAsync(() => state.dropIntoPlaylist(id!, SongDrag([tracks[0]], playlistId: id, positions: [0]), 3));
    list = await tester.runAsync(() => db.playlists.tracks(id!));
    expect(list!.map((t) => t.id), [tracks[2].id, tracks[1].id, tracks[0].id]);

    await tester.runAsync(() async {
      await state.enqueue(tracks[0]);
      await state.enqueue(tracks[1]);
      await state.dropIntoQueue(SongDrag([tracks[2]]), 1);
    });
    expect(state.queue.map((e) => e.track.id), [tracks[0].id, tracks[2].id, tracks[1].id]);
    final last = state.queue.last;
    await tester.runAsync(() => state.dropIntoQueue(SongDrag([last.track], queueIds: [last.id]), 0));
    expect(state.queue.map((e) => e.track.id), [tracks[1].id, tracks[0].id, tracks[2].id]);
  });

  testWidgets('the player display follows the player by itself', (tester) async {
    await pumpApp(tester);
    await tester.runAsync(() => state.playNow(state.results.first.primary));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pump();
    expect(find.byIcon(Icons.pause), findsOneWidget);
    // Only the player changes from here on: no AppState notifications.
    await tester.runAsync(() async {
      await backend.pause();
      backend.at(const Duration(seconds: 65));
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pump();
    expect(find.byIcon(Icons.play_arrow), findsOneWidget);
    expect(find.text('01:05'), findsOneWidget); // seek bar, elapsed
    expect(find.text('-01:55'), findsOneWidget); // seek bar, remaining
    expect(find.textContaining('01:05 / 03:00'), findsOneWidget); // the display
    final slider = tester.widget<Slider>(find.byKey(const Key('seek')));
    expect(slider.value, 65000);
    expect(slider.max, 180000);
  });

  testWidgets('Space plays and pauses, but types a space in the search box', (tester) async {
    await pumpApp(tester);
    await tester.runAsync(() => state.playNow(state.results.first.primary, autostart: false));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pump();
    expect(state.engine.playing, isFalse);
    await tester.runAsync(() async {
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pump();
    expect(state.engine.playing, isTrue);
    expect(find.byIcon(Icons.pause), findsOneWidget);

    // Typing in the search box keeps the space and doesn't pause.
    await tester.tap(find.byType(TextField));
    await tester.pump();
    final calls = backend.calls.length;
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump(const Duration(milliseconds: 200));
    expect(backend.calls.length, calls);
    expect(state.engine.playing, isTrue);
  });

  testWidgets('filter by file type, and sort A to Z by title or artist', (tester) async {
    await pumpApp(tester);
    await tester.runAsync(() async {
      await tester.tap(find.descendant(of: find.byKey(const Key('type-filter')), matching: find.text('MP4')));
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pump();
    expect(state.results.map((g) => g.primary.title), ['Bohemian Rhapsody']);

    await tester.runAsync(() => state.setTypeFilter(null));
    await tester.runAsync(() async {
      await tester.tap(find.descendant(of: find.byKey(const Key('sort')), matching: find.text('Artist A–Z')));
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pump();
    expect(state.results.map((g) => g.primary.artist), ['Abba', 'Bon Jovi', 'Queen']);
    await tester.runAsync(() => state.setSort(SearchSort.title));
    expect(state.results.map((g) => g.primary.title), ['Bohemian Rhapsody', 'Livin On A Prayer', 'Waterloo']);
    await tester.pump();
  });

  testWidgets('autocue loads the top of the queue whenever the player is empty', (tester) async {
    await pumpApp(tester);
    final tracks = state.results.map((g) => g.primary).toList();
    state.toggleAutocue(); // off
    await tester.runAsync(() async {
      await state.enqueue(tracks[0]);
      await state.enqueue(tracks[1]);
    });
    expect(state.engine.current, isNull);
    // Turning it on with songs already waiting cues the first one.
    await tester.runAsync(() async {
      state.toggleAutocue();
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    expect(state.engine.current?.id, tracks[0].id);
    expect(state.engine.playing, isFalse);
    // Removing the loaded song cues the next one.
    await tester.runAsync(() => state.removeFromQueue(state.queue.first));
    expect(state.engine.current?.id, tracks[1].id);
    expect(state.engine.playing, isFalse);
  });

  testWidgets('crossfade fades into the next song, in single mode too, without skipping', (tester) async {
    await pumpApp(tester);
    final tracks = state.results.map((g) => g.primary).toList();
    expect(state.mode, PlayMode.single);
    state.toggleCrossfade();
    await tester.runAsync(() async {
      for (final t in tracks) {
        await state.enqueue(t);
      }
      await state.playEntry(state.queue.first);
      backend.at(const Duration(minutes: 2, seconds: 59)); // 1 second left
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(backend.volume, lessThan(80)); // fading out
      backend.finish(); // the song ends while it fades
      await Future<void>.delayed(const Duration(milliseconds: 1200));
    });
    expect(state.engine.current?.id, tracks[1].id, reason: 'moves on exactly one song');
    expect(state.engine.playing, isTrue);
    expect(state.queue.length, 2);
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 2300)));
    expect(backend.volume, 80); // faded back in
  });

  testWidgets('double-clicking a song in the list loads it paused', (tester) async {
    await pumpApp(tester);
    // An MP3 with no CDG, so the load touches no files on disk.
    final row = find.widgetWithText(ResultRow, 'Livin On A Prayer');
    await tester.tap(row);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(row);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pump();
    expect(state.engine.current?.title, 'Livin On A Prayer');
    expect(backend.calls, contains('pause'));
    expect(state.engine.playing, isFalse);
    expect(state.queue, isEmpty);
  });

  testWidgets('a queue left from last time is cued after start-up', (tester) async {
    await pumpApp(tester);
    final t = state.results.first.primary;
    state.toggleAutocue(); // off, so adding doesn't cue
    await tester.runAsync(() => state.enqueue(t));
    // A fresh start: init must not load a song (the window isn't up yet).
    final fresh = AppState(db, KaraokeEngine(FakeBackend()));
    await tester.runAsync(fresh.init);
    expect(fresh.engine.current, isNull);
    fresh.autocue = true;
    await tester.runAsync(fresh.startUp);
    expect(fresh.engine.current?.id, t.id);
    expect(fresh.engine.playing, isFalse);
  });

  testWidgets('settings and the loaded song come back next time', (tester) async {
    await pumpApp(tester);
    final t = state.results.firstWhere((g) => g.primary.title == 'Livin On A Prayer').primary;
    await tester.runAsync(() async {
      state.setMode(PlayMode.autoplay);
      state.toggleCrossfade();
      await state.engine.setVolume(55);
      await state.playNow(t, autostart: false);
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    final fresh = AppState(db, KaraokeEngine(FakeBackend()));
    await tester.runAsync(() async {
      await fresh.init();
      await fresh.startUp();
    });
    expect(fresh.mode, PlayMode.autoplay);
    expect(fresh.crossfade, isTrue);
    expect(fresh.engine.volume, 55);
    expect(fresh.engine.current?.id, t.id);
    expect(fresh.engine.playing, isFalse);
  });
}
