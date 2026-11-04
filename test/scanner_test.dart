import 'package:eztiger_core/eztiger_core.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  late TestLibrary lib;
  setUp(() async => lib = await TestLibrary.create());
  tearDown(() async => lib.dispose());

  test('pairs MP3+CDG case-insensitively and classifies every type', () async {
    lib.touch('backings/Reason To Believe.MP3');
    lib.touch('backings/Reason To Believe.CDG');
    lib.touch('backings/sweet caroline.mp3');
    lib.touch('acoustic tracks/Wonderwall.avi');
    lib.touch('vr trax/Shallow.mp4');
    lib.touch('vr trax/Shallow.mp4.vdjstems');
    lib.touch('from lee/ric trax/hurt.wav');
    lib.touch('backings/thumb.jpg');
    lib.touch('backings/Thumbs.db');
    lib.touch('backings/song.pk');
    final r = await lib.scan();
    expect(r.added, 5);
    expect((await lib.track('backings/Reason To Believe.MP3')).type, TrackType.cdg);
    expect((await lib.track('backings/sweet caroline.mp3')).type, TrackType.mp3);
    expect((await lib.track('acoustic tracks/Wonderwall.avi')).type, TrackType.mp4);
    final shallow = await lib.track('vr trax/Shallow.mp4');
    expect(shallow.hasStems, isTrue);
    expect(shallow.type, TrackType.mp4);
  });

  test('reports orphaned CDG files', () async {
    lib.touch('backings/3 working man.cdg');
    final r = await lib.scan();
    expect(r.added, 0);
    expect(r.orphanCdgs.single, endsWith('3 working man.cdg'));
  });

  test('unchanged rescan writes nothing', () async {
    lib.touch('a/Delilah - Tom Jones.mp3');
    lib.touch('a/Delilah - Tom Jones.cdg');
    await lib.scan();
    final r = await lib.scan();
    expect(r.changed, isFalse);
    expect(r.unchanged, 1);
  });

  test('freshness is mtime AND pairing: a CDG dropped beside an untouched MP3', () async {
    final when = DateTime(2024, 4, 1);
    lib.touch('a/Delilah - Tom Jones.mp3', mtime: when);
    await lib.scan();
    expect((await lib.track('a/Delilah - Tom Jones.mp3')).type, TrackType.mp3);

    lib.touch('a/Delilah - Tom Jones.cdg', mtime: when);
    var r = await lib.scan();
    expect(r.updated, 1);
    expect((await lib.track('a/Delilah - Tom Jones.mp3')).type, TrackType.cdg);

    lib.delete('a/Delilah - Tom Jones.cdg');
    r = await lib.scan();
    expect(r.updated, 1);
    expect((await lib.track('a/Delilah - Tom Jones.mp3')).type, TrackType.mp3);
  });

  test('a changed file keeps its id, so playlists, queue and history survive', () async {
    lib.touch('a/Delilah - Tom Jones.mp3', bytes: 10);
    await lib.scan();
    final t = await lib.track('a/Delilah - Tom Jones.mp3');
    final pl = await lib.db.playlists.create('Friday Night Regulars');
    await lib.db.playlists.add(pl, t.id);
    await lib.db.queue.add(t.id, singer: 'Dave M.');
    await lib.db.history.log(t.id, singer: 'Steph K.');

    lib.touch('a/Delilah - Tom Jones.mp3', bytes: 20, mtime: DateTime(2025, 1, 1));
    final r = await lib.scan();
    expect(r.updated, 1);
    final again = await lib.track('a/Delilah - Tom Jones.mp3');
    expect(again.id, t.id);
    expect(again.size, 20);
    expect((await lib.db.playlists.tracks(pl)).single.id, t.id);
    expect((await lib.db.queue.all()).single.track.id, t.id);
    expect((await lib.db.history.recent()).single.track.id, t.id);
  });

  test('a deleted file is removed (and leaves its playlists)', () async {
    lib.touch('a/one.mp3');
    lib.touch('a/two.mp3');
    await lib.scan();
    final pl = await lib.db.playlists.create('Set');
    await lib.db.playlists.add(pl, (await lib.track('a/one.mp3')).id);
    await lib.db.playlists.add(pl, (await lib.track('a/two.mp3')).id);
    lib.delete('a/one.mp3');
    final r = await lib.scan();
    expect(r.removed, 1);
    expect((await lib.db.playlists.tracks(pl)).map((t) => t.title), ['Two']);
  });

  test('a missing root (unplugged drive) changes nothing', () async {
    lib.touch('a/one.mp3');
    await lib.scan();
    final pl = await lib.db.playlists.create('Set');
    await lib.db.playlists.add(pl, (await lib.track('a/one.mp3')).id);
    final otherRoot = await lib.db.folders.addRoot('${lib.dir.path}/not-plugged-in');
    final r = await lib.scan();
    expect(r.missingRoots, ['${lib.dir.path}/not-plugged-in']);
    expect(r.removed, 0);
    expect((await lib.db.playlists.tracks(pl)), hasLength(1));
    expect(await lib.db.folders.byId(otherRoot), isNotNull);
  });

  test("Dean's tag edits survive rescans, including when the file changes", () async {
    lib.touch('a/ZM6S01-02 - Bad Moon Rising - Creedence Clearwater Revival.mp3');
    await lib.scan();
    var t = await lib.track('a/ZM6S01-02 - Bad Moon Rising - Creedence Clearwater Revival.mp3');
    await lib.db.tracks.editTags(t.id, title: 'Bad Moon Rising', artist: 'CCR', type: TrackType.mp4);
    lib.touch('a/ZM6S01-02 - Bad Moon Rising - Creedence Clearwater Revival.mp3',
        bytes: 99, mtime: DateTime(2025));
    await lib.scan();
    t = await lib.track('a/ZM6S01-02 - Bad Moon Rising - Creedence Clearwater Revival.mp3');
    expect(t.title, 'Bad Moon Rising');
    expect(t.artist, 'CCR');
    expect(t.type, TrackType.mp4);
    expect(await lib.titles('ccr'), ['Bad Moon Rising']);
    await lib.db.tracks.editTags(t.id, artist: '', clearType: true);
    t = await lib.track('a/ZM6S01-02 - Bad Moon Rising - Creedence Clearwater Revival.mp3');
    expect(t.userArtist, isNull);
    expect(t.type, TrackType.mp3);
  });

  test('zipped MP3+G is indexed, and skipped when an extracted copy sits beside it', () async {
    lib.zip('trinity night/legends/Return To Sender - Elvis Presley.zip',
        ['Return To Sender - Elvis Presley.mp3', 'Return To Sender - Elvis Presley.cdg']);
    lib.zip(
        'trinity night/legends/Sway - Dean Martin.zip', ['Sway - Dean Martin.mp3', 'Sway - Dean Martin.cdg']);
    lib.touch('trinity night/legends/Sway - Dean Martin.mp3');
    lib.touch('trinity night/legends/Sway - Dean Martin.cdg');
    lib.zip('trinity night/legends/photos.zip', ['a.jpg']);
    final r = await lib.scan();
    expect(r.added, 2);
    expect(r.duplicateZipsSkipped, 1);
    final zipped = await lib.track('trinity night/legends/Return To Sender - Elvis Presley.zip');
    expect(zipped.isZipped, isTrue);
    expect(zipped.type, TrackType.cdg);
    expect((await lib.scan()).changed, isFalse);
  });

  test('lyric sheets: same name, "lyrics X", and a sibling lyrics folder', () async {
    lib.touch('backings/minnie the moocher.mp3');
    lib.touch('backings/minnie the moocher.txt', text: 'hi de hi de hi de ho');
    lib.touch('backings/Mack The Knife.mp3');
    lib.touch('backings/lyrics Mack The Knife.txt', text: 'oh the shark babe');
    lib.touch('motown show/set 1/My Girl - The Temptations.mp3');
    lib.touch('motown show/motown lyrics/my girl.txt', text: 'sunshine on a cloudy day');
    lib.touch('backings/duo show list.txt', text: 'set list');
    final r = await lib.scan();
    expect(r.lyricSheetsUnmatched, 1);
    expect((await lib.track('backings/minnie the moocher.mp3')).hasLyricSheet, isTrue);
    expect((await lib.track('backings/Mack The Knife.mp3')).hasLyricSheet, isTrue);
    final myGirl = await lib.track('motown show/set 1/My Girl - The Temptations.mp3');
    expect(myGirl.lyricsPath, endsWith('my girl.txt'));
    expect(await lib.db.tracks.lyrics(myGirl.id), 'sunshine on a cloudy day');
    expect(await lib.titles('cloudy day'), ['My Girl']);
  });

  test('ambiguous A - B names are settled by the rest of the library', () async {
    // Dean Martin appears with several titles, so it must be the artist,
    // whichever side of the dash it is on.
    lib.touch('dm/Sway - Dean Martin.mp3');
    lib.touch('dm/Dean Martin - Volare.mp3');
    lib.touch('dm/Dean Martin - Thats Amore.mp3');
    lib.touch('dm/Mambo Italiano - Dean Martin.mp3');
    await lib.scan();
    for (final f in [
      'Sway - Dean Martin',
      'Dean Martin - Volare',
      'Dean Martin - Thats Amore',
      'Mambo Italiano - Dean Martin'
    ]) {
      expect((await lib.track('dm/$f.mp3')).artist, 'Dean Martin', reason: f);
    }
  });

  test('excluded folders are hidden from search and kept intact', () async {
    lib.touch('christmas show/Last Christmas - Wham.mp3');
    lib.touch('backings/Sway - Dean Martin.mp3');
    await lib.scan();
    final xmas = (await lib.db.folders.byPath(lib.path('christmas show')))!;
    await lib.db.folders.setIncluded(xmas.id, false);
    lib.delete('christmas show/Last Christmas - Wham.mp3');
    final r = await lib.scan();
    expect(r.removed, 0, reason: 'excluded folders are not walked, so nothing in them is deleted');
    expect(await lib.titles('last christmas'), isEmpty);
    await lib.db.folders.setIncluded(xmas.id, true);
    expect((await lib.scan()).removed, 1);
  });

  test('folder tree counts', () async {
    lib.touch('backings/a.mp3');
    lib.touch('backings/motown show/b.mp3');
    lib.touch('backings/motown show/c.mp3');
    lib.touch('vr trax/d.mp4');
    await lib.scan();
    final root = (await lib.db.folders.roots()).single;
    expect(root.totalCount, 4);
    final kids = await lib.db.folders.children(root.id);
    expect(kids.map((f) => '${f.name}:${f.trackCount}/${f.totalCount}'), ['backings:1/3', 'vr trax:1/1']);
    expect(kids.first.hasChildren, isTrue);
    lib.delete('backings/motown show/c.mp3');
    await lib.scan();
    expect((await lib.db.folders.byId(root.id))!.totalCount, 3);
  });

  test('big mix albums are tagged as mixes, not hidden', () async {
    lib.touch('christmas show/mix album.mp3', bytes: 70 * 1024 * 1024);
    await lib.scan();
    final t = await lib.track('christmas show/mix album.mp3');
    expect(t.category, 'mix');
  });
}
