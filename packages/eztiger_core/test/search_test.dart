import 'package:eztiger_core/eztiger_core.dart';
import 'package:test/test.dart';

import 'helpers.dart';

Future<void> seed(TestLibrary lib) async {
  lib.touch('backings/Neil Diamond - Sweet Caroline.mp3');
  lib.touch('backings/Neil Diamond - Sweet Caroline.cdg');
  lib.touch('backings 2/Neil Diamond - Sweet Caroline.mp3');
  lib.touch('vr trax/Neil Diamond - Sweet Caroline.mp4');
  lib.touch("backings/Journey - Don't Stop Believin'.mp3");
  lib.touch('backings/Simon & Garfunkel - Mrs Robinson.mp3');
  lib.touch("backings/Elvis Presley - Can't Help Falling In Love.mp3");
  lib.touch('trinity night/Elvis Presley - Return To Sender.mp3');
  lib.touch('trinity night/Dean Martin - Sway down 2.mp3');
  lib.touch('backings/Energy 52 - Café Del Mar.mp3');
  await lib.scan();
}

void main() {
  for (final fts in [true, false]) {
    group(fts ? 'FTS5' : 'LIKE fallback', () {
      late TestLibrary lib;
      setUp(() async {
        lib = await TestLibrary.create(disableFts: !fts);
        expect(lib.db.hasFts, fts);
        await seed(lib);
      });
      tearDown(() async => lib.dispose());

      test('sorts A to Z by title or by artist', () async {
        final byTitle = await lib.db.search.search('', sort: SearchSort.title);
        expect(byTitle.map((g) => g.primary.title).take(3),
            ['Café Del Mar', "Can't Help Falling In Love", "Don't Stop Believin'"]);
        final byArtist = await lib.db.search.search('', sort: SearchSort.artist);
        expect(byArtist.map((g) => g.primary.artist).toList(), [
          'Dean Martin',
          'Elvis Presley',
          'Elvis Presley',
          'Energy 52',
          'Journey',
          'Neil Diamond',
          'Simon & Garfunkel'
        ]);
        expect(byArtist[1].primary.title, "Can't Help Falling In Love"); // then by title
        final found = await lib.db.search.search('elvis', sort: SearchSort.title);
        expect(found.map((g) => g.primary.title), ["Can't Help Falling In Love", 'Return To Sender']);
        final cdg = await lib.db.search.search('', type: TrackType.cdg, sort: SearchSort.artist);
        expect(cdg.single.primary.title, 'Sweet Caroline');
      });

      test('finds by title and by artist', () async {
        expect(await lib.titles('sweet caroline'), ['Sweet Caroline']);
        expect(await lib.titles('neil diamond'), ['Sweet Caroline']);
      });

      test('ignores apostrophes, case and & vs and', () async {
        expect(await lib.titles('dont stop'), ["Don't Stop Believin'"]);
        expect(await lib.titles('DON’T STOP'), ["Don't Stop Believin'"]);
        expect(await lib.titles('simon and garfunkel'), ['Mrs Robinson']);
        // Accent folding needs FTS5; the LIKE fallback is a basic mode.
        if (fts) expect(await lib.titles('cafe'), ['Café Del Mar']);
      });

      test('copies of a song in different folders come back as one result', () async {
        final groups = await lib.db.search.search('sweet caroline');
        expect(groups, hasLength(1));
        expect(groups.single.versions, hasLength(3));
        expect(groups.single.versions.map((t) => t.type).toSet(), {TrackType.cdg, TrackType.mp3, TrackType.mp4});
      });

      test('searches folder names (set lists and shows)', () async {
        expect((await lib.titles('trinity night'))..sort(), ['Return To Sender', 'Sway']);
      });

      test("searches Dean's version notes", () async {
        expect(await lib.titles('down 2'), ['Sway']);
      });

      test('filters by folder subtree and by type', () async {
        final trinity = (await lib.db.folders.byPath(lib.path('trinity night')))!;
        expect(await lib.titles('elvis', folderId: trinity.id), ['Return To Sender']);
        final cdg = await lib.db.search.search('sweet caroline', type: TrackType.cdg);
        expect(cdg.single.versions.single.type, TrackType.cdg);
      });

      test('empty query lists everything in scope', () async {
        final trinity = (await lib.db.folders.byPath(lib.path('trinity night')))!;
        expect(await lib.titles('', folderId: trinity.id), ['Return To Sender', 'Sway']);
      });

      if (fts) {
        test('prefix matching while typing', () async {
          expect(await lib.titles('swe car'), ['Sweet Caroline']);
        });

        test('corrects misspellings', () async {
          expect(await lib.titles('cant help faling'), ["Can't Help Falling In Love"]);
          expect(await lib.titles('trintry'), containsAll(['Return To Sender', 'Sway']));
        });

        test('falls back to any word when no song has them all', () async {
          expect(await lib.titles('show me trinity night songs'), containsAll(['Return To Sender', 'Sway']));
        });

        test('index follows tag edits immediately', () async {
          final t = (await lib.db.search.search('mrs robinson')).single.primary;
          await lib.db.tracks.editTags(t.id, title: 'Here’s To You');
          expect(await lib.titles('heres to you'), ['Here’s To You']);
          expect(await lib.titles('mrs robinson'), isNot(contains('Mrs Robinson')));
        });
      }
    });
  }
}
