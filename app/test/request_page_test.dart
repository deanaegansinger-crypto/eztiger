import 'dart:convert';
import 'dart:io';

import 'package:eztiger/app_state.dart';
import 'package:eztiger/edition.dart';
import 'package:eztiger/player.dart';
import 'package:eztiger/request_page.dart';
import 'package:eztiger_core/eztiger_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'fakes.dart';

void main() {
  sqfliteFfiInit();

  test('the version is the collection: the top folder under the library folder', () {
    final root = p.join('K', 'Karaoke');
    expect(brandOf(p.join(root, 'Sunfly Gold (SF)', 'SF001'), [root]), 'Sunfly');
    expect(brandOf(p.join(root, 'Zoom (ZM)', 'Elvis'), [root]), 'Zoom');
    expect(brandOf(p.join(root, 'Party Pack (PP)', 'Disc 1'), [root]), 'Party Pack');
    expect(brandOf(root, [root]), 'Karaoke', reason: 'songs right in the library folder');
  });

  test('the page: each song once, with its versions, the colours and the name', () {
    final template = File(p.join('requests', 'request-template.html')).readAsStringSync();
    final page = requestPageHtml(
      template: template,
      name: "Deano's <Karaoke>",
      logoBase64: 'AAAA',
      skin: 'nightdrive',
      songs: [
        (title: 'Waterloo', artist: 'Abba', brand: 'Sunfly', code: 'SF001'),
        (title: 'Waterloo', artist: 'Abba', brand: 'Zoom', code: 'ZM12'),
        (title: 'Bohemian Rhapsody', artist: 'Queen', brand: 'Sunfly', code: 'SF002'),
        (title: '</script><b>', artist: 'X', brand: 'Sunfly', code: 'SF003'),
      ],
    );
    expect(page.count, 3, reason: 'Waterloo once, with two versions');
    expect(RegExp(r'\{\{[A-Z_]+\}\}').hasMatch(page.html), isFalse, reason: 'every gap filled');
    expect(page.html, contains('Deano&#39;s &lt;Karaoke&gt;'));
    expect(page.html, contains('#2F8BFF'), reason: "Night Drive's accent");
    expect(page.html, contains(r'</script>'), reason: 'a title cannot end the script');
    final brands = RegExp(r'const BRANDS = (\[.*?\]);').firstMatch(page.html)!.group(1)!;
    expect(jsonDecode(brands), ['Sunfly', 'Zoom'], reason: 'biggest collection first');
    final songs = jsonDecode(RegExp(r'const SONGS = (\[.*?\]);', dotAll: true).firstMatch(page.html)!.group(1)!) as List;
    final waterloo = songs.firstWhere((x) => x[0] == 'Waterloo') as List;
    expect((waterloo[2] as String).split('|').toSet(), {'0~SF001', '1~ZM12'});
  });

  test('Start song requests: the page from this library, the list started, EZTiger connected', () async {
    isPro = true;
    final lib = makeLibrary();
    final data = Directory.systemTemp.createTempSync('ezt_req');
    final db = await EztigerDatabase.open(databaseFactoryFfiNoIsolate, inMemoryDatabasePath);
    final s = AppState(db, KaraokeEngine(FakeBackend(), scanEdges: (_) async => null));
    addTearDown(() async {
      s.setRequestsLink('');
      s.dispose();
      await db.close();
      lib.deleteSync(recursive: true);
      data.deleteSync(recursive: true);
    });
    await s.init(rescanLibrary: false);
    s.findPcAddress = () async => '192.168.1.20';
    final launched = <List<String>>[];
    s.launch = (exe, args) async => launched.add([exe, ...args]);
    s.requestTools = () => p.absolute('requests');

    // No songs yet: it says so, and starts nothing.
    await expectLater(s.startRequestList(), throwsA(isA<StateError>()));
    expect(launched, isEmpty);

    await s.addRootFolder(lib.path);
    final n = await s.startRequestList();
    expect(n, 3);
    expect(launched.single.first, 'powershell');
    final args = launched.single;
    expect(args[args.indexOf('-File') + 1], endsWith('request-server.ps1'));
    final page = File(args[args.indexOf('-Page') + 1]).readAsStringSync();
    expect(page, contains('Bohemian Rhapsody'));
    expect(s.requestsLink, 'localhost:8080');
    expect(s.songbookUrl, 'http://192.168.1.20:8080/', reason: 'the QR code opens the request page');
  });
}
