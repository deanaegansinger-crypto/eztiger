import 'dart:io';

import 'package:eztiger/app_state.dart';
import 'package:eztiger/edition.dart';
import 'package:eztiger/licence.dart';
import 'package:eztiger/ui/pro_sound.dart';
import 'package:eztiger/platform.dart';
import 'package:eztiger/player.dart';
import 'package:eztiger/theme.dart';
import 'package:eztiger/ui/app.dart';
import 'package:eztiger/ui/output_panel.dart';
import 'package:eztiger/ui/common.dart';
import 'package:eztiger/ui/queue_panel.dart';
import 'package:eztiger/ui/rack.dart';
import 'package:eztiger/ui/stage_view.dart';
import 'package:eztiger/ui/logo.dart';
import 'package:eztiger/ui/twin_decks.dart';
import 'package:eztiger_core/eztiger_core.dart';
import 'package:flutter/gestures.dart';
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

  /// Where the music starts and ends, by file name (none: unknown).
  final edges = <String, AudioEdges>{};
  Future<AudioEdges?> scan(String path) async => edges[path.split(RegExp(r'[\\/]')).last];

  setUp(() async {
    // The tests try EZTiger Pro, which has everything Basic has and more;
    // the Basic tests switch it off.
    isPro = true;
    edges.clear();
    lib = makeLibrary();
    db = await EztigerDatabase.open(databaseFactoryFfiNoIsolate, inMemoryDatabasePath);
    backend = FakeBackend();
    state = AppState(db, KaraokeEngine(backend, scanEdges: scan));
  });

  tearDown(() async {
    EzSkin.current = EzSkin.classic;
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

  group('EZTiger Pro sound', () {
    testWidgets('key change: up to 3 semitones, remembered for the song, and a warning on load', (tester) async {
      await pumpApp(tester);
      final tracks = state.results.map((g) => g.primary).toList();
      await tester.runAsync(() => state.playNow(tracks[0], autostart: false));
      await tester.pump();
      expect(find.byType(ProSoundRow), findsOneWidget);
      expect(find.byKey(const Key('key-warning')), findsNothing);
      expect(backend.audioFilter, '');

      for (var i = 0; i < 5; i++) {
        await tester.tap(find.byKey(const Key('key-up')), warnIfMissed: false);
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
        await tester.pump();
      }
      expect(state.engine.keyShift, 3); // no further than 3 up
      expect(find.text('+3'), findsOneWidget);
      expect(backend.pitch, closeTo(1.189207, 1e-6)); // 3 semitones up
      expect(backend.audioFilter, ''); // the key needs no ffmpeg filter
      for (var i = 0; i < 8; i++) {
        await tester.tap(find.byKey(const Key('key-down')), warnIfMissed: false);
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
        await tester.pump();
      }
      expect(state.engine.keyShift, -3); // no further than 3 down
      await tester.tap(find.byKey(const Key('key-up')));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump();
      expect(state.engine.keyShift, -2);

      // Another song plays in its own key...
      await tester.runAsync(() => state.playNow(tracks[1], autostart: false));
      await tester.pump();
      expect(state.engine.keyShift, 0);
      expect(backend.pitch, 1);
      expect(find.byKey(const Key('key-warning')), findsNothing);

      // ...and the first comes back in its changed key, with the warning.
      await tester.runAsync(() => state.playNow(tracks[0], autostart: false));
      await tester.pump();
      expect(state.engine.keyShift, -2);
      expect(backend.pitch, closeTo(0.890899, 1e-6)); // 2 semitones down
      expect(find.byKey(const Key('key-warning')), findsOneWidget);
      expect(find.text('KEY −2'), findsOneWidget);

      // Remembered after a restart too.
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 50));
        final again = AppState(db, KaraokeEngine(FakeBackend(), scanEdges: scan));
        await again.init(rescanLibrary: false);
        expect(again.keyShifts[tracks[0].path], -2);
      });

      // The 0 in the middle puts it back in its own key, and forgets it.
      await tester.tap(find.byKey(const Key('key-reset')));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump(const Duration(seconds: 1));
      expect(state.engine.keyShift, 0);
      expect(state.keyShifts, isEmpty);
      expect(find.byKey(const Key('key-warning')), findsNothing);
    });

    testWidgets('Level and Vocal cut switch the filters on and are remembered', (tester) async {
      await pumpApp(tester);
      await tester.runAsync(() => state.playNow(state.results.first.primary, autostart: false));
      await tester.pump();
      await tester.tap(find.byKey(const Key('level-loudness')));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump();
      expect(backend.audioFilter, contains('loudnorm'));
      await tester.tap(find.byKey(const Key('vocal-cut')));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump();
      expect(backend.audioFilter, audioFilterChain(levelLoudness: true, vocalCut: true));
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 50));
        final b = FakeBackend();
        final again = AppState(db, KaraokeEngine(b, scanEdges: scan));
        await again.init(rescanLibrary: false);
        expect(again.engine.levelLoudness, isTrue);
        expect(again.engine.vocalCut, isTrue);
      });
      await tester.tap(find.byKey(const Key('vocal-cut')));
      await tester.tap(find.byKey(const Key('level-loudness')));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump();
      expect(backend.audioFilter, '');
    });

    test('the filter graph is wrapped for mpv with its exact length', () {
      final f = audioFilterChain(levelLoudness: true, vocalCut: true);
      final m = RegExp(r'^lavfi=graph=%(\d+)%(.*)$').firstMatch(f)!;
      expect(m.group(2)!.length, int.parse(m.group(1)!));
      expect(audioFilterChain(), '');
    });
  });

  test('sync: playlists and keys go from the PC to a tablet with the library somewhere else', () async {
    await state.init(rescanLibrary: false);
    await state.addRootFolder(lib.path);
    final all = {for (final g in state.results) g.primary.fileName: g.primary};
    final waterloo = all['Abba - Waterloo.mp3']!, prayer = all['Bon Jovi - Livin On A Prayer.mp3']!;
    await state.createPlaylist('Friday', tracks: [prayer, waterloo]);
    state.keyShifts[waterloo.path] = -2;
    final json = await state.exportSync();

    // The tablet: the same songs, in another folder, with "Pop" as its library.
    final tab = Directory.systemTemp.createTempSync('eztiger_tablet');
    addTearDown(() => tab.deleteSync(recursive: true));
    for (final f in [
      'SD/Pop/Abba - Waterloo.mp3',
      'SD/Pop/Abba - Waterloo.cdg',
      'SD/Rock/Bon Jovi - Livin On A Prayer.mp3',
    ]) {
      File('${tab.path}/$f')
        ..parent.createSync(recursive: true)
        ..writeAsBytesSync(List.filled(f.endsWith('.cdg') ? 24 * 300 : 10, 0));
    }
    final tdb = await EztigerDatabase.open(databaseFactoryFfiNoIsolate, inMemoryDatabasePath);
    addTearDown(tdb.close);
    final tablet = AppState(tdb, KaraokeEngine(FakeBackend(), scanEdges: scan));
    await tablet.init(rescanLibrary: false);
    await tablet.addRootFolder('${tab.path}/SD/Pop');
    await tablet.addRootFolder('${tab.path}/SD/Rock');
    final r = await tablet.importSync(json);
    expect(r.playlists, 1);
    expect(r.songs, 2);
    expect(r.keys, 1);
    expect(r.missing, isEmpty);
    final pl = tablet.playlists.single;
    expect(pl.name, 'Friday');
    final songs = await tdb.playlists.tracks(pl.id);
    expect(songs.map((t) => t.fileName), ['Bon Jovi - Livin On A Prayer.mp3', 'Abba - Waterloo.mp3']);
    expect(tablet.keyShifts[songs[1].path], -2);
    // Saved, so the tablet keeps the key after a restart.
    expect(await tdb.getMeta('key_shifts'), contains('-2'));

    // Loading it again replaces the playlist instead of doubling it.
    await tablet.importSync(json);
    expect(tablet.playlists.length, 1);
    expect(tablet.playlists.single.trackCount, 2);
    await expectLater(tablet.importSync('{"x": 1}'), throwsFormatException);
  });

  testWidgets('EZTiger Basic has no Pro sound controls, skins or second deck', (tester) async {
    isPro = false;
    await tester.runAsync(() => db.setMeta('key_shifts', '{"x": 2}'));
    await pumpApp(tester);
    expect(find.byType(ProSoundRow), findsNothing);
    expect(find.textContaining('QUEUE · '), findsOneWidget, reason: 'Basic keeps the word queue');
    expect(find.textContaining("Tonight's playlist"), findsNothing);
    await tester.runAsync(() => state.playNow(state.results.first.primary, autostart: false));
    await tester.pump();
    expect(state.engine.keyShift, 0);
    expect(backend.audioFilter, '');
    await tester.tap(find.byKey(const Key('main-menu')));
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.byKey(const Key('menu-skin')), findsNothing);
    expect(find.byKey(const Key('menu-two-decks')), findsNothing);
    expect(editionName, 'EZTiger Basic');
  });

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
    expect(find.textContaining("TONIGHT'S PLAYLIST · 1 TO SING"), findsOneWidget);
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
    // The sung song stays in the queue, ticked, with its time and singer.
    expect(state.queue.length, 2);
    expect(state.queue.first.played, isTrue);
    expect(state.playedCount, 1);
    expect(find.textContaining('1 TO SING · 1 PLAYED'), findsOneWidget);
    expect(find.byIcon(Icons.check), findsOneWidget);
    expect(state.engine.current?.id, tracks[1].id);
    await tester.tap(find.byKey(const Key('clear-played')));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pump();
    expect(state.queue.length, 1);
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
    await tester.tap(find.byKey(const Key('main-menu')));
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.tap(find.text('Light'));
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(state.dark, isFalse);
  });

  testWidgets('a skin picked in the menu changes the colours and is remembered', (tester) async {
    await pumpApp(tester);
    Color wordmark() => tester.widget<Text>(find.text('EZTIGER').first).style!.color!;
    expect(wordmark(), EzSkin.classic.brass);
    await tester.tap(find.byKey(const Key('main-menu')));
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    // The classic skin has a light screen too; the others don't.
    expect(find.text('Light'), findsOneWidget);
    await tester.tap(find.byKey(const Key('menu-skin')));
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    for (final skin in EzSkin.all) {
      expect(find.byKey(Key('skin-${skin.id}')), findsOneWidget);
    }
    await tester.tap(find.byKey(const Key('skin-reactor')));
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(state.skin, 'reactor');
    expect(EzSkin.current, EzSkin.reactor);
    expect(wordmark(), EzSkin.reactor.brass);
    await tester.tap(find.byKey(const Key('main-menu')));
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.text('Light'), findsNothing);
    expect(find.text('Reactor'), findsOneWidget); // the skin's name by "Skin"
    // Saved with the other settings, for the next start.
    final saved = await tester.runAsync(() => db.getMeta('settings'));
    expect(saved, contains('"skin":"reactor"'));
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

  testWidgets('Pro: the highlighted folder drags whole into Tonight\'s playlist', (tester) async {
    await pumpApp(tester);
    final root = state.roots.first;
    await tester.runAsync(() => state.selectFolder(root.id));
    await tester.pump();
    final songs = state.results.length;
    expect(songs, greaterThan(1));

    final g = await tester.startGesture(tester.getCenter(find.byKey(Key('folder-drag-${root.id}'))));
    await tester.pump();
    await g.moveBy(const Offset(400, -100));
    await tester.pump();
    await g.moveTo(tester.getCenter(find.byType(QueuePanel)));
    await tester.pump();
    await tester.runAsync(() async {
      await g.up();
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pump();
    expect(state.queue.length, songs);
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('Pro: double-click can add to Tonight\'s playlist instead of the player', (tester) async {
    await pumpApp(tester);
    await tester.tap(find.byKey(const Key('main-menu')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.text('Tonight'));
    await tester.pump(const Duration(milliseconds: 500));
    expect(state.doubleClickToQueue, isTrue);

    final row = find.byType(ResultRow).first;
    await tester.tap(row);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(row);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pump();
    expect(state.queue.length, 1);
    expect(await tester.runAsync(() => db.getMeta('settings')), contains('"doubleClickToQueue":true'));
  });

  testWidgets('Pro: searching folds away everything under the player, and ✕ brings it back', (tester) async {
    await pumpApp(tester);
    expect(find.byType(CrossfadeRow), findsOneWidget);
    expect(find.byType(LibraryTabs), findsOneWidget);
    await tester.tap(find.byKey(const Key('search')));
    await tester.pump();
    expect(find.byType(CrossfadeRow), findsNothing);
    expect(find.byType(ProSoundRow), findsNothing);
    expect(find.byType(LibraryTabs), findsNothing);
    await tester.enterText(find.byKey(const Key('search')), 'prayer');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pump();
    // Still folded after leaving the box while there is a search in it.
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();
    expect(find.byType(LibraryTabs), findsNothing);
    await tester.tap(find.descendant(of: find.byKey(const Key('search')), matching: find.byIcon(Icons.close)));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pump();
    expect(find.byType(CrossfadeRow), findsOneWidget);
    expect(find.byType(LibraryTabs), findsOneWidget);
  });

  testWidgets('Pro: when nothing is playing the output shows the logo, not the lyrics', (tester) async {
    await pumpApp(tester);
    final waterloo = state.results.map((g) => g.primary).firstWhere((t) => t.title == 'Waterloo');
    await tester.runAsync(() async {
      await state.playNow(waterloo, autostart: false);
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pump();
    expect(state.engine.hasCdg, isTrue);
    final out = find.byType(KaraokeScreen);
    expect(find.descendant(of: out, matching: find.byType(EzLogo)), findsOneWidget);
    expect(
      find.descendant(of: out, matching: find.byType(AspectRatio)),
      findsNothing,
      reason: 'no lyric screen',
    );

    await tester.runAsync(() async {
      await state.engine.play();
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pump();
    expect(find.descendant(of: out, matching: find.byType(EzLogo)), findsNothing);

    await tester.runAsync(() => state.engine.playPause());
    await tester.pump();
    expect(find.descendant(of: out, matching: find.byType(EzLogo)), findsOneWidget);
  });

  testWidgets('Pro keys: M, Q, S, /, U/D, K/L/0 and B, but not while typing', (tester) async {
    await pumpApp(tester);
    Future<void> key(LogicalKeyboardKey k, {bool shift = false}) async {
      if (shift) await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(k);
      if (shift) await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump(const Duration(milliseconds: 300));
    }

    await key(LogicalKeyboardKey.keyM);
    expect(state.engine.muted, isTrue);
    await key(LogicalKeyboardKey.keyM);
    expect(state.engine.muted, isFalse);

    // Q adds the selected song; Shift+Q puts the next one ahead of it.
    final rows = find.byType(ResultRow);
    await tester.tap(rows.at(0));
    await tester.pump(const Duration(milliseconds: 400));
    await key(LogicalKeyboardKey.keyQ);
    expect(state.queue.length, 1);
    final first = state.queue.first.track.id;
    await tester.tap(rows.at(1));
    await tester.pump(const Duration(milliseconds: 400));
    await key(LogicalKeyboardKey.keyQ, shift: true);
    expect(state.queue.length, 2);

    await key(LogicalKeyboardKey.keyS);
    expect(state.stageView, isTrue);
    await key(LogicalKeyboardKey.keyS);
    expect(state.stageView, isFalse);

    // / goes to the search box, where S and M are just letters.
    await key(LogicalKeyboardKey.slash);
    expect(state.searchFocus.hasFocus, isTrue);
    await key(LogicalKeyboardKey.keyS);
    await key(LogicalKeyboardKey.keyM);
    expect(state.stageView, isFalse);
    expect(state.engine.muted, isFalse);
    expect(first, isNonZero);
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();

    // U / D volume, K / L key on the song in the player, 0 back, B locks.
    await tester.runAsync(() async {
      await state.playNow(state.queue.first.track, autostart: false);
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pump();
    final vol = state.engine.volume;
    await key(LogicalKeyboardKey.keyU);
    expect(state.engine.volume, vol + 5 > 100 ? 100 : vol + 5);
    await key(LogicalKeyboardKey.keyD);
    await key(LogicalKeyboardKey.keyD);
    expect(state.engine.volume, (vol + 5 > 100 ? 100 : vol + 5) - 10);
    await key(LogicalKeyboardKey.keyK);
    await key(LogicalKeyboardKey.keyK);
    expect(state.engine.keyShift, 2);
    await key(LogicalKeyboardKey.keyL);
    expect(state.engine.keyShift, 1);
    await key(LogicalKeyboardKey.digit0);
    expect(state.engine.keyShift, 0);
    await key(LogicalKeyboardKey.keyB);
    expect(state.locked, isTrue);
    await key(LogicalKeyboardKey.keyU);
    expect(state.engine.volume, (vol + 5 > 100 ? 100 : vol + 5) - 10, reason: 'keys wait while locked');
    state.setLocked(false);
    await tester.pump(const Duration(seconds: 3));
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

  testWidgets('the queue is saved as a new playlist, then added to it again', (tester) async {
    await pumpApp(tester);
    Future<void> settle() async {
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    final tracks = state.results.map((g) => g.primary).toList();
    await tester.runAsync(() => state.enqueueAll(tracks.sublist(0, 2)));
    await tester.pump();

    await tester.tap(find.byKey(const Key('save-queue')));
    await settle();
    await tester.tap(find.text("★ New playlist from Tonight's playlist (2 songs)…"));
    await settle();
    await tester.enterText(find.descendant(of: find.byType(AlertDialog), matching: find.byType(TextField)), 'Saturday');
    await tester.tap(find.text('OK'));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await settle();
    final saturday = state.playlists.singleWhere((p) => p.name == 'Saturday');
    final saved = await tester.runAsync(() => db.playlists.tracks(saturday.id));
    expect(saved!.map((t) => t.id), tracks.sublist(0, 2).map((t) => t.id));

    // One more song in the queue, then "Add the queue to Saturday".
    await tester.runAsync(() => state.enqueue(tracks[2]));
    await tester.pump();
    await tester.tap(find.byKey(const Key('save-queue')));
    await settle();
    await tester.tap(find.text("★ Add Tonight's playlist to Saturday"));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await settle();
    expect(state.playlists.singleWhere((p) => p.name == 'Saturday').trackCount, 5);
  });

  testWidgets('Pro: a playlist changed in the queue is saved back over itself', (tester) async {
    await pumpApp(tester);
    Future<void> settle() async {
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    final tracks = state.results.map((g) => g.primary).toList();
    final id = (await tester.runAsync(() => state.createPlaylist('Friday', tracks: tracks.sublist(0, 2))))!;
    await tester.runAsync(() => state.loadPlaylistIntoQueue(id));
    await settle();
    expect(state.queuePlaylist?.name, 'Friday');
    expect(
      find.textContaining("TONIGHT'S PLAYLIST · "),
      findsOneWidget,
      reason: 'Pro calls the queue Tonight\'s playlist',
    );
    // Live changes: drop the first song, add the third.
    await tester.runAsync(() async {
      await state.removeFromQueue(state.queue.first);
      await state.enqueue(tracks[2]);
    });
    await settle();
    await tester.tap(find.byKey(const Key('save-changes-button')));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await settle();
    final saved = await tester.runAsync(() => db.playlists.tracks(id));
    expect(saved!.map((t) => t.id), [tracks[1].id, tracks[2].id]);
    expect(state.playlists.singleWhere((p) => p.name == 'Friday').trackCount, 2);
  });

  testWidgets('Pro 2 decks: the decks sit side by side, with the crossfade slider', (tester) async {
    state = AppState(
      db,
      KaraokeEngine(backend, scanEdges: scan),
      deckB: KaraokeEngine(FakeBackend(), scanEdges: scan),
    );
    await pumpApp(tester);
    await tester.runAsync(() => state.setTwoDecks(true));
    await tester.pump();
    expect(find.byKey(const Key('deck-A')), findsOneWidget);
    expect(find.byKey(const Key('deck-B')), findsOneWidget);
    final a = tester.getTopLeft(find.byKey(const Key('deck-A')));
    final b = tester.getTopLeft(find.byKey(const Key('deck-B')));
    expect(a.dy, b.dy, reason: 'side by side');
    expect(b.dx, greaterThan(a.dx));
    expect(tester.getSize(find.byKey(const Key('deck-A'))).height, lessThan(110), reason: 'not deep');

    expect(find.byKey(const Key('xfade-style')), findsOneWidget);
    final slider = tester.widget<Slider>(find.byKey(const Key('xfade-time')));
    expect(slider.max, 6);
    slider.onChanged!(0);
    await tester.pump();
    expect(state.fadeOutTime, Duration.zero);
    expect(tester.widget<Text>(find.byKey(const Key('xfade-label'))).data, 'Cut');
    slider.onChanged!(5.5);
    await tester.pump();
    expect(state.fadeOutTime, const Duration(milliseconds: 5500));
    expect(tester.widget<Text>(find.byKey(const Key('xfade-label'))).data, '5.5s');
    await tester.tap(find.text('In turn'));
    await tester.pump();
    expect(state.fadeOverlap, isFalse);
    await tester.tap(find.text('Linear'));
    await tester.pump();
    expect(state.smoothFades, isFalse);
    expect(state.decks.every((d) => !d.smoothFades), isTrue);
  });

  testWidgets('Pro 2 decks, Stage view: both decks across the top, the transport on them', (tester) async {
    state = AppState(
      db,
      KaraokeEngine(backend, scanEdges: scan),
      deckB: KaraokeEngine(FakeBackend(), scanEdges: scan),
    );
    await pumpApp(tester);
    await tester.runAsync(() async {
      for (final g in state.results) {
        await state.enqueue(g.primary);
      }
    });
    await tester.pump();
    await tester.runAsync(() => state.setTwoDecks(true));
    await tester.pump();
    state.setStageView(true);
    await tester.pump();
    final a = tester.getRect(find.byKey(const Key('deck-A')));
    final b = tester.getRect(find.byKey(const Key('deck-B')));
    expect(a.top, b.top);
    expect(a.top, lessThan(20), reason: 'at the top of the screen');
    expect(b.right - a.left, greaterThan(1300), reason: 'across the whole width');
    expect(a.height, lessThan(170), reason: 'about half the old player block');
    expect(find.byKey(const Key('stage-play')), findsNothing, reason: 'the transport is on the deck');
    expect(find.byKey(const Key('stage-lyrics')), findsOneWidget);
    expect(tester.getRect(find.byKey(const Key('stage-lyrics'))).top, greaterThan(a.bottom));
    expect(find.byKey(const Key('deck-A-play')), findsOneWidget);
    expect(find.byKey(const Key('deck-B-mix')), findsOneWidget);

    // The key of the song waiting on deck B is set before it plays, and kept.
    final waiting = state.standby!;
    await tester.runAsync(() async {
      await tester.tap(find.byKey(const Key('deck-B-key-up')));
      await tester.tap(find.byKey(const Key('deck-B-key-up')));
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pump();
    expect(waiting.keyShift, 2);
    expect(state.engine.keyShift, 0, reason: 'the song on air keeps its key');
    expect(tester.widget<Text>(find.byKey(const Key('deck-B-key'))).data, 'KEY +2');
    expect(state.keyShifts[waiting.current!.path], 2, reason: 'remembered for the song');
  });

  testWidgets('Pro trial: days left by the PRO badge, and a licence key in the menu', (tester) async {
    addTearDown(() => licence = null);
    final shop = FakeShop();
    final l = licence = Licence(db, server: shop);
    await tester.runAsync(l.load);
    await pumpApp(tester);
    expect(find.text('TRIAL 14d'), findsOneWidget);
    await tester.tap(find.byKey(const Key('licence-chip')));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.byKey(const Key('licence-dialog')), findsOneWidget);
    expect(find.textContaining('14 more days'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('licence-key')), 'GOOD-KEY');
    await tester.runAsync(() async {
      await tester.tap(find.byKey(const Key('licence-activate')));
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.byKey(const Key('licence-dialog')), findsNothing);
    expect(l.licensed, isTrue);
    expect(find.byKey(const Key('licence-chip')), findsNothing, reason: 'licensed: no trial chip');
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
    expect(state.queue.where((e) => !e.played).length, 2);
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
    final fresh = AppState(db, KaraokeEngine(FakeBackend(), scanEdges: scan));
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
    final fresh = AppState(db, KaraokeEngine(FakeBackend(), scanEdges: scan));
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

  void silentEnds() {
    for (final f in ['Abba - Waterloo.mp3', 'Queen - Bohemian Rhapsody.mp4', 'Bon Jovi - Livin On A Prayer.mp3']) {
      edges[f] = const AudioEdges(Duration(seconds: 10), Duration(seconds: 170), Duration(minutes: 3));
    }
  }

  testWidgets('autocue starts a song at its first note, past the silence', (tester) async {
    await pumpApp(tester);
    silentEnds();
    final t = state.results.first.primary;
    await tester.runAsync(() => state.enqueue(t));
    expect(state.engine.current?.id, t.id);
    expect(backend.opensAt.last, const Duration(milliseconds: 9850));
    expect(state.engine.cueStart, const Duration(milliseconds: 9850));
    await tester.runAsync(state.previous); // ⏮ goes back to the first note
    expect(backend.seeks.last, const Duration(milliseconds: 9850));

    // With Autocue off, songs play from the very start.
    state.toggleAutocue();
    await tester.runAsync(() => state.playNow(state.results.last.primary, autostart: false));
    expect(backend.opensAt.last, Duration.zero);
  });

  testWidgets('crossfade fades before the silence at the end, into the next first note', (tester) async {
    await pumpApp(tester);
    silentEnds();
    final tracks = state.results.map((g) => g.primary).toList();
    state.toggleAutocue(); // off: the crossfade still skips the next song's silence
    state.toggleCrossfade();
    await tester.runAsync(() async {
      await state.enqueue(tracks[0]);
      await state.enqueue(tracks[1]);
      await state.playEntry(state.queue.first);
      backend.at(const Duration(seconds: 167)); // 3 s before the music ends, 13 s before the file does
      await Future<void>.delayed(const Duration(milliseconds: 600));
      expect(backend.volume, lessThan(80)); // fading
      await Future<void>.delayed(const Duration(milliseconds: 5000));
    });
    expect(state.engine.current?.id, tracks[1].id);
    expect(backend.opensAt.last, const Duration(milliseconds: 9850));
  });

  testWidgets('Basic: the fade-out length can be 4, 2 or 0.2 seconds, down to a third', (tester) async {
    isPro = false;
    await pumpApp(tester);
    silentEnds();
    final tracks = state.results.map((g) => g.primary).toList();
    state.toggleCrossfade();
    await tester.tap(find.byKey(const Key('main-menu')));
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.tap(find.descendant(of: find.byKey(const Key('fade-length')), matching: find.text('0.2s')));
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(state.fadeOutTime, const Duration(milliseconds: 200));
    await tester.runAsync(() async {
      await state.enqueue(tracks[0]);
      await state.enqueue(tracks[1]);
      await state.playEntry(state.queue.first);
      backend.at(const Duration(seconds: 169)); // 1 s left: too early for a 0.2 s fade
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(backend.volume, 80);
      backend.at(const Duration(milliseconds: 169850));
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    expect(state.engine.current?.id, tracks[1].id);
    expect(backend.volume, closeTo(80 / 3, 1)); // the next song starts at a third, then fades up
  });

  testWidgets('load playlist puts a saved playlist into the queue', (tester) async {
    await pumpApp(tester);
    Future<void> settle() async {
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    final tracks = state.results.map((g) => g.primary).toList();
    // With no playlists yet, the menu says how to make one.
    await tester.tap(find.byKey(const Key('load-playlist')));
    await settle();
    expect(find.textContaining('No playlists yet'), findsOneWidget);
    await tester.tapAt(const Offset(5, 5));
    await settle();

    await tester.runAsync(() => state.createPlaylist('Friday', tracks: tracks.sublist(0, 2)));
    await tester.pump();
    expect(state.queue, isEmpty);
    await tester.tap(find.byKey(const Key('load-playlist')));
    await settle();
    await tester.tap(find.text('★ Friday  (2 songs)'));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await settle();
    expect(state.queue.map((e) => e.track.id), tracks.sublist(0, 2).map((t) => t.id));
  });

  testWidgets('double-clicking the karaoke output opens full screen, and again closes it', (tester) async {
    await pumpApp(tester);
    expect(find.byType(OutputPanel), findsOneWidget);
    await tester.tap(find.byKey(const Key('output-screen')));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(find.byKey(const Key('output-screen')));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(OutputPanel), findsNothing); // full screen lyrics only
    expect(find.byType(KaraokeScreen), findsOneWidget);

    await tester.tap(find.byType(KaraokeScreen));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(find.byType(KaraokeScreen));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(OutputPanel), findsOneWidget);
  });

  testWidgets('a please-wait message shows while the library loads', (tester) async {
    await tester.pumpWidget(const LoadingApp());
    expect(find.text('Loading your song library… please wait'), findsOneWidget);

    await pumpApp(tester);
    expect(find.byKey(const Key('loading-banner')), findsNothing);
    final scan = tester.runAsync(state.rescan);
    await tester.pump();
    expect(find.byKey(const Key('loading-banner')), findsOneWidget);
    await scan;
    await tester.pump();
    expect(find.byKey(const Key('loading-banner')), findsNothing);
  });

  testWidgets('Pro screen lock: taps are ignored until the lock is held, and it can be switched off', (tester) async {
    await pumpApp(tester);
    final tracks = state.results.map((g) => g.primary).toList();
    await tester.runAsync(() => state.enqueue(tracks[0]));
    await tester.pump();
    await tester.tap(find.byKey(const Key('stage-view')));
    await tester.pump();

    await tester.tap(find.byKey(const Key('lock-screen')));
    await tester.pump();
    expect(state.locked, isTrue);
    expect(find.text('LOCKED'), findsOneWidget);

    // A tap on Play or Library does nothing, and says how to unlock.
    await tester.tap(find.byKey(const Key('stage-play')), warnIfMissed: false);
    await tester.tap(find.byKey(const Key('stage-exit')), warnIfMissed: false);
    await tester.pump();
    expect(state.engine.playing, isFalse);
    expect(state.stageView, isTrue);
    expect(find.text('LOCKED · press and hold the lock to unlock'), findsOneWidget);

    // A quick tap on the lock doesn't unlock; holding it does.
    await tester.tap(find.byKey(const Key('lock-unlock')));
    await tester.pump(const Duration(milliseconds: 900));
    expect(state.locked, isTrue);
    final g = await tester.startGesture(tester.getCenter(find.byKey(const Key('lock-unlock'))));
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 300));
    }
    await g.up();
    await tester.pump();
    expect(state.locked, isFalse);
    expect(find.text('LOCKED'), findsNothing);

    // ☰ Menu → Screen lock button takes the 🔒 away, and is remembered.
    await tester.tap(find.byKey(const Key('stage-exit')));
    await tester.pump();
    expect(find.byKey(const Key('lock-screen')), findsOneWidget);
    await tester.tap(find.byKey(const Key('main-menu')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.byKey(const Key('menu-lock-enabled')));
    await tester.pump(const Duration(milliseconds: 500));
    expect(state.lockEnabled, isFalse);
    expect(find.byKey(const Key('lock-screen')), findsNothing);
    expect(await tester.runAsync(() => db.getMeta('settings')), contains('"lockEnabled":false'));
    await tester.pump(const Duration(seconds: 3));
  });

  for (final size in const [Size(1280, 800)]) {
    testWidgets('Pro on a ${size.width.round()}-wide tablet: key, 2 decks, no Level or Vocal cut', (tester) async {
      touchUi = true;
      audioFilters = false;
      addTearDown(() {
        touchUi = false;
        audioFilters = true;
      });
      state = AppState(
        db,
        KaraokeEngine(backend, scanEdges: scan),
        deckB: KaraokeEngine(FakeBackend(), scanEdges: scan),
      );
      await pumpApp(tester);
      tester.view.physicalSize = size;
      await tester.pump();
      expect(find.byKey(const Key('key-up')), findsOneWidget);
      expect(find.byKey(const Key('level-loudness')), findsNothing);
      expect(find.byKey(const Key('vocal-cut')), findsNothing);
      expect(find.byKey(const Key('lock-screen')), findsOneWidget);

      await tester.tap(find.byKey(const Key('main-menu')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byKey(const Key('menu-lock-enabled')), findsOneWidget);
      await tester.tap(find.byKey(const Key('menu-two-decks')));
      for (var i = 0; i < 5; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
        await tester.pump(const Duration(milliseconds: 200));
      }
      expect(state.twoDecks, isTrue);
      expect(find.byKey(const Key('deck-A')), findsOneWidget);
      expect(find.byKey(const Key('deck-B')), findsOneWidget);

      // And across the top of the Stage view.
      await tester.tap(find.byKey(const Key('stage-view')));
      await tester.pump();
      expect(find.byKey(const Key('deck-A')), findsOneWidget);
      expect(find.byKey(const Key('deck-B')), findsOneWidget);
      expect(find.byKey(const Key('lock-screen')), findsOneWidget);
    });
  }

  testWidgets('stage view: big buttons, what is next, and back to the library', (tester) async {
    await pumpApp(tester);
    final tracks = state.results.map((g) => g.primary).toList();
    await tester.runAsync(() async {
      await state.enqueue(tracks[0], singer: 'Dean');
      await state.enqueue(tracks[1], singer: 'Mike');
    });
    await tester.pump();

    await tester.tap(find.byKey(const Key('stage-view')));
    await tester.pump();
    expect(find.byType(StageView), findsOneWidget);
    expect(find.byType(QueuePanel), findsNothing);
    // The cued song is big at the top, and the next singer is up next.
    expect(find.text(tracks[0].title), findsWidgets);
    expect(find.text('UP NEXT · 1'), findsOneWidget);
    expect(find.text(tracks[1].title), findsOneWidget);
    expect(tester.getSize(find.byKey(const Key('stage-play'))).width, greaterThanOrEqualTo(100));

    // Lyrics on the left, buttons on the right; ⇄ swaps them.
    double lyricsX() => tester.getCenter(find.byKey(const Key('stage-lyrics'))).dx;
    double playX() => tester.getCenter(find.byKey(const Key('stage-play'))).dx;
    expect(lyricsX(), lessThan(playX()));
    await tester.tap(find.byKey(const Key('stage-swap')));
    await tester.pump();
    expect(state.stageLyricsRight, isTrue);
    expect(lyricsX(), greaterThan(playX()));

    await tester.runAsync(() async {
      await tester.tap(find.byKey(const Key('stage-play')));
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pump();
    expect(state.engine.playing, isTrue);

    // The time and the seek bar follow the song as it plays.
    Slider stageSeek() =>
        tester.widget<Slider>(find.descendant(of: find.byType(StageView), matching: find.byType(Slider)).first);
    await tester.runAsync(() async {
      backend.at(const Duration(minutes: 1));
      await Future<void>.delayed(const Duration(milliseconds: 20));
    });
    await tester.pump();
    expect(find.text('-${fmt(const Duration(minutes: 2))}'), findsOneWidget);
    expect(stageSeek().value, const Duration(minutes: 1).inMilliseconds);
    await tester.runAsync(() async {
      backend.at(const Duration(minutes: 2));
      await Future<void>.delayed(const Duration(milliseconds: 20));
    });
    await tester.pump();
    expect(find.text('-${fmt(const Duration(minutes: 1))}'), findsOneWidget);
    expect(stageSeek().value, const Duration(minutes: 2).inMilliseconds);

    await tester.runAsync(() async {
      await tester.tap(find.byKey(const Key('stage-next')));
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pump();
    expect(state.engine.current?.id, tracks[1].id);
    expect(find.text('UP NEXT · NOTHING QUEUED'), findsOneWidget);

    // Double-tap the lyrics for full screen, and again to come back.
    await tester.tap(find.byKey(const Key('stage-lyrics')));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(find.byKey(const Key('stage-lyrics')));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(StageView), findsNothing);
    await tester.tap(find.byType(KaraokeScreen));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(find.byType(KaraokeScreen));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(StageView), findsOneWidget);

    // It's remembered, so the app opens in stage view at the next gig.
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 50));
      final again = AppState(db, KaraokeEngine(FakeBackend(), scanEdges: scan));
      await again.init(rescanLibrary: false);
      expect(again.stageView, isTrue);
      expect(again.stageLyricsRight, isTrue);
    });

    await tester.tap(find.byKey(const Key('stage-exit')));
    await tester.pump();
    expect(find.byType(StageView), findsNothing);
    expect(find.byType(QueuePanel), findsOneWidget);
  });

  testWidgets('the menu makes the song lists larger, but not the player', (tester) async {
    await pumpApp(tester);
    await tester.runAsync(() => state.enqueue(state.results.first.primary));
    await tester.pump();
    double sizeOf(Finder f) => tester.getSize(f).height;
    final song = state.results.first.primary.title;
    Finder inResults() => find.descendant(of: find.byType(ResultsTable), matching: find.text(song));
    Finder inQueue() => find.descendant(of: find.byType(QueuePanel), matching: find.text(song));
    final before = sizeOf(inResults());
    final queueBefore = sizeOf(inQueue());
    final logoBefore = sizeOf(find.text('EZTIGER').first);

    await tester.tap(find.byKey(const Key('main-menu')));
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    // The menu has grown: scroll down to the text sizes.
    await tester.ensureVisible(find.byKey(const Key('text-size-Extra large')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('text-size-Extra large')));
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(state.textScale, 1.5);
    expect(sizeOf(inResults()), greaterThan(before * 1.3));
    expect(sizeOf(inQueue()), greaterThan(queueBefore * 1.3));
    expect(sizeOf(find.text('EZTIGER').first), logoBefore);
    expect(tester.takeException(), isNull); // nothing overflows

    await tester.runAsync(() async {
      // Saved for next time.
      await Future<void>.delayed(const Duration(milliseconds: 50));
      final again = AppState(db, KaraokeEngine(FakeBackend(), scanEdges: scan));
      await again.init(rescanLibrary: false);
      expect(again.textScale, 1.5);
    });
  });

  testWidgets('the Read me sheet opens from the top', (tester) async {
    await pumpApp(tester);
    await tester.tap(find.byKey(const Key('main-menu')));
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.tap(find.byKey(const Key('read-me')));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('EZTiger Pro · Read me'), findsOneWidget);
    expect(find.textContaining('Autocue loads the next song'), findsOneWidget);
    expect(find.textContaining('Claude created'), findsNothing);
    // The last line is reachable by scrolling.
    await tester.dragUntilVisible(
      find.textContaining('remembers your settings'),
      find.byType(SingleChildScrollView).last,
      const Offset(0, -200),
    );
    expect(find.textContaining('remembers your settings'), findsOneWidget);
    await tester.tap(find.text('Close'));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('EZTiger Pro · Read me'), findsNothing);
  });

  testWidgets('tablet: press and hold drags a song to the queue, or opens the menu', (tester) async {
    touchUi = true;
    addTearDown(() => touchUi = false);
    await pumpApp(tester);
    final rows = find.byType(ResultRow);

    // Hold and let go without moving: the menu.
    var g = await tester.startGesture(tester.getCenter(rows.at(0)), kind: PointerDeviceKind.touch);
    await tester.pump(const Duration(milliseconds: 700));
    await g.up();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text("➕ Add to Tonight's playlist"), findsOneWidget);
    await tester.tap(find.text("➕ Add to Tonight's playlist"));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
    await tester.pump(const Duration(milliseconds: 500));
    expect(state.queue.length, 1);

    // A quick swipe doesn't pick a song up.
    await tester.drag(rows.at(1), const Offset(0, -40), kind: PointerDeviceKind.touch);
    await tester.pump(const Duration(milliseconds: 500));
    expect(state.queue.length, 1);

    // Hold, then drag onto the queue.
    g = await tester.startGesture(tester.getCenter(rows.at(1)), kind: PointerDeviceKind.touch);
    await tester.pump(const Duration(milliseconds: 700));
    await g.moveBy(const Offset(200, -100));
    await tester.pump();
    await g.moveTo(tester.getCenter(find.byType(QueuePanel)));
    await tester.pump();
    await tester.runAsync(() async {
      await g.up();
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pump(const Duration(milliseconds: 500));
    expect(state.queue.length, 2);
    expect(find.text("➕ Add to Tonight's playlist"), findsNothing); // no menu after a real drag
  });

  testWidgets('tablet: holding a queued song still opens its menu', (tester) async {
    touchUi = true;
    addTearDown(() => touchUi = false);
    await pumpApp(tester);
    final tracks = state.results.map((g) => g.primary).toList();
    await tester.runAsync(() async {
      await state.enqueue(tracks[0]);
      await state.enqueue(tracks[1]);
    });
    await tester.pump();
    final row = find.descendant(of: find.byType(QueuePanel), matching: find.text(tracks[1].title));
    final g = await tester.startGesture(tester.getCenter(row), kind: PointerDeviceKind.touch);
    await tester.pump(const Duration(milliseconds: 700));
    await g.up();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('🎤 Set singer…'), findsOneWidget);
    // Letting go on itself didn't move it.
    expect(state.queue.map((e) => e.track.id), [tracks[0].id, tracks[1].id]);
  });

  testWidgets('Autocue and Crossfade are in the menu, and Single/Autoplay sits by the volume', (tester) async {
    await pumpApp(tester);
    final autocue = state.autocue, crossfade = state.crossfade;
    await tester.tap(find.byKey(const Key('main-menu')));
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.tap(find.byKey(const Key('menu-autocue')));
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(state.autocue, !autocue);
    await tester.tap(find.byKey(const Key('main-menu')));
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.tap(find.byKey(const Key('menu-crossfade')));
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(state.crossfade, !crossfade);

    await tester.tap(find.descendant(of: find.byKey(const Key('play-mode')), matching: find.text('Autoplay')));
    await tester.pump();
    expect(state.mode, PlayMode.autoplay);
    // Same row as the volume bar.
    final mode = tester.getCenter(find.byKey(const Key('play-mode')));
    final slider = tester.getCenter(find.byIcon(state.engine.muted ? Icons.volume_off : Icons.volume_up).first);
    expect((mode.dy - slider.dy).abs(), lessThan(12));
  });

  testWidgets('the Library / Playlists box folds away and comes back', (tester) async {
    await pumpApp(tester);
    expect(find.byType(FolderTree), findsOneWidget);
    final before = tester.getSize(find.byType(ResultsTable)).height;
    await tester.tap(find.byKey(const Key('library-fold')));
    await tester.pump();
    expect(find.byType(FolderTree), findsNothing);
    expect(state.libraryCollapsed, isTrue);
    expect(tester.getSize(find.byType(ResultsTable)).height, greaterThan(before + 40));
    await tester.tap(find.text('★ Playlists'));
    await tester.pump();
    expect(find.byType(PlaylistsPanel), findsOneWidget);
    expect(state.libraryCollapsed, isFalse);
  });

  testWidgets('stage view: move and remove queued songs, and Single/Autoplay', (tester) async {
    await pumpApp(tester);
    final tracks = state.results.map((g) => g.primary).toList();
    await tester.runAsync(() async {
      for (final t in tracks) {
        await state.enqueue(t);
      }
      state.setStageView(true);
    });
    await tester.pump();
    // The first song is cued, so two wait in Up Next.
    List<int> waiting() => [
      for (final q in state.queue)
        if (!q.played && q.id != state.nowPlayingQueueId) q.track.id,
    ];
    expect(waiting(), [tracks[1].id, tracks[2].id]);
    final second = state.queue[1], third = state.queue[2];
    await tester.runAsync(() async {
      await tester.tap(find.byKey(ValueKey('stage-down-${second.id}')));
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pump();
    expect(waiting(), [tracks[2].id, tracks[1].id]);
    await tester.runAsync(() async {
      await tester.tap(find.byKey(ValueKey('stage-up-${second.id}')));
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pump();
    expect(waiting(), [tracks[1].id, tracks[2].id]);
    await tester.runAsync(() async {
      await tester.tap(find.byKey(ValueKey('stage-remove-${third.id}')));
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pump();
    expect(waiting(), [tracks[1].id]);
    expect(find.byKey(ValueKey('stage-next-${third.id}')), findsNothing);

    expect(state.mode, PlayMode.single);
    await tester.tap(find.byKey(const Key('stage-mode-autoplay')));
    await tester.pump();
    expect(state.mode, PlayMode.autoplay);
    await tester.tap(find.byKey(const Key('stage-mode-single')));
    await tester.pump();
    expect(state.mode, PlayMode.single);
  });

  group('2 decks', () {
    late FakeBackend backendB;
    late AppState two;
    setUp(() {
      backendB = FakeBackend();
      two = AppState(
        db,
        KaraokeEngine(backend, scanEdges: scan),
        deckB: KaraokeEngine(backendB, scanEdges: scan),
      );
    });

    Future<List<Track>> queueAll() async {
      await two.init();
      await two.addRootFolder(lib.path);
      final tracks = two.results.map((g) => g.primary).toList();
      for (final t in tracks) {
        await two.enqueue(t);
      }
      await two.setTwoDecks(true);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      return tracks;
    }

    test('the next song waits on the other deck, and the decks take turns', () async {
      final tracks = await queueAll();
      expect(two.liveDeck, 0);
      expect(two.engine.current?.id, tracks[0].id);
      expect(two.standby!.current?.id, tracks[1].id, reason: 'the next song is cued on deck B');
      expect(two.standby!.playing, isFalse);

      await two.playPause();
      await two.next();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(two.liveDeck, 1);
      expect(two.engine.current?.id, tracks[1].id);
      expect(two.engine.playing, isTrue);
      expect(backend.calls.last, isNot('play'));
      expect(two.standby!.current?.id, tracks[2].id, reason: 'deck A takes the song after');

      // Moving songs in the queue re-cues the waiting deck.
      await two.clearQueue();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(two.standby!.current, isNull);
    });

    test('autoplay: the end of a song starts the other deck', () async {
      final tracks = await queueAll();
      two.setMode(PlayMode.autoplay);
      await two.playPause();
      backend.finish();
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(two.liveDeck, 1);
      expect(two.engine.current?.id, tracks[1].id);
      expect(two.engine.playing, isTrue);
      expect(two.queue.first.played, isTrue);
    });

    test('crossfade overlaps the two decks', () async {
      final tracks = await queueAll();
      two.toggleCrossfade();
      await two.playPause();
      backend.at(const Duration(minutes: 2, seconds: 58)); // 2 seconds left
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(two.liveDeck, 1, reason: 'the next song has started');
      expect(two.engine.current?.id, tracks[1].id);
      expect(two.engine.playing, isTrue);
      expect(backend.volume, lessThan(100), reason: 'deck A fading out');
      expect(two.decks[0].current?.id, tracks[0].id, reason: 'still playing out on deck A');
      await Future<void>.delayed(const Duration(milliseconds: 2200));
      expect(two.standby!.current?.id, tracks[2].id, reason: 'then deck A takes the song after');
      expect(two.queue.where((e) => !e.played).length, 2);
    });

    test(
      'double-click while a song plays: it waits on the free deck, the old next song moves back to second',
      () async {
        final tracks = await queueAll();
        await two.playPause();
        expect(two.standby!.current?.id, tracks[1].id);
        await two.loadNext([tracks[2]]);
        await Future<void>.delayed(const Duration(milliseconds: 50));
        expect(two.standby!.current?.id, tracks[2].id, reason: 'the picked song is on the free deck');
        final waiting = two.queue.where((e) => !e.played).map((e) => e.track.id).toList();
        expect(waiting.indexOf(tracks[2].id), lessThan(waiting.lastIndexOf(tracks[1].id)));
        expect(two.engine.current?.id, tracks[0].id, reason: 'the live song keeps playing');
        expect(two.engine.playing, isTrue);
      },
    );

    test('mix now brings in the waiting deck at once', () async {
      final tracks = await queueAll();
      two.setFadeOut(const Duration(milliseconds: 300));
      await two.playPause();
      await two.mixNow();
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(two.liveDeck, 1);
      expect(two.engine.current?.id, tracks[1].id);
      expect(two.engine.playing, isTrue);
    });

    test('turning 2 decks off stops the waiting deck; it is remembered', () async {
      await queueAll();
      expect(two.decks[1].current, isNotNull);
      await two.setTwoDecks(false);
      expect(two.decks[1].current, isNull);
      expect(two.standby, isNull);
      await two.setTwoDecks(true);
      final again = AppState(db, KaraokeEngine(FakeBackend()), deckB: KaraokeEngine(FakeBackend()));
      await again.init(rescanLibrary: false);
      expect(again.twoDecks, isTrue);
      final single = AppState(db, KaraokeEngine(FakeBackend()));
      await single.init(rescanLibrary: false);
      expect(single.twoDecks, isFalse, reason: 'no second deck on the tablet');
    });
  });
}
