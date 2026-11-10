import 'package:eztiger_core/eztiger_core.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  late TestLibrary lib;
  late List<int> ids;
  setUp(() async {
    lib = await TestLibrary.create();
    for (final n in ['Toto - Africa', 'Billy Joel - Piano Man', 'Lady Gaga - Shallow']) {
      lib.touch('a/$n.mp3');
    }
    await lib.scan();
    ids = [
      for (final n in ['Toto - Africa', 'Billy Joel - Piano Man', 'Lady Gaga - Shallow'])
        (await lib.track('a/$n.mp3')).id
    ];
  });
  tearDown(() async => lib.dispose());

  test('queue: add, reorder, remove, and mark sung into history', () async {
    final q1 = await lib.db.queue.add(ids[0], singer: 'Dave M.');
    await lib.db.queue.add(ids[1], singer: 'Steph K.');
    final q3 = await lib.db.queue.add(ids[2], singer: 'Rich T.');
    await lib.db.queue.move(q3, 0);
    expect((await lib.db.queue.all()).map((e) => e.singer), ['Rich T.', 'Dave M.', 'Steph K.']);
    await lib.db.queue.markSung(q3, at: DateTime(2026, 11, 4, 20, 51));
    await lib.db.queue.remove(q1);
    var q = await lib.db.queue.all();
    // A sung song stays in the queue, marked played.
    expect(q.map((e) => '${e.position}:${e.singer}:${e.played}'), ['0:Rich T.:true', '1:Steph K.:false']);
    expect(q.first.playedAt, DateTime(2026, 11, 4, 20, 51));
    expect(q.first.lastSung, DateTime(2026, 11, 4, 20, 51));
    await lib.db.queue.clearPlayed();
    q = await lib.db.queue.all();
    expect(q.map((e) => '${e.position}:${e.singer}'), ['0:Steph K.']);
    final h = await lib.db.history.recent();
    expect(h.single.singer, 'Rich T.');
    expect(h.single.track.title, 'Shallow');
    expect(await lib.db.history.singers(), ['Rich T.']);
  });

  test('playlists: create, add, reorder, remove, save the queue', () async {
    final pl = await lib.db.playlists.create('80s Rock Set');
    await lib.db.playlists.add(pl, ids[0]);
    await lib.db.playlists.add(pl, ids[1]);
    await lib.db.playlists.add(pl, ids[2]);
    await lib.db.playlists.move(pl, 2, 0);
    expect((await lib.db.playlists.tracks(pl)).map((t) => t.title), ['Shallow', 'Africa', 'Piano Man']);
    await lib.db.playlists.removeAt(pl, 1);
    expect((await lib.db.playlists.tracks(pl)).map((t) => t.title), ['Shallow', 'Piano Man']);

    await lib.db.queue.add(ids[0]);
    final saved = await lib.db.playlists.create('Friday Night Regulars');
    await lib.db.playlists.addQueue(saved);
    final all = await lib.db.playlists.all();
    expect(all.map((p) => '${p.name}:${p.trackCount}'), ['80s Rock Set:2', 'Friday Night Regulars:1']);
    await lib.db.playlists.delete(pl);
    expect(await lib.db.playlists.all(), hasLength(1));
  });

  test('the same song can appear twice in a playlist', () async {
    final pl = await lib.db.playlists.create('Encores');
    await lib.db.playlists.add(pl, ids[0]);
    await lib.db.playlists.add(pl, ids[0]);
    expect(await lib.db.playlists.tracks(pl), hasLength(2));
  });

  test('playlists: add a block of songs, remove several at once', () async {
    final pl = await lib.db.playlists.create('Block');
    await lib.db.playlists.add(pl, ids[2]);
    await lib.db.playlists.addAll(pl, [ids[0], ids[1], ids[2]]);
    expect((await lib.db.playlists.tracks(pl)).map((t) => t.title), ['Shallow', 'Africa', 'Piano Man', 'Shallow']);
    await lib.db.playlists.removePositions(pl, [0, 2]);
    expect((await lib.db.playlists.tracks(pl)).map((t) => t.title), ['Africa', 'Shallow']);
    await lib.db.playlists.add(pl, ids[1]);
    expect((await lib.db.playlists.tracks(pl)).last.title, 'Piano Man');
  });

  test('a song is found by its folder and file name, wherever the library is', () async {
    final t = await lib.db.tracks.byPathEnding(r'A\toto - AFRICA.mp3');
    expect(t?.title, 'Africa');
    expect((await lib.db.tracks.byPathEnding('a/Billy Joel - Piano Man.mp3'))?.title, 'Piano Man');
    // The whole folder name must match, not just the end of it.
    expect(await lib.db.tracks.byPathEnding('xa/Toto - Africa.mp3'), isNull);
    expect(await lib.db.tracks.byPathEnding('b/Toto - Africa.mp3'), isNull);
    expect(await lib.db.tracks.byPathEnding(''), isNull);
  });

  test('a pasted song list is matched line by line', () async {
    final m = await lib.db.search.matchList('''
1. Africa - Toto
02 - Billy Joel\tPiano Man

• shallow.mp3
Nothing Like This At All
''');
    expect(m.map((e) => '${e.$1} => ${e.$2?.title}'), [
      'Africa - Toto => Africa',
      'Billy Joel - Piano Man => Piano Man',
      'shallow => Shallow',
      'Nothing Like This At All => null',
    ]);
  });

  test('songs drop in at any spot, and blocks move', () async {
    final pl = await lib.db.playlists.create('Order');
    await lib.db.playlists.addAll(pl, [ids[0], ids[1]]);
    await lib.db.playlists.insertAll(pl, [ids[2]], at: 1);
    expect((await lib.db.playlists.tracks(pl)).map((t) => t.title), ['Africa', 'Shallow', 'Piano Man']);
    await lib.db.playlists.moveBlock(pl, [0, 1], 3);
    expect((await lib.db.playlists.tracks(pl)).map((t) => t.title), ['Piano Man', 'Africa', 'Shallow']);
    await lib.db.playlists.moveBlock(pl, [2], 0);
    expect((await lib.db.playlists.tracks(pl)).map((t) => t.title), ['Shallow', 'Piano Man', 'Africa']);

    await lib.db.queue.add(ids[0]);
    await lib.db.queue.add(ids[1]);
    await lib.db.queue.insertAll([ids[2]], at: 0);
    var q = await lib.db.queue.all();
    expect(q.map((e) => e.track.title), ['Shallow', 'Africa', 'Piano Man']);
    expect(q.map((e) => e.position), [0, 1, 2]);
    await lib.db.queue.moveBlock([q[0].id, q[1].id], 3);
    q = await lib.db.queue.all();
    expect(q.map((e) => e.track.title), ['Piano Man', 'Shallow', 'Africa']);
  });

  test('an older database gets the played column when opened', () async {
    final path = p.join(lib.dir.path, 'old.db');
    await (await EztigerDatabase.open(databaseFactoryFfiNoIsolate, path)).close();
    final raw = await databaseFactoryFfiNoIsolate.openDatabase(path);
    await raw.execute('ALTER TABLE queue DROP COLUMN played_at');
    await raw.setVersion(1);
    await raw.close();
    final db = await EztigerDatabase.open(databaseFactoryFfiNoIsolate, path);
    final cols = (await db.db.rawQuery('PRAGMA table_info(queue)')).map((r) => r['name']);
    expect(cols, contains('played_at'));
    await db.close();
  });
}
