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
    await lib.db.queue.markSung(q3);
    await lib.db.queue.remove(q1);
    final q = await lib.db.queue.all();
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
}
