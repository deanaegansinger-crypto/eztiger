import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:eztiger_core/eztiger_core.dart';
import 'package:test/test.dart';

const _rate = 11025;

/// [seconds] of a I-IV-V-I chord loop in [root] major (or i-iv-V-i minor),
/// a bass note under each chord, with a click on every beat at [bpm].
Int16List _song({required int root, bool minor = false, required double bpm, int seconds = 40}) {
  final out = Float64List(_rate * seconds);
  final beat = 60 / bpm;
  double freq(int midi) => 440 * math.pow(2, (midi - 69) / 12).toDouble();
  final third = minor ? 3 : 4;
  final chords = [
    [0, third, 7],
    [5, 5 + (minor ? 3 : 4), 12],
    [7, 11, 14],
    [0, third, 7],
  ];
  for (var i = 0; i < out.length; i++) {
    final t = i / _rate;
    final bar = (t / (beat * 4)).floor();
    final chord = chords[bar % 4];
    var v = 0.0;
    for (final n in chord) {
      v += 0.12 * math.sin(2 * math.pi * freq(60 + root + n) * t);
    }
    v += 0.2 * math.sin(2 * math.pi * freq(36 + root + chord[0]) * t);
    // A short noisy click at the start of each beat.
    final inBeat = t % beat;
    if (inBeat < 0.03) v += 0.5 * (1 - inBeat / 0.03) * math.sin(2 * math.pi * 1800 * t + i % 7);
    out[i] = v;
  }
  return Int16List.fromList([for (final v in out) (v.clamp(-1.0, 1.0) * 20000).round()]);
}

void main() {
  group('key names', () {
    test('majors and minors', () {
      expect(keyName(0), 'C');
      expect(keyName(1), 'C#');
      expect(keyName(10), 'Bb');
      expect(keyName(9, minor: true), 'Am');
      expect(keyName(8, minor: true), 'G#m');
    });

    test('a pitch change moves the key', () {
      const a = TrackAnalysis(pitchClass: 11, minor: false, bpm: 120);
      expect(a.keyShifted(2), 'C#');
      expect(a.keyShifted(-3), 'Ab');
    });

    test('names read back', () {
      for (var pc = 0; pc < 12; pc++) {
        for (final minor in [false, true]) {
          expect(parseKeyName(keyName(pc, minor: minor)), (pc, minor));
        }
      }
      expect(parseKeyName('H'), isNull);
      expect(parseKeyName(null), isNull);
    });
  });

  group('analysePcm', () {
    test('finds the key and tempo of a chord loop', () {
      final r = analysePcm(_song(root: 2, bpm: 120), _rate)!; // D major
      expect(r.key, 'D');
      expect(r.bpm, closeTo(120, 2));
    });

    test('a minor key', () {
      final r = analysePcm(_song(root: 9, minor: true, bpm: 100), _rate)!; // A minor
      expect(r.key, 'Am');
      expect(r.bpm, closeTo(100, 2));
    });

    test('another key and a faster tempo', () {
      final r = analysePcm(_song(root: 10, bpm: 150), _rate)!; // Bb major
      expect(r.key, 'Bb');
      expect(r.bpm, closeTo(150, 3));
    });

    test('too short or silent gives nothing', () {
      expect(analysePcm(Int16List(_rate * 5), _rate), isNull);
      expect(analysePcm(Int16List(_rate * 30), _rate), isNull);
    });
  });

  // Needs a libmpv on the machine (the app ships one; CI may not have it).
  final libmpv = Platform.isLinux && File('/usr/lib/x86_64-linux-gnu/libmpv.so.2').existsSync() ? 'libmpv.so.2' : null;
  test('decodes an MP3 through libmpv', () {
    final pcm =
        decodeWithMpv('test/fixtures/silence_tone_silence.mp3', tempDir: Directory.systemTemp.path, libmpvPath: libmpv);
    expect(pcm, isNotNull);
    expect(pcm!.length, greaterThan(_rate));
  }, skip: libmpv == null ? 'no libmpv here' : false);
}
