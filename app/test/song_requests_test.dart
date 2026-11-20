import 'dart:convert';
import 'dart:io';

import 'package:eztiger/app_state.dart';
import 'package:eztiger/player.dart';
import 'package:eztiger/song_requests.dart';
import 'package:eztiger_core/eztiger_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'fakes.dart';

void main() {
  sqfliteFfiInit();
  late Directory lib;
  late EztigerDatabase db;
  late AppState state;

  setUp(() async {
    // Real network calls to the pretend request list below.
    final saved = HttpOverrides.current;
    HttpOverrides.global = null;
    addTearDown(() => HttpOverrides.global = saved);
    lib = makeLibrary();
    db = await EztigerDatabase.open(databaseFactoryFfiNoIsolate, inMemoryDatabasePath);
    state = AppState(db, KaraokeEngine(FakeBackend(), scanEdges: (_) async => null));
    await state.init(rescanLibrary: false);
    await state.addRootFolder(lib.path);
  });

  tearDown(() async {
    state.dispose();
    await db.close();
    lib.deleteSync(recursive: true);
  });

  test('the link to the request list: on the PC, or the DJ link on a tablet', () {
    final pc = RequestServer.parse('localhost:8080')!;
    expect(pc.base.toString(), 'http://localhost:8080');
    expect(pc.key, '');
    final tablet = RequestServer.parse(' http://192.168.1.20:8080/dj?key=ab12cd ')!;
    expect(tablet.base.toString(), 'http://192.168.1.20:8080');
    expect(tablet.key, 'ab12cd');
    expect(RequestServer.parse(''), isNull);
    expect(RequestServer.parse('ftp://somewhere'), isNull);
    expect(pc.online, isFalse);
    expect(tablet.online, isFalse, reason: 'another device on the Wi-Fi');
    final web = RequestServer.parse('https://eztiger-requests.deano.workers.dev/dj?key=Zx9')!;
    expect(web.online, isTrue);
    expect(web.singerPage, 'https://eztiger-requests.deano.workers.dev/');
    expect(web.djList, 'https://eztiger-requests.deano.workers.dev/dj?key=Zx9');
    // A DJ's own list on the shared service, under /v/<id>/.
    final shared = RequestServer.parse('https://eztiger-requests.deano.workers.dev/v/ab12cd34/dj?key=Qq7')!;
    expect(shared.online, isTrue);
    expect(shared.prefix, '/v/ab12cd34');
    expect(shared.singerPage, 'https://eztiger-requests.deano.workers.dev/v/ab12cd34/');
    expect(shared.djList, 'https://eztiger-requests.deano.workers.dev/v/ab12cd34/dj?key=Qq7');
    expect(pc.prefix, '');
    expect(tablet.prefix, '');
  });

  test('a new DJ gets their own list on the shared online service', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final asked = <String>[];
    server.listen((req) async {
      final body = await utf8.decoder.bind(req).join();
      asked.add('${req.method} ${req.uri.path} $body');
      req.response.headers.contentType = ContentType.json;
      if (body.contains('Full')) {
        req.response.statusCode = 429;
        req.response.write('{"ok":false,"error":"Too many new request pages today"}');
      } else {
        req.response.write('{"ok":true,"link":"http://x/v/ab12cd34/","dj":"http://127.0.0.1:${server.port}/v/ab12cd34/dj?key=K9"}');
      }
      await req.response.close();
    });
    addTearDown(() => server.close(force: true));
    final http = HttpClient();
    addTearDown(() => http.close(force: true));
    final dj = await RequestServer.register(http, 'http://127.0.0.1:${server.port}', "Deano's Karaoke");
    expect(asked.single, startsWith('POST /register name=Deano'));
    expect(RequestServer.parse(dj)!.prefix, '/v/ab12cd34');
    await expectLater(RequestServer.register(http, 'http://127.0.0.1:${server.port}', 'Full'),
        throwsA(isA<HttpException>().having((e) => e.message, 'message', contains('Too many'))));

    // The app connects to it straight away.
    state.registerOnline = (http, name) async => dj;
    await state.getOnlineRequestPage();
    expect(state.requestsLink, dj);
    expect(state.requestsOnline, isFalse, reason: '127.0.0.1 is this PC, not online');
    // Stop checking the list, and let a check already under way finish before tearDown.
    state.setRequestsLink('');
    await Future<void>.delayed(const Duration(milliseconds: 500));
  });

  test('the singers\' page goes to the online request list gzipped, with the DJ code, name and time zone', () async {
    final got = <String, Object>{};
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((req) async {
      final bytes = await req.fold<List<int>>([], (a, b) => a..addAll(b));
      got['method'] = req.method;
      got['query'] = req.uri.queryParameters;
      got['page'] = utf8.decode(gzip.decode(bytes));
      req.response.statusCode = req.uri.queryParameters['key'] == 'Zx9' ? 200 : 403;
      req.response.write('{"ok":true}');
      await req.response.close();
    });
    addTearDown(() => server.close(force: true));
    final http = HttpClient();
    addTearDown(() => http.close(force: true));
    final ok = RequestServer.parse('http://127.0.0.1:${server.port}/dj?key=Zx9')!;
    await ok.publishPage(http, '<html>Waterloo</html>', name: 'Deano\'s Karaoke');
    expect(got['method'], 'PUT');
    expect(got['page'], '<html>Waterloo</html>');
    final q = got['query']! as Map<String, String>;
    expect(q['name'], 'Deano\'s Karaoke');
    expect(int.parse(q['tz']!), DateTime.now().timeZoneOffset.inMinutes);
    final wrong = RequestServer.parse('http://127.0.0.1:${server.port}/dj?key=nope')!;
    await expectLater(wrong.publishPage(http, '<html></html>', name: 'x'), throwsA(isA<RequestServerRefused>()));
  });

  test('songs in the request list\'s singing queue come into Tonight\'s playlist with the singer', () async {
    final waiting = [
      // The exact file, from a PC whose library is somewhere else.
      {'Id': '1', 'Singer': 'Deano', 'Title': 'Waterloo', 'Artist': 'ABBA', 'Path': r'C:\Karaoke\Pop\Abba - Waterloo.mp3',
       'File': r'Pop\Abba - Waterloo.mp3'},
      // No file known: found by its title and artist.
      {'Id': '2', 'Singer': 'Kim & Jo', 'Title': "Livin' On A Prayer", 'Artist': 'Bon Jovi', 'Path': '', 'File': ''},
      // Not in this library.
      {'Id': '3', 'Singer': 'Sam', 'Title': 'Waterloo Sunset', 'Artist': 'The Kinks', 'Path': '', 'File': ''},
    ];
    final sent = <String, String>{};
    final keys = <String?>{};
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((req) async {
      keys.add(req.uri.queryParameters['key']);
      if (req.method == 'GET' && req.uri.path == '/app/next') {
        req.response.headers.contentType = ContentType.json;
        req.response.write(jsonEncode([for (final w in waiting) if (!sent.containsKey(w['Id'])) w]));
      } else if (req.method == 'POST' && req.uri.path == '/app/sent') {
        sent[req.uri.queryParameters['id']!] = req.uri.queryParameters['found']!;
      } else {
        req.response.statusCode = 404;
      }
      await req.response.close();
    });

    state.requestsLink = 'http://127.0.0.1:${server.port}/dj?key=ab12cd';
    await state.checkSongRequests();
    expect(state.requestsState, RequestsState.connected);
    expect(state.queue.map((e) => '${e.singer}: ${e.track.title}'), ['Deano: Waterloo', 'Kim & Jo: Livin On A Prayer']);
    expect(sent, {'1': '1', '2': '1', '3': '0'}, reason: 'the request list is told what went in, and what is missing');
    expect(keys, {'ab12cd'});
    expect(state.status, contains('Waterloo Sunset'));

    // Nothing new: nothing goes in twice.
    await state.checkSongRequests();
    expect(state.queue, hasLength(2));

    // The request list closed: shown as not connected.
    await server.close(force: true);
    await state.checkSongRequests();
    expect(state.requestsState, RequestsState.unreachable);
  });

  test('the request list asks for the DJ code when the link has none', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((req) async {
      req.response.statusCode = 403;
      await req.response.close();
    });
    state.requestsLink = '127.0.0.1:${server.port}';
    await state.checkSongRequests();
    expect(state.requestsState, RequestsState.needsCode);
    expect(state.queue, isEmpty);
  });

  test("EZTiger tells the request list on this PC which address its QR code uses", () async {
    final ips = <String?>[];
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((req) async {
      ips.add(req.uri.queryParameters['ip']);
      req.response.headers.contentType = ContentType.json;
      req.response.write('[]');
      await req.response.close();
    });
    state.requestsLink = 'localhost:${server.port}';
    state.setSongbook(url: 'http://192.168.0.57:8080/');
    await state.checkSongRequests();
    expect(ips.last, '192.168.0.57', reason: "the QR code's address");

    state.setSongbook(url: 'https://example.github.io/songbook/');
    state.pcAddress = '10.0.0.9';
    await state.checkSongRequests();
    expect(ips.last, '10.0.0.9', reason: 'the QR code is a web site: this PC\'s address');
    expect(RequestServer.parse('http://192.168.0.57:8080/dj?key=x')!.onThisDevice, isFalse, reason: 'a tablet sends none');
  });
}
