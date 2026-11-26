import 'dart:convert';
import 'dart:io';

import 'package:eztiger/promos.dart';
import 'package:eztiger/request_page.dart';
import 'package:eztiger/second_screen.dart';
import 'package:eztiger/ui/venue_dialog.dart';
import 'package:eztiger/venue.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory root;
  late VenueStore store;
  final sep = Platform.pathSeparator;
  setUp(() {
    root = Directory.systemTemp.createTempSync('ezvenues');
    store = VenueStore('${root.path}${sep}EZTiger Venues');
  });
  tearDown(() => root.deleteSync(recursive: true));

  File picture(String name) => File('${root.path}$sep$name')..writeAsBytesSync([137, 80, 78, 71, 1, 2, 3]);
  Map<String, dynamic> json(String rel) => jsonDecode(File('${store.root}$sep$rel').readAsStringSync()) as Map<String, dynamic>;

  test('makes the venues folder on its own, in the format bingo and quiz read', () {
    expect(Directory(store.root).existsSync(), isFalse);
    expect(store.save(name: '').ok, isFalse);
    final r = store.save(name: '  Hotel   Costa Azul ', tagline: 'Karaoke every Friday', colour: '#880C7E');
    expect(r.ok, isTrue);
    expect(r.venue!.id, 'Hotel Costa Azul');
    expect(json('Hotel Costa Azul${sep}venue.json'), {
      'name': 'Hotel Costa Azul',
      'tagline': 'Karaoke every Friday',
      'colour': '#880c7e',
      'logo': '',
      'photos': <String>[],
    });
    // A colour that isn't #rrggbb falls back to the usual one.
    expect(store.save(id: 'Hotel Costa Azul', name: 'Hotel Costa Azul', colour: 'pink').venue!.colour, Venue.defaultColour);

    // Switching it on writes active.json, as Music Bingo and Quiz Night do.
    expect(store.active(), isNull);
    store.setActive('Hotel Costa Azul', true);
    expect(json('active.json'), {'venue': 'Hotel Costa Azul', 'on': true});
    expect(store.active()!.name, 'Hotel Costa Azul');
    expect(store.setActive('Gone', true).ok, isFalse);

    // Renaming moves the folder, and the chosen venue follows it.
    final moved = store.save(id: 'Hotel Costa Azul', name: 'Costa Azul', colour: '#123456');
    expect(moved.venue!.id, 'Costa Azul');
    expect(Directory('${store.root}${sep}Hotel Costa Azul').existsSync(), isFalse);
    expect(store.activeSetting().venue, 'Costa Azul');
    store.save(name: 'Seaview');
    expect(store.save(id: 'Seaview', name: 'Costa Azul').ok, isFalse, reason: 'already a venue with that name');
    expect(store.list().map((v) => v.name), ['Costa Azul', 'Seaview']);

    store.delete('Costa Azul');
    expect(store.list().map((v) => v.name), ['Seaview']);
    expect(store.activeSetting(), (venue: '', on: false));
  });

  test('logo and up to 3 photos are copied in', () {
    store.save(name: 'Seaview');
    expect(store.addImage('Seaview', logo: true, from: picture('notes.txt').path).ok, isFalse);
    expect(store.addImage('Seaview', logo: true, from: picture('Our Logo.png').path).ok, isTrue);
    for (var i = 1; i <= 3; i++) {
      expect(store.addImage('Seaview', logo: false, from: picture('p$i.jpg').path).ok, isTrue);
    }
    final full = store.addImage('Seaview', logo: false, from: picture('p4.jpg').path);
    expect(full.ok, isFalse);
    expect(full.error, contains('3 photos'));
    var v = store.read('Seaview')!;
    expect(v.logo, 'logo.png');
    expect(v.photos, ['photo-1.jpg', 'photo-2.jpg', 'photo-3.jpg']);
    expect(File(v.logoPath!).existsSync(), isTrue);

    v = store.removeImage('Seaview', 'photo-2.jpg').venue!;
    expect(v.photos, ['photo-1.jpg', 'photo-3.jpg']);
    v = store.addImage('Seaview', logo: false, from: picture('p5.webp').path).venue!;
    expect(v.photos, ['photo-1.jpg', 'photo-3.jpg', 'photo-2.webp']);
  });

  test("promos go with the chosen venue, and EZTiger's second screen reads them", () {
    // No venue chosen: the general set.
    store.addTextPromo(main: 'Quiz on Tuesday', theme: 'activity');
    expect(File('${store.root}${sep}_promos${sep}promos.json').existsSync(), isTrue);

    store.save(name: 'Seaview');
    store.setActive('Seaview', false);
    final id = store.addTextPromo(top: 'Happy hour', main: '2 for 1 cocktails', detail: 'Pool bar till 10', theme: 'nonsense');
    expect(store.addPromoImage(picture('menu.png').path).ok, isTrue);
    expect(store.addPromoImage(picture('menu.svg').path).ok, isFalse);

    final j = store.readPromoFile();
    expect(j['slides'].map((s) => s['kind']), ['text', 'image']);
    expect(j['slides'][0]['theme'], 'cocktails');
    j['seconds'] = 15;
    j['mix'] = 'full';
    (j['slides'] as List).insert(0, (j['slides'] as List).removeAt(1));
    store.savePromoFile(j);

    final set = readPromos(store.root);
    expect(set.seconds, 15);
    expect(set.full, isTrue);
    expect(set.slides.map((s) => s.kind), ['image', 'text']);
    expect(set.slides[1].main, '2 for 1 cocktails');

    store.removePromo(id);
    store.removePromo(set.slides.first.id);
    expect(readPromos(store.root).slides, isEmpty);
    expect(Directory('${store.root}${sep}Seaview${sep}promos').listSync(), isEmpty, reason: 'the picture goes too');
  });

  test('the apps find each other through apps.json', () {
    expect(store.apps(env: const {}), isEmpty);
    final bingo = picture('Music Bingo.exe');
    final when = DateTime.utc(2026, 11, 26, 20);
    // What Music Bingo writes when it opens (eztiger_venue.register_app).
    File('${store.root}${sep}apps.json')
      ..createSync(recursive: true)
      ..writeAsStringSync(jsonEncode({
        'apps': {
          'bingo': {'name': 'Music Bingo', 'version': '', 'path': bingo.path, 'seen': when.toIso8601String()},
          'quiz': {'name': 'EZTiger Quiz Night', 'path': '${root.path}${sep}gone.exe', 'seen': when.toIso8601String()},
        },
      }));
    store.registerApp('karaoke', path: picture('eztiger.exe').path, now: when);
    final apps = {for (final a in store.apps(env: const {})) a.key: a};
    expect(apps.keys, ['karaoke', 'bingo'], reason: 'quiz was uninstalled: its exe is gone');
    expect(apps['bingo']!.seen, when);
    // Karaoke kept the other apps' entries.
    expect((json('apps.json')['apps'] as Map).keys, containsAll(['bingo', 'quiz', 'karaoke']));
  });

  testWidgets('the venue box: add a venue, switch it on, add a promo, see the other apps', (tester) async {
    final bingo = picture('Music Bingo.exe');
    File('${store.root}${sep}apps.json')
      ..createSync(recursive: true)
      ..writeAsStringSync(jsonEncode({
        'apps': {'bingo': {'name': 'Music Bingo', 'path': bingo.path, 'seen': DateTime.now().toUtc().toIso8601String()}},
      }));
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(onPressed: () => showVenueBranding(context, store: store), child: const Text('open')),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('venue-dialog')), findsOneWidget);
    expect(find.textContaining('Music Bingo: found, sharing these venues (used today)'), findsOneWidget);
    expect(find.textContaining('EZTiger Quiz Night: not on this PC'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('venue-name')), 'Seaview Holiday Park');
    await tester.enterText(find.byKey(const Key('venue-tagline')), 'Karaoke every Friday');
    await tester.tap(find.byKey(const Key('venue-save')));
    await tester.pumpAndSettle();
    expect(find.text('✓ Saved Seaview Holiday Park.'), findsOneWidget);
    expect(store.read('Seaview Holiday Park')!.tagline, 'Karaoke every Friday');
    expect(store.activeSetting().venue, 'Seaview Holiday Park', reason: 'the first venue is the chosen one');

    await tester.tap(find.byKey(const Key('venue-on')));
    await tester.pumpAndSettle();
    expect(store.active()!.name, 'Seaview Holiday Park');
    expect(find.text('Showing Seaview Holiday Park'), findsOneWidget);

    await tester.ensureVisible(find.byKey(const Key('promo-add-text')));
    await tester.tap(find.byKey(const Key('promo-add-text')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('slide-main')), 'Steak night');
    await tester.tap(find.byKey(const Key('slide-add')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Steak night'), findsOneWidget);
    expect(readPromos(store.root).slides.single.main, 'Steak night');

    await tester.tap(find.byKey(const Key('venue-close')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('venue-dialog')), findsNothing);
  });

  testWidgets('the second screen between singers shows the venue', (tester) async {
    store.save(name: 'Seaview', tagline: 'Karaoke every Friday');
    final v = store.read('Seaview')!;
    await tester.pumpWidget(MaterialApp(home: VenueScreen(venue: v, title: 'Waterloo', artist: 'Abba', singer: 'Dean')));
    expect(find.byKey(const Key('venue-screen-name')), findsOneWidget);
    expect(find.text('Karaoke every Friday'), findsOneWidget);
    expect(find.text('🎤 Dean'), findsOneWidget);
    expect(find.text(VenueScreen.poweredBy), findsOneWidget);
  });

  test('the request page carries the venue', () {
    const template = '<title>{{NAME}}</title><img src="data:image/png;base64,{{LOGO}}"><h1>{{NAME}}</h1>'
        '<footer>Powered by EZTiger</footer>{{COUNT}}{{SONGS}}{{BRANDS}}';
    final songs = [(title: 'Waterloo', artist: 'Abba', brand: 'SF', code: 'SF001')];
    final plain = requestPageHtml(template: template, name: 'EZTiger Karaoke', logoBase64: 'AA', skin: 'classic', songs: songs).html;
    expect(plain, contains('Powered by EZTiger<'));
    final branded = requestPageHtml(
      template: template,
      name: 'Seaview & Co',
      logoBase64: 'BB',
      skin: 'classic',
      songs: songs,
      venue: true,
      logoType: 'image/jpeg',
      tagline: 'Karaoke <every> Friday',
    ).html;
    expect(branded, contains('<h1>Seaview &amp; Co</h1>'));
    expect(branded, contains('data:image/jpeg;base64,BB'));
    expect(branded, contains('Karaoke &lt;every&gt; Friday'));
    expect(branded, contains('Powered by EZTiger Entertainment<'));
  });
}
