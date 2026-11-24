import 'dart:convert';
import 'dart:io';

import 'package:eztiger/promos.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory root;
  setUp(() => root = Directory.systemTemp.createTempSync('ezpromos'));
  tearDown(() => root.deleteSync(recursive: true));

  void write(String rel, Object json) {
    final f = File('${root.path}${Platform.pathSeparator}$rel')..createSync(recursive: true);
    f.writeAsStringSync(jsonEncode(json));
  }

  test('reads the general set when no venue is chosen, skipping hidden and missing slides', () {
    write('_promos/promos.json', {
      'on': true, 'seconds': 5, 'gap': 6, 'mix': 'turns',
      'slides': [
        {'id': 'a', 'kind': 'text', 'top': 'Happy Hour', 'main': '2 for 1', 'detail': '5-7pm', 'theme': 'cocktails'},
        {'id': 'b', 'kind': 'text', 'main': 'Hidden', 'on': false},
        {'id': 'c', 'kind': 'image', 'file': 'missing.jpg'},
      ],
    });
    final s = readPromos(root.path);
    expect(s.usable, isTrue);
    expect(s.seconds, 5);
    expect(s.full, isFalse);
    expect(s.slides.map((x) => x.id), ['a']);
  });

  test("uses the chosen venue's own promos", () {
    write('Hotel Costa Azul/venue.json', {'name': 'Hotel Costa Azul'});
    write('active.json', {'venue': 'Hotel Costa Azul', 'on': false});
    write('Hotel Costa Azul/promos.json', {'slides': [{'id': 'v', 'kind': 'text', 'main': 'Steak night'}], 'mix': 'full'});
    write('_promos/promos.json', {'slides': [{'id': 'g', 'kind': 'text', 'main': 'General'}]});
    final s = readPromos(root.path);
    expect(s.slides.single.main, 'Steak night');
    expect(s.full, isTrue);
  });

  test('venue folder names match the other apps', () {
    expect(venueFolderName('  Bar:  "Nil" / Calis. '), 'Bar Nil  Calis');
    expect(venueFolderName('***'), 'Venue');
  });

  test('takes turns with the idle screen between acts, and stops when a song plays', () {
    var t = DateTime(2026, 1, 1, 20);
    final p = PromoPlayer(
      read: ([_]) => PromoSet(on: true, seconds: 8, gap: 12, slides: [
        PromoSlide(id: 'a', kind: 'text', main: 'A'),
        PromoSlide(id: 'b', kind: 'text', main: 'B'),
      ]),
      now: () => t,
    )..reload();
    p.update(true);
    expect(p.showing, isNull); // the "up next" screen first
    t = t.add(const Duration(seconds: 7));
    p.update(true);
    expect(p.showing?.id, 'a');
    t = t.add(const Duration(seconds: 9));
    p.update(true);
    expect(p.showing, isNull); // back to the idle screen
    t = t.add(const Duration(seconds: 13));
    p.update(true);
    expect(p.showing?.id, 'b');
    p.update(false); // the next singer starts
    expect(p.showing, isNull);
    p.dispose();
  });
}
