import 'dart:io';

import 'package:eztiger/app_state.dart';
import 'package:eztiger/edition.dart';
import 'package:eztiger/platform.dart';
import 'package:eztiger/player.dart';
import 'package:eztiger/ui/app.dart';
import 'package:eztiger/ui/stage_view.dart';
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

    // Sung in order: after the third starts, 2 are left.
    for (final x in q.take(3)) {
      await tester.runAsync(() => state.playEntry(x));
    }
    await tester.pump();
    expect(lowSongsMessage(state), ('Only 2 songs left: load more soon', false));
    expect(find.byKey(const Key('stage-low-songs')), findsOneWidget);

    await tester.runAsync(() => state.playEntry(q[3]));
    await tester.pump();
    expect(lowSongsMessage(state)?.$2, isTrue, reason: '1 left: red');

    await tester.runAsync(() => state.playEntry(q[4]));
    await tester.pump();
    expect(lowSongsMessage(state), ('Last song! Nothing after this one: load more', true));
    expect(find.text('Last song! Nothing after this one: load more'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test('the singer app is one app: the Pro singing features, however it was built', () {
    expect(builtAsPro, isTrue);
  });
}
