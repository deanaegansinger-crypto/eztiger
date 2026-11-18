import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:eztiger_core/eztiger_core.dart';
import 'package:test/test.dart';

import 'helpers.dart';

List<int> _be32(int v) => [v >> 24 & 255, v >> 16 & 255, v >> 8 & 255, v & 255];
List<int> _safe(int v) => [v >> 21 & 127, v >> 14 & 127, v >> 7 & 127, v & 127];

/// An ID3v2 tag with TIT2 / TPE1 frames ([major] 3 or 4), then fake audio.
List<int> id3v2(Map<String, String> frames, {int major = 3}) {
  final body = <int>[];
  frames.forEach((id, text) {
    final data = major == 4 ? [3, ...utf8.encode(text)] : [1, 0xff, 0xfe, for (final u in text.codeUnits) ...[u & 255, u >> 8]];
    body.addAll([...ascii.encode(id), ...(major == 4 ? _safe(data.length) : _be32(data.length)), 0, 0, ...data]);
  });
  body.addAll(List.filled(64, 0)); // padding
  return [...ascii.encode('ID3'), major, 0, 0, ..._safe(body.length), ...body, ...List.filled(400, 0x55)];
}

List<int> id3v1(String title, String artist) {
  List<int> field(String s, int n) => [...latin1.encode(s), ...List.filled(n - s.length, 0)];
  return [...List.filled(400, 0x55), ...ascii.encode('TAG'), ...field(title, 30), ...field(artist, 30), ...List.filled(65, 0)];
}

List<int> box(String type, List<int> body) => [..._be32(body.length + 8), ...latin1.encode(type), ...body];
List<int> item(String type, String text) => box(type, box('data', [0, 0, 0, 1, 0, 0, 0, 0, ...utf8.encode(text)]));

/// An MP4 with a big 'mdat' first and the tags in moov/udta/meta/ilst.
List<int> mp4(String title, String artist) => [
      ...box('ftyp', ascii.encode('isom0000')),
      ...box('mdat', List.filled(5000, 7)),
      ...box('moov', [
        ...box('mvhd', List.filled(20, 0)),
        ...box('udta', box('meta', [0, 0, 0, 0, ...box('hdlr', List.filled(25, 0)), ...box('ilst', [...item('©nam', title), ...item('©ART', artist)])])),
      ]),
    ];

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('ezt_tags'));
  tearDown(() => dir.deleteSync(recursive: true));
  String write(String name, List<int> bytes) => (File('${dir.path}/$name')..writeAsBytesSync(Uint8List.fromList(bytes))).path;

  test('ID3v2.3 (UTF-16) and 2.4 (UTF-8) title and artist', () {
    expect(readTags(write('a.mp3', id3v2({'TIT2': 'Sweet Caroline', 'TPE1': 'Neil Diamond'}))), (title: 'Sweet Caroline', artist: 'Neil Diamond'));
    expect(readTags(write('b.mp3', id3v2({'TPE1': 'Beyoncé', 'TIT2': 'Halo'}, major: 4))), (title: 'Halo', artist: 'Beyoncé'));
  });

  test('ID3v1 when there is no ID3v2; blank or placeholder tags count as missing', () {
    expect(readTags(write('c.mp3', id3v1('Waterloo', 'Abba'))), (title: 'Waterloo', artist: 'Abba'));
    expect(readTags(write('d.mp3', id3v2({'TIT2': 'Halo', 'TPE1': '  '}))), (title: 'Halo', artist: null));
    expect(readTags(write('e.mp3', id3v2({'TIT2': 'Track 03', 'TPE1': 'Unknown Artist'}))), (title: null, artist: null));
    expect(readTags(write('f.mp3', List.filled(500, 1))), (title: null, artist: null));
  });

  test('MP4 ©nam and ©ART, with the moov after the video data', () {
    expect(readTags(write('g.mp4', mp4('Bohemian Rhapsody', 'Queen'))), (title: 'Bohemian Rhapsody', artist: 'Queen'));
  });

  test('the library uses the tags (the file name where a tag is blank), and switches to file names and back', () async {
    final lib = await TestLibrary.create();
    addTearDown(lib.dispose);
    File(lib.path('Pop/SF001-01 - Wrong Name - Not This.mp3')).parent.createSync(recursive: true);
    File(lib.path('Pop/SF001-01 - Wrong Name - Not This.mp3')).writeAsBytesSync(id3v2({'TIT2': 'Sweet Caroline', 'TPE1': 'Neil Diamond'}));
    File(lib.path('Pop/Abba - Waterloo.mp3')).writeAsBytesSync(id3v2({'TIT2': 'Waterloo (Live)', 'TPE1': ''}));
    await lib.scan();
    var t = await lib.track('Pop/SF001-01 - Wrong Name - Not This.mp3');
    expect((t.title, t.artist), ('Sweet Caroline', 'Neil Diamond'));
    t = await lib.track('Pop/Abba - Waterloo.mp3');
    expect((t.title, t.artist), ('Waterloo (Live)', 'Abba'), reason: 'blank artist tag: the file name');
    expect(await lib.titles('neil diamond'), ['Sweet Caroline']);

    await lib.db.setNamesFrom('files');
    expect(await lib.db.namesFrom(), 'files');
    t = await lib.track('Pop/Abba - Waterloo.mp3');
    expect(t.title, 'Waterloo');
    expect(await lib.titles('neil diamond'), isEmpty);

    await lib.db.setNamesFrom('tags');
    t = await lib.track('Pop/SF001-01 - Wrong Name - Not This.mp3');
    expect(t.title, 'Sweet Caroline');
    expect(await lib.titles('sweet caroline'), ['Sweet Caroline']);
  });

  test('a folder can have its own Song names setting, which the folders inside it follow', () async {
    final lib = await TestLibrary.create();
    addTearDown(lib.dispose);
    for (final dir in ['Pop', 'Pop/80s', 'Rock']) {
      Directory(lib.path(dir)).createSync(recursive: true);
    }
    File(lib.path('Pop/80s/Wrong - Name.mp3')).writeAsBytesSync(id3v2({'TIT2': 'Africa', 'TPE1': 'Toto'}));
    File(lib.path('Rock/Wrong - Other.mp3')).writeAsBytesSync(id3v2({'TIT2': 'Livin On A Prayer', 'TPE1': 'Bon Jovi'}));
    await lib.scan();
    final pop = (await lib.db.folders.byPath(lib.path('Pop')))!;

    await lib.db.setFolderNamesFrom(pop.id, 'files');
    expect((await lib.track('Pop/80s/Wrong - Name.mp3')).artist, 'Wrong', reason: 'Pop and below: file names');
    expect((await lib.track('Rock/Wrong - Other.mp3')).artist, 'Bon Jovi', reason: 'the rest: the library (tags)');
    expect((await lib.db.folders.byPath(lib.path('Pop')))!.namesFrom, 'files');

    // A new song in the folder follows it after a rescan too.
    File(lib.path('Pop/80s/Also - Wrong.mp3')).writeAsBytesSync(id3v2({'TIT2': 'Take On Me', 'TPE1': 'A-ha'}));
    await lib.scan();
    expect((await lib.track('Pop/80s/Also - Wrong.mp3')).title, isNot('Take On Me'));

    await lib.db.setFolderNamesFrom(pop.id, null);
    expect((await lib.track('Pop/80s/Wrong - Name.mp3')).artist, 'Toto', reason: 'back to following the library');
  });
}
