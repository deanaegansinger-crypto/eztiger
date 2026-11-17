import 'dart:io';

import 'package:eztiger/app_state.dart';
import 'package:eztiger/edition.dart';
import 'package:eztiger/player.dart';
import 'package:eztiger/ui/app.dart';
import 'package:eztiger_core/eztiger_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'fakes.dart';

void main() {
  sqfliteFfiInit();
  late Directory lib;
  late EztigerDatabase db;
  late FakeBackend backend;
  late AppState state;

  setUp(() async {
    isPro = true;
    lib = makeLibrary();
    // A second version of Waterloo, on another disc: Waterloo shows ×2.
    File(p.join(lib.path, 'Zoom', 'ZM12', 'Abba - Waterloo.mp4'))
      ..parent.createSync(recursive: true)
      ..writeAsBytesSync(List.filled(10, 0));
    db = await EztigerDatabase.open(databaseFactoryFfiNoIsolate, inMemoryDatabasePath);
    backend = FakeBackend();
    state = AppState(db, KaraokeEngine(backend, scanEdges: (_) async => null));
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

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  int rowOf(String title) => state.results.indexWhere((g) => g.primary.title == title);

  testWidgets('a song with other versions: pick it and its discs open under it, one click loads one', (tester) async {
    await pumpApp(tester);
    final waterloo = rowOf('Waterloo');
    expect(state.results[waterloo].versions, hasLength(2));
    expect(find.byKey(const Key('version-0')), findsNothing, reason: 'closed until the song is picked');

    // A song with one version: nothing opens.
    state.selectRow(rowOf('Bohemian Rhapsody'));
    await settle(tester);
    expect(find.byKey(const Key('version-0')), findsNothing);

    state.selectRow(waterloo);
    await settle(tester);
    expect(find.byKey(const Key('version-0')), findsOneWidget);
    expect(find.byKey(const Key('version-1')), findsOneWidget);
    for (final k in ['now', 'next', 'bottom']) {
      expect(find.byKey(Key('version-$k-1')), findsOneWidget);
    }
    expect(tester.takeException(), isNull, reason: 'no overflow');

    final versions = state.results[waterloo].versions;
    final mp4 = versions.indexWhere((t) => t.fileName.endsWith('.mp4'));
    final cdg = 1 - mp4;
    Future<void> click(String key) async {
      await tester.tap(find.byKey(Key(key)));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
      await settle(tester);
    }

    // Now: one click loads the MP4 disc on the player.
    await click('version-now-$mp4');
    expect(backend.calls, contains('open Abba - Waterloo.mp4'));

    // Bottom: the MP4 disc goes to the end of tonight's playlist.
    await tester.runAsync(() async {
      await state.enqueue(state.results[rowOf('Bohemian Rhapsody')].primary);
      await state.enqueue(state.results[rowOf('Livin On A Prayer')].primary);
    });
    await click('version-bottom-$mp4');
    expect(state.queue.last.track.id, versions[mp4].id);

    // Next: the CDG disc goes in ahead of the others waiting.
    await click('version-next-$cdg');
    final at = state.queue.indexWhere((e) => e.track.id == versions[cdg].id);
    expect(at, greaterThanOrEqualTo(0));
    expect(at, lessThan(state.queue.indexWhere((e) => e.track.title == 'Livin On A Prayer')));
    expect(state.queue.last.track.id, versions[mp4].id);

    // ☰ Menu → Versions: one saved choice. Only that button shows.
    state.selectRow(waterloo);
    state.setDiscChoice('bottom');
    await settle(tester);
    expect(find.byKey(const Key('version-bottom-0')), findsOneWidget);
    expect(find.byKey(const Key('version-now-0')), findsNothing);
    expect(find.byKey(const Key('version-next-0')), findsNothing);

    // Off: picking it opens nothing.
    state.setDiscChoice('off');
    await settle(tester);
    expect(find.byKey(const Key('version-0')), findsNothing);
    state.setDiscChoice('all');
    await settle(tester);
    expect(find.byKey(const Key('version-now-0')), findsOneWidget);

    // Two songs picked (a block): nothing opens.
    state.selectRow(rowOf('Bohemian Rhapsody'), ctrl: true);
    await settle(tester);
    expect(find.byKey(const Key('version-0')), findsNothing);
  });

  testWidgets('the Songbook view (the usual one): a tile per collection, a click puts its disc in', (tester) async {
    await pumpApp(tester);
    expect(state.searchStyle, 'songbook');
    expect(find.byKey(const Key('songbook-header')), findsOneWidget);
    expect(find.byKey(const Key('brand-Zoom')), findsOneWidget);
    expect(find.byKey(const Key('brand-Pop')), findsWidgets);
    expect(tester.takeException(), isNull, reason: 'no overflow');
    final versions = state.results[rowOf('Waterloo')].versions;
    final zoom = versions.firstWhere((t) => t.fileName.endsWith('.mp4'));

    // All: the tile asks Now, Next or Bottom.
    await tester.tap(find.byKey(const Key('brand-Zoom')));
    await settle(tester);
    await tester.tap(find.byKey(const Key('brand-bottom')));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await settle(tester);
    expect(state.queue.last.track.id, zoom.id);

    // A saved choice (Now): one click loads it.
    state.setDiscChoice('now');
    await settle(tester);
    await tester.tap(find.byKey(const Key('brand-Zoom')));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await settle(tester);
    expect(find.byKey(const Key('brand-bottom')), findsNothing, reason: 'no menu');
    expect(backend.calls, contains('open Abba - Waterloo.mp4'));

    // The List view, the other choice.
    state.setSearchStyle('list');
    await settle(tester);
    expect(find.byKey(const Key('songbook-header')), findsNothing);
    expect(find.byKey(const Key('brand-Zoom')), findsNothing);
  });

  testWidgets('☰ Menu → Versions (×5): the list of choices, and the pick is used', (tester) async {
    await pumpApp(tester);
    await tester.tap(find.byKey(const Key('main-menu')));
    await settle(tester);
    expect(find.text('Versions (×5): All…'), findsOneWidget);
    await tester.ensureVisible(find.byKey(const Key('menu-disc-choices')));
    await settle(tester);
    await tester.tap(find.byKey(const Key('menu-disc-choices')));
    await settle(tester);
    await tester.tap(find.byKey(const Key('disc-choice-next')));
    await settle(tester);
    expect(state.discChoice, 'next');
  });
}
