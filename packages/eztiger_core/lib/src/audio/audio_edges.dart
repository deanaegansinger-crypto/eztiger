import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

/// Where the music starts and ends in a file, past the silence that karaoke
/// tracks (CDG ones especially) often have at both ends.
class AudioEdges {
  const AudioEdges(this.start, this.end, this.length);

  /// First sound.
  final Duration start;

  /// Last sound.
  final Duration end;

  /// The whole file.
  final Duration length;

  @override
  String toString() => 'AudioEdges($start .. $end of $length)';
}

/// Finds the [AudioEdges] of an MP3 or WAV file without decoding it fully,
/// or returns null for other files or when it can't tell.
///
/// Sound has to last [minSound] to count, so a click at the very start (common
/// in CDG rips) is passed over.
Future<AudioEdges?> findAudioEdges(String path, {Duration minSound = const Duration(milliseconds: 200)}) async {
  try {
    final ext = path.toLowerCase().split('.').last;
    if (ext != 'mp3' && ext != 'wav') return null;
    final bytes = await File(path).readAsBytes();
    return ext == 'mp3' ? mp3Edges(bytes, minSound: minSound) : wavEdges(bytes, minSound: minSound);
  } catch (_) {
    return null;
  }
}

// ------------------------------------------------------------------- MP3

const _bitrates1 = [0, 32, 40, 48, 56, 64, 80, 96, 112, 128, 160, 192, 224, 256, 320];
const _bitrates2 = [0, 8, 16, 24, 32, 40, 48, 56, 64, 80, 96, 112, 128, 144, 160];
const _rates = {
  3: [44100, 48000, 32000],
  2: [22050, 24000, 16000],
  0: [11025, 12000, 8000],
};

/// How loud a frame must be to count as sound, by its MP3 "global gain".
/// Checked against ffmpeg on real CDG tracks: silence and the hiss in
/// fade-outs sit below it, music above it.
const int mp3SoundGain = 140;

/// Reads each MP3 frame's side information (no audio decoding). A frame
/// counts as sound when one of its granules carries coded audio at a gain of
/// at least [mp3SoundGain].
AudioEdges? mp3Edges(Uint8List b, {Duration minSound = const Duration(milliseconds: 200)}) {
  var i = 0;
  if (b.length > 10 && b[0] == 0x49 && b[1] == 0x44 && b[2] == 0x33) {
    i = 10 + ((b[6] & 0x7f) << 21 | (b[7] & 0x7f) << 14 | (b[8] & 0x7f) << 7 | (b[9] & 0x7f));
  }
  final times = <double>[];
  final loud = <bool>[];
  var t = 0.0;
  while (i + 4 < b.length) {
    if (b[i] != 0xff || (b[i + 1] & 0xe0) != 0xe0) {
      i++;
      continue;
    }
    final ver = (b[i + 1] >> 3) & 3, layer = (b[i + 1] >> 1) & 3, crc = (b[i + 1] & 1) == 0;
    final bri = b[i + 2] >> 4, sri = (b[i + 2] >> 2) & 3, pad = (b[i + 2] >> 1) & 1, mode = b[i + 3] >> 6;
    if (ver == 1 || layer != 1 || bri == 0 || bri == 15 || sri == 3) {
      i++;
      continue;
    }
    final mpeg1 = ver == 3;
    final rate = _rates[ver]![sri];
    final bitrate = (mpeg1 ? _bitrates1 : _bitrates2)[bri] * 1000;
    final len = (mpeg1 ? 144 : 72) * bitrate ~/ rate + pad;
    if (i + len > b.length) break;
    final channels = mode == 3 ? 1 : 2;
    final bits = _Bits(b, i + 4 + (crc ? 2 : 0));
    if (mpeg1) {
      bits.skip(9 + (channels == 1 ? 5 : 3) + 4 * channels);
    } else {
      bits.skip(8 + (channels == 1 ? 1 : 2));
    }
    var gain = 0;
    for (var g = 0; g < (mpeg1 ? 2 : 1); g++) {
      for (var c = 0; c < channels; c++) {
        bits.skip(12); // part2_3_length
        final bigValues = bits.read(9);
        final globalGain = bits.read(8);
        bits.skip((mpeg1 ? 4 : 9) + 1 + 22 + (mpeg1 ? 3 : 2));
        if (bigValues > 0) gain = math.max(gain, globalGain);
      }
    }
    times.add(t);
    loud.add(gain >= mp3SoundGain);
    t += (mpeg1 ? 1152 : 576) / rate;
    i += len;
  }
  if (times.isEmpty) return null;
  final frameTime = t / times.length;
  return _edges(times, loud, t, frameTime, minSound);
}

