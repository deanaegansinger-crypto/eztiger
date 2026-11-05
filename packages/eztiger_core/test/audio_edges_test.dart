import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:eztiger_core/eztiger_core.dart';
import 'package:test/test.dart';

double secs(Duration d) => d.inMicroseconds / 1e6;

void main() {
  test('finds the tone between two silences in an MP3', () async {
    final e = (await findAudioEdges('test/fixtures/silence_tone_silence.mp3'))!;
    expect(secs(e.start), closeTo(1.5, 0.15));
    expect(secs(e.end), closeTo(3.5, 0.15));
    expect(secs(e.length), closeTo(5.0, 0.15));
  });

  test('reads MPEG-2 stereo frames too', () async {
    final e = (await findAudioEdges('test/fixtures/mpeg2_stereo.mp3'))!;
    expect(secs(e.start), closeTo(1.0, 0.15));
    expect(secs(e.end), closeTo(2.0, 0.15));
  });

  test('finds the sound in a WAV and passes over a click', () {
    const rate = 22050;
    final samples = Int16List(rate * 4);
    samples[10] = 30000; // a click at the very start
    for (var k = rate; k < rate * 3; k++) {
      samples[k] = (8000 * math.sin(k * 2 * math.pi * 440 / rate)).round();
    }
    final e = wavEdges(_wav(samples, rate))!;
    expect(secs(e.start), closeTo(1.0, 0.06));
    expect(secs(e.end), closeTo(3.0, 0.06));
  });

  test('silence only, or a file it cannot read, gives null', () async {
    expect(wavEdges(_wav(Int16List(22050), 22050)), isNull);
    expect(await findAudioEdges('nope.mp4'), isNull);
    expect(await findAudioEdges('${Directory.systemTemp.path}/missing.mp3'), isNull);
  });
}

Uint8List _wav(Int16List samples, int rate) {
  final data = samples.buffer.asUint8List();
  final b = ByteData(44 + data.length);
  void s(int at, String x) {
    for (var k = 0; k < 4; k++) {
      b.setUint8(at + k, x.codeUnitAt(k));
    }
  }

  s(0, 'RIFF');
  b.setUint32(4, 36 + data.length, Endian.little);
  s(8, 'WAVE');
  s(12, 'fmt ');
  b.setUint32(16, 16, Endian.little);
  b.setUint16(20, 1, Endian.little);
  b.setUint16(22, 1, Endian.little);
  b.setUint32(24, rate, Endian.little);
  b.setUint32(28, rate * 2, Endian.little);
  b.setUint16(32, 2, Endian.little);
  b.setUint16(34, 16, Endian.little);
  s(36, 'data');
  b.setUint32(40, data.length, Endian.little);
  final out = b.buffer.asUint8List();
  out.setRange(44, out.length, data);
  return out;
}
