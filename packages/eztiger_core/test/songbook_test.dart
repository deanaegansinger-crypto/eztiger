import 'package:eztiger_core/eztiger_core.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  test(
      'the songbook lists each song once, by artist, from searchable folders only',
      () async {
    final lib = await TestLibrary.create();
    addTearDown(lib.dispose);
    lib.touch('a/Toto - Africa.mp3');
    lib.touch('a/Toto - Africa (Karaoke Version).mp4');
    lib.touch('a/ABBA - Waterloo.mp3');
    lib.touch('hidden/Queen - Bohemian Rhapsody.mp3');
    await lib.scan();
    final hidden = (await lib.db.folders.roots()).first;
    final sub = (await lib.db.folders.children(hidden.id))
        .firstWhere((f) => f.name == 'hidden');
    await lib.db.folders.setIncluded(sub.id, false);

    final songs = await lib.db.tracks.songbook();
    expect(songs.map((s) => '${s.artist} - ${s.title}'),
        ['ABBA - Waterloo', 'Toto - Africa']);
  });

  test('the songbook page holds the songs safely and needs no other files', () {
    final html = songbookHtml(
      title: "Deano's <Songs>",
      songs: [
        (artist: 'AC/DC', title: 'Back In Black'),
        (artist: 'Odd', title: 'Ends </script><script>alert(1)</script>'),
      ],
      updated: DateTime(2026, 11, 9),
    );
    expect(html, startsWith('<!DOCTYPE html>'));
    expect(html, contains('<title>Deano&#39;s &lt;Songs&gt;</title>'));
    expect(html, contains('2 songs · updated 9 Nov 2026'));
    expect(html, contains('Back In Black'));
    // A song name can't close the page's script.
    expect('</script>'.allMatches(html), hasLength(1));
    expect(html, isNot(contains('src=')));
    expect(html, isNot(contains('href="http')));
  });
}
