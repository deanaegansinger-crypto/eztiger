import 'dart:convert';
import 'dart:io';

import 'package:eztiger/player.dart';
import 'package:eztiger/second_screen.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes.dart';

void main() {
  test('the output copy of EZTiger is started with its port', () {
    expect(outputWindowPort(['--output-window=51234']), 51234);
    expect(outputWindowPort(['--something', '--output-window=80']), 80);
    expect(outputWindowPort([]), isNull);
    expect(outputWindowPort(['--output-window=x']), isNull);
  });

  test('the second screen is a program of its own, told the song and the time over a local connection', () async {
    // Real sockets on this PC.
    final saved = HttpOverrides.current;
    HttpOverrides.global = null;
    addTearDown(() => HttpOverrides.global = saved);

    final engine = KaraokeEngine(FakeBackend(), scanEdges: (_) async => null);
    final lines = <Map<String, dynamic>>[];
    Socket? output;
    final second = SecondScreen(() => engine, startOutput: (port) async {
      // A pretend output program: connects back and keeps every message.
      output = await Socket.connect(InternetAddress.loopbackIPv4, port);
      output!.cast<List<int>>().transform(utf8.decoder).transform(const LineSplitter()).listen(
            (l) => lines.add(jsonDecode(l) as Map<String, dynamic>),
          );
      return null;
    });
    addTearDown(second.dispose);

    await second.open();
    expect(second.isOpen, isTrue);
    await Future<void>.delayed(const Duration(milliseconds: 250));
    expect(lines.map((m) => m['m']), containsAllInOrder(['track', 'clock']));
    expect(lines.first['a'], containsPair('cdg', null));

    // Only small messages, a few a second: no pictures.
    lines.clear();
    await Future<void>.delayed(const Duration(milliseconds: 700));
    expect(lines.where((m) => m['m'] == 'clock').length, inInclusiveRange(1, 4));
    expect(lines.every((m) => jsonEncode(m).length < 1000), isTrue);

    // Closed from the main window: it is told to close.
    await second.close();
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(lines.last['m'], 'close');
    expect(second.isOpen, isFalse);

    // Closed by hand on the second screen: the main window notices.
    await second.open();
    expect(second.isOpen, isTrue);
    await output!.close();
    output!.destroy();
    await Future<void>.delayed(const Duration(milliseconds: 300));
    expect(second.isOpen, isFalse);
  });

  test("if the output program never connects, it doesn't stay half-open", () async {
    final engine = KaraokeEngine(FakeBackend(), scanEdges: (_) async => null);
    final second = SecondScreen(() => engine, startOutput: (port) async => throw const ProcessException('eztiger', []));
    addTearDown(second.dispose);
    await second.open();
    expect(second.isOpen, isFalse);
  });
}