class _Bits {
  _Bits(this.b, int byte) : p = byte * 8;
  final Uint8List b;
  int p;

  int read(int n) {
    var v = 0;
    for (var k = 0; k < n; k++) {
      final byte = p >> 3;
      v = (v << 1) | (byte < b.length ? (b[byte] >> (7 - (p & 7))) & 1 : 0);
      p++;
    }
    return v;
  }

  void skip(int n) => p += n;
}

// ------------------------------------------------------------------- WAV

/// Sound is a 50 ms window louder than -45 dBFS.
AudioEdges? wavEdges(Uint8List b, {Duration minSound = const Duration(milliseconds: 200)}) {
  final d = ByteData.sublistView(b);
  if (b.length < 44 || String.fromCharCodes(b.sublist(0, 4)) != 'RIFF') return null;
  var i = 12;
  int? channels, rate, bitsPer, dataStart, dataLen;
  while (i + 8 <= b.length) {
    final id = String.fromCharCodes(b.sublist(i, i + 4));
    final size = d.getUint32(i + 4, Endian.little);
    if (id == 'fmt ') {
      if (d.getUint16(i + 8, Endian.little) != 1 && d.getUint16(i + 8, Endian.little) != 0xfffe) return null;
      channels = d.getUint16(i + 10, Endian.little);
      rate = d.getUint32(i + 12, Endian.little);
      bitsPer = d.getUint16(i + 22, Endian.little);
    } else if (id == 'data') {
      dataStart = i + 8;
      dataLen = math.min(size, b.length - dataStart);
      break;
    }
    i += 8 + size + (size & 1);
  }
  if (channels == null || rate == null || dataStart == null || dataLen == null) return null;
  if (bitsPer != 16 && bitsPer != 24) return null;
  final bytesPer = bitsPer! ~/ 8, frameBytes = bytesPer * channels;
  final frames = dataLen ~/ frameBytes;
  final window = rate ~/ 20; // 50 ms
  final threshold = math.pow(10, -45 / 20) * math.pow(2, bitsPer - 1);
  final times = <double>[];
  final loud = <bool>[];
  for (var w = 0; w + window <= frames; w += window) {
    var sum = 0.0;
    for (var f = w; f < w + window; f += 4) {
      final at = dataStart + f * frameBytes; // first channel is enough
      final v = bitsPer == 16
          ? d.getInt16(at, Endian.little)
          : (d.getUint8(at) | d.getUint8(at + 1) << 8 | d.getInt8(at + 2) << 16);
      sum += v * v.toDouble();
    }
    times.add(w / rate);
    loud.add(math.sqrt(sum / (window / 4)) > threshold);
  }
  if (times.isEmpty) return null;
  return _edges(times, loud, frames / rate, window / rate, minSound);
}

// ---------------------------------------------------------------- shared

AudioEdges? _edges(List<double> times, List<bool> loud, double length, double step, Duration minSound) {
  final need = math.max(1, (minSound.inMicroseconds / 1e6 / step).ceil());
  int? first, last;
  var run = 0;
  for (var k = 0; k < loud.length; k++) {
    run = loud[k] ? run + 1 : 0;
    if (run == need) {
      first = k - need + 1;
      break;
    }
  }
  if (first == null) return null;
  run = 0;
  for (var k = loud.length - 1; k >= 0; k--) {
    run = loud[k] ? run + 1 : 0;
    if (run == need) {
      last = k + need - 1;
      break;
    }
  }
  Duration at(double s) => Duration(microseconds: (s * 1e6).round());
  return AudioEdges(at(times[first]), at(times[last!] + step), at(length));
}
