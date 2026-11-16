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
}
