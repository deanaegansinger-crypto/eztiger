import 'dart:io';

import 'package:eztiger/app_state.dart';
import 'package:eztiger/edition.dart';
import 'package:eztiger/platform.dart';
import 'package:eztiger/player.dart';
import 'package:eztiger/ui/app.dart';
import 'package:eztiger/ui/common.dart';
import 'package:eztiger/ui/stage_view.dart';
import 'package:eztiger/ui/transfer_dialogs.dart';
import 'package:eztiger_core/eztiger_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'fakes.dart';

/// The Android app, for singers: the Pro singing features without the
/// host's tools, and the Stage view upright on the tablet.
void main() {
  sqfliteFfiInit();
  late Directory lib;
  late EztigerDatabase db;
  late AppState state;
  Future<AudioEdges?> scan(String path) async => null;

  setUp(() async {
    isPro = true;
    singerApp = true;
    touchUi = true;
    lib = makeLibrary();
    db = await EztigerDatabase.open(databaseFactoryFfiNoIsolate, inMemoryDatabasePath);
    state = AppState(
      db,
      KaraokeEngine(FakeBackend(), scanEdges: scan),
      deckB: KaraokeEngine(FakeBackend(), scanEdges: scan),
    );
  });

  tearDown(() async {
    singerApp = false;
    touchUi = false;
    await db.close();
    lib.deleteSync(recursive: true);
  });

  Future<void> pumpApp(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.runAsync(() async {
      await state.init();
      await state.addRootFolder(lib.path);
      for (final g in state.results) {
        await state.enqueue(g.primary);
      }
    });
    await tester.pumpWidget(EztigerApp(state: state));
    await tester.pump();
  }

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  testWidgets('the menu: no songbook, requests or sync file; Import, Receive and Portrait', (tester) async {
    await pumpApp(tester, const Size(1280, 800));
    await tester.tap(find.byKey(const Key('main-menu')));
    await settle(tester);
    expect(find.byKey(const Key('menu-songbook')), findsNothing);
    expect(find.byKey(const Key('menu-requests')), findsNothing);
    expect(find.byKey(const Key('sync-save')), findsNothing);
    expect(find.byKey(const Key('sync-load')), findsNothing);
    expect(find.byKey(const Key('menu-licence')), findsNothing);
    expect(find.byKey(const Key('menu-stage-portrait'), skipOffstage: false), findsOneWidget);
    expect(find.byKey(const Key('import-playlist'), skipOffstage: false), findsOneWidget);
    expect(find.byKey(const Key('receive-playlist'), skipOffstage: false), findsOneWidget);
  });

  testWidgets('portrait Stage view: decks side by side on top, lyrics filling the bottom half', (tester) async {
    final turned = <bool>[];
    state.onOrientation = turned.add;
    // The library is landscape; the tablet turns upright for the Stage view.
    await pumpApp(tester, const Size(1280, 800));
    await tester.runAsync(() => state.setTwoDecks(true));
    state.songbookUrl = 'https://example.com/songbook';
    state.setStagePortrait(true);
    state.setStageView(true);
    tester.view.physicalSize = const Size(800, 1280);
    await tester.pump();
    expect(turned.last, isTrue, reason: 'the tablet turns upright');
    expect(find.byKey(const Key('stage-portrait')), findsOneWidget);

    final a = tester.getRect(find.byKey(const Key('deck-A')));
    final b = tester.getRect(find.byKey(const Key('deck-B')));
    expect(a.top, b.top, reason: 'side by side');
    expect(b.left, greaterThan(a.right));
    final lyrics = tester.getRect(find.byKey(const Key('stage-lyrics')));
    expect(lyrics.top, closeTo(640, 20), reason: 'the bottom half');
    expect(lyrics.bottom, greaterThan(1250));
    expect(find.byKey(const Key('stage-qr')), findsNothing, reason: 'the singer app has no songbook QR');
    expect(find.byKey(const Key('stage-swap')), findsNothing);
    // Up next scrolls between the decks and the lyrics.
    expect(tester.getRect(find.byType(ListView).first).bottom, lessThanOrEqualTo(lyrics.top));
    expect(tester.takeException(), isNull);

    // The rotate button turns it back, and Library goes back to landscape.
    await tester.tap(find.byKey(const Key('stage-rotate')));
    await tester.pump();
    expect(state.stagePortrait, isFalse);
    expect(turned.last, isFalse);
    state.setStagePortrait(true);
    state.setStageView(false);
    expect(turned.last, isFalse, reason: 'the library is landscape');
  });

  testWidgets('portrait with one deck: the player compact, Up next and lyrics below', (tester) async {
    await pumpApp(tester, const Size(1280, 800));
    state.setStagePortrait(true);
    state.setStageView(true);
    tester.view.physicalSize = const Size(800, 1280);
    await tester.pump();
    expect(find.byKey(const Key('stage-play')), findsOneWidget);
    expect(tester.getRect(find.byKey(const Key('stage-lyrics'))).top, closeTo(640, 20));
    expect(tester.takeException(), isNull);
  });

  testWidgets('a warning when Tonight\'s playlist is down to its last 2 songs', (tester) async {
    await pumpApp(tester, const Size(1280, 800));
    // Two more, so the list starts well above the warning.
    await tester.runAsync(() async {
      for (final g in state.results.take(2)) {
        await state.enqueue(g.primary);
      }
    });
    state.setStageView(true);
    await tester.pump();
    final q = [...state.queue];
    expect(q, hasLength(5));
    expect(lowSongsMessage(state), isNull, reason: '4 or 5 to come');
    expect(find.byKey(const Key('stage-low-songs')), findsNothing);

    // Sung in order, with Next: on the third song, 2 are left.
    await tester.runAsync(() => state.playEntry(q[0]));
    await tester.runAsync(state.next);
    expect(lowSongsMessage(state), isNull, reason: '3 to come');
    await tester.runAsync(state.next);
    await tester.pump();
    expect(lowSongsMessage(state), ('Only 2 songs left: load more soon', false));
    expect(find.byKey(const Key('stage-low-songs')), findsOneWidget);

    await tester.runAsync(state.next);
    await tester.pump();
    expect(lowSongsMessage(state)?.$2, isTrue, reason: '1 left: red');

    await tester.runAsync(state.next);
    await tester.pump();
    expect(lowSongsMessage(state), ('Last song! Nothing after this one: load more', true));
    expect(find.text('Last song! Nothing after this one: load more'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('on a phone, Receive from PC fits above the keyboard', (tester) async {
    // A phone on its side, with the keyboard up over half the screen.
    tester.view.physicalSize = const Size(800, 380);
    tester.view.devicePixelRatio = 1;
    tester.view.viewInsets = const FakeViewPadding(bottom: 190);
    addTearDown(tester.view.reset);
    await tester.runAsync(() => state.init(rescanLibrary: false));
    await tester.pumpWidget(
      MaterialApp(
        home: AppScope(
          state: state,
          child: Builder(
            builder: (context) => Scaffold(
              body: TextButton(onPressed: () => receivePlaylist(context), child: const Text('open')),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await settle(tester);
    // The box scrolls down to the code (as Next on the keyboard does).
    await tester.ensureVisible(find.byKey(const Key('receive-code')));
    await settle(tester);
    await tester.tap(find.byKey(const Key('receive-code')));
    await settle(tester);
    expect(tester.takeException(), isNull, reason: 'nothing squashed off the box');
    // The code box and the Receive button are on screen above the keyboard.
    for (final k in ['receive-code', 'receive-go']) {
      await tester.ensureVisible(find.byKey(Key(k)));
      await tester.pump();
      expect(tester.getRect(find.byKey(Key(k))).bottom, lessThanOrEqualTo(380 - 190 + 1), reason: k);
    }
  });

  testWidgets('the Read me: for singers, step by step, without the host\'s tools', (tester) async {
    await pumpApp(tester, const Size(1280, 800));
    await tester.tap(find.byKey(const Key('main-menu')));
    await settle(tester);
    await tester.tap(find.byKey(const Key('read-me')));
    await settle(tester);
    expect(find.text('EZTiger for singers · Read me'), findsOneWidget);
    for (final head in ['1. Add your songs', '2. Bring a playlist from the PC', '7. Sing from the Stage view']) {
      expect(find.text(head.toUpperCase(), skipOffstage: false), findsOneWidget, reason: head);
    }
    for (final host in ['Songbook', 'Song requests', 'Vocal cut', 'sync file']) {
      expect(
        find.descendant(of: find.byType(AlertDialog), matching: find.textContaining(host, skipOffstage: false)),
        findsNothing,
        reason: host,
      );
    }
    expect(tester.takeException(), isNull);
  });

  test('the singer app is one app: the Pro singing features, however it was built', () {
    expect(builtAsPro, isTrue);
  });
}
