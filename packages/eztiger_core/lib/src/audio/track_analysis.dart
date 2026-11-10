import 'dart:math' as math;
import 'dart:typed_data';

/// A song's musical key and tempo, worked out from its audio.
class TrackAnalysis {
  const TrackAnalysis({required this.pitchClass, required this.minor, required this.bpm});

  /// The key's root note: 0 = C, 1 = C#, … 11 = B.
  final int pitchClass;

  /// True for a minor key.
  final bool minor;

  /// Beats per minute.
  final double bpm;

  /// The key as players write it: C, C#, D, Eb … for majors, Am, F#m … for
  /// minors.
  String get key => keyName(pitchClass, minor: minor);

  /// The key after a pitch change of [semitones] (the Pro key control).
  String keyShifted(int semitones) => keyName((pitchClass + semitones) % 12, minor: minor);

  /// The tempo to show: a whole number.
  int get bpmRounded => bpm.round();

  @override
  String toString() => 'TrackAnalysis($key, ${bpm.toStringAsFixed(1)} BPM)';
}

const _majorNames = ['C', 'C#', 'D', 'Eb', 'E', 'F', 'F#', 'G', 'Ab', 'A', 'Bb', 'B'];
const _minorNames = ['Cm', 'C#m', 'Dm', 'Ebm', 'Em', 'Fm', 'F#m', 'Gm', 'G#m', 'Am', 'Bbm', 'Bm'];

/// The name of a key: [pitchClass] 0 = C … 11 = B.
String keyName(int pitchClass, {bool minor = false}) => (minor ? _minorNames : _majorNames)[pitchClass % 12];

/// Reads a key name written by [keyName] back to (pitch class, minor), or
/// null.
(int, bool)? parseKeyName(String? name) {
  if (name == null) return null;
  var i = _majorNames.indexOf(name);
  if (i >= 0) return (i, false);
  i = _minorNames.indexOf(name);
  if (i >= 0) return (i, true);
  return null;
}

/// Works out the key and tempo of mono 16-bit audio at [sampleRate]
/// (11025 Hz is plenty). Returns null when there is too little sound.
///
/// Key: the energy of each note (pitch class), from the spectrum's peaks,
/// summed over the song and matched against the 24 major and minor key
/// profiles. Tempo: the autocorrelation of the onset strength (how sharply
/// the sound gets louder), weighted towards everyday tempos.
TrackAnalysis? analysePcm(Int16List pcm, int sampleRate) {
  if (pcm.length < sampleRate * 10) return null;
  final samples = Float64List(pcm.length);
  for (var i = 0; i < pcm.length; i++) {
    samples[i] = pcm[i] / 32768.0;
  }
  final chroma = _chroma(samples, sampleRate);
  if (chroma == null) return null;
  final (pc, minor) = _bestKey(chroma);
  final bpm = _tempo(samples, sampleRate);
  if (bpm == null) return null;
  return TrackAnalysis(pitchClass: pc, minor: minor, bpm: bpm);
}

// ------------------------------------------------------------------ key

/// Key profiles (Shaath's, as in Essentia), C major and C minor; the others
/// are rotations. Of the usual profiles these matched the known keys of
/// Dean's backing tracks best.
const _majorProfile = [6.6, 2.0, 3.5, 2.3, 4.6, 4.0, 2.5, 5.2, 2.4, 3.7, 2.3, 3.4];
const _minorProfile = [6.5, 2.7, 3.5, 5.4, 2.6, 3.5, 2.5, 5.2, 4.0, 2.7, 4.3, 3.2];

Float64List? _chroma(Float64List x, int rate) {
  const n = 4096;
  final window = _hann(n);
  final re = Float64List(n), im = Float64List(n);
  final mag = Float64List(n ~/ 2);
  // Which note each FFT bin belongs to, from E1 (41 Hz) to B5 (988 Hz):
  // the bass and the chords, where the key shows most.
  final binNote = Int32List(n ~/ 2)..fillRange(0, n ~/ 2, -1);
  for (var k = 1; k < n ~/ 2; k++) {
    final f = k * rate / n;
    final midi = 69 + 12 * math.log(f / 440) / math.ln2;
    final note = midi.round();
    if (note >= 28 && note <= 83 && (midi - note).abs() < 0.4) binNote[k] = note;
  }
  final chroma = Float64List(12);
  var frames = 0;
  final frameChroma = Float64List(12);
  for (var start = 0; start + n <= x.length; start += n) {
    var energy = 0.0;
    for (var i = 0; i < n; i++) {
      final v = x[start + i];
      energy += v * v;
      re[i] = v * window[i];
      im[i] = 0;
    }
    if (energy / n < 1e-6) continue; // silence (below about -60 dBFS)
    _fft(re, im);
    for (var k = 0; k < n ~/ 2; k++) {
      mag[k] = math.sqrt(re[k] * re[k] + im[k] * im[k]);
    }
    frameChroma.fillRange(0, 12, 0);
    var peak = 0.0;
    for (var k = 2; k < n ~/ 2 - 2; k++) {
      final note = binNote[k];
      if (note < 0) continue;
      final m = mag[k];
      // Peaks only: a tone shows as a peak, noise and drums mostly don't.
      if (m <= mag[k - 1] || m < mag[k + 1] || m <= mag[k - 2] || m < mag[k + 2]) continue;
      frameChroma[note % 12] += m;
    }
    for (var c = 0; c < 12; c++) {
      peak = math.max(peak, frameChroma[c]);
    }
    if (peak <= 0) continue;
    for (var c = 0; c < 12; c++) {
      chroma[c] += frameChroma[c] / peak; // every frame counts the same
    }
    frames++;
  }
  return frames < 10 ? null : chroma;
}

(int, bool) _bestKey(Float64List chroma) {
  var best = -2.0;
  var key = (0, false);
  for (final minor in [false, true]) {
    final profile = minor ? _minorProfile : _majorProfile;
    for (var root = 0; root < 12; root++) {
      final r = _correlation(chroma, [for (var i = 0; i < 12; i++) profile[(i - root + 12) % 12]]);
      if (r > best) {
        best = r;
        key = (root, minor);
      }
    }
  }
  return key;
}

double _correlation(List<double> a, List<double> b) {
  final ma = a.reduce((x, y) => x + y) / a.length, mb = b.reduce((x, y) => x + y) / b.length;
  var sab = 0.0, saa = 0.0, sbb = 0.0;
  for (var i = 0; i < a.length; i++) {
    sab += (a[i] - ma) * (b[i] - mb);
    saa += (a[i] - ma) * (a[i] - ma);
    sbb += (b[i] - mb) * (b[i] - mb);
  }
  return saa == 0 || sbb == 0 ? 0 : sab / math.sqrt(saa * sbb);
}

// ---------------------------------------------------------------- tempo

double? _tempo(Float64List x, int rate) {
  const n = 1024, hop = 256;
  final fps = rate / hop;
  final window = _hann(n);
  final re = Float64List(n), im = Float64List(n);
  // Log energy in 24 bands, for the onset strength.
  const bands = 24;
  final bandOf = Int32List(n ~/ 2);
  final lo = math.log(40), hi = math.log(math.min(5000, rate / 2 - 1));
  for (var k = 0; k < n ~/ 2; k++) {
    final f = math.max(k * rate / n, 40);
    bandOf[k] = (((math.log(f) - lo) / (hi - lo)) * bands).floor().clamp(0, bands - 1);
  }
  final frames = (x.length - n) ~/ hop;
  if (frames < fps * 8) return null;
  var prev = Float64List(bands), cur = Float64List(bands);
  final onset = Float64List(frames);
  for (var t = 0; t < frames; t++) {
    final start = t * hop;
    for (var i = 0; i < n; i++) {
      re[i] = x[start + i] * window[i];
      im[i] = 0;
    }
    _fft(re, im);
    cur.fillRange(0, bands, 0);
    for (var k = 1; k < n ~/ 2; k++) {
      cur[bandOf[k]] += re[k] * re[k] + im[k] * im[k];
    }
    var flux = 0.0;
    for (var b = 0; b < bands; b++) {
      cur[b] = math.log(1 + 1000 * cur[b]);
      if (t > 0) flux += math.max(0, cur[b] - prev[b]);
    }
    onset[t] = flux;
    final swap = prev;
    prev = cur;
    cur = swap;
  }
  // Take away the slowly moving level (about 1 s), keep the rises.
  final w = fps.round();
  final env = Float64List(frames);
  var sum = 0.0;
  for (var t = 0; t < frames; t++) {
    sum += onset[t];
    if (t >= w) sum -= onset[t - w];
    final mean = sum / math.min(t + 1, w);
    env[t] = math.max(0, onset[t] - mean);
  }
  // Autocorrelation up to 8 beats at 60 BPM.
  final maxLag = math.min(frames - 1, (fps * 8).ceil() + 2);
  final ac = Float64List(maxLag + 1);
  for (var lag = 1; lag <= maxLag; lag++) {
    var s = 0.0;
    for (var t = lag; t < frames; t++) {
      s += env[t] * env[t - lag];
    }
    ac[lag] = s / (frames - lag);
  }
  double acAt(double lag) {
    final i = lag.floor();
    if (i < 1 || i + 1 > maxLag) return 0;
    final f = lag - i;
    return ac[i] * (1 - f) + ac[i + 1] * f;
  }

  // Score each tempo from 60 to 200 BPM in 0.1 steps by how well the
  // sound repeats after 1, 2, 4 and 8 beats (bars, not triplets, so a
  // shuffle's triplets don't pass for the beat), weighted towards about
  // 130 BPM so the felt tempo wins over half or double time. Tuned on 13 of
  // Dean's backing tracks against Essentia and librosa.
  var bestBpm = 0.0, best = -1.0;
  for (var b = 600; b <= 2000; b++) {
    final bpm = b / 10;
    final lag = fps * 60 / bpm;
    var s = acAt(lag) + acAt(lag * 2) + acAt(lag * 4) + 0.5 * acAt(lag * 8);
    final octaves = math.log(bpm / 130) / math.ln2;
    s *= math.exp(-0.5 * octaves * octaves);
    if (s > best) {
      best = s;
      bestBpm = bpm;
    }
  }
  return best <= 0 ? null : bestBpm;
}

// ------------------------------------------------------------------ fft

Float64List _hann(int n) =>
    Float64List.fromList([for (var i = 0; i < n; i++) 0.5 - 0.5 * math.cos(2 * math.pi * i / (n - 1))]);

/// In-place radix-2 FFT; the length must be a power of two.
void _fft(Float64List re, Float64List im) {
  final n = re.length;
  for (var i = 1, j = 0; i < n; i++) {
    var bit = n >> 1;
    for (; j & bit != 0; bit >>= 1) {
      j ^= bit;
    }
    j ^= bit;
    if (i < j) {
      final tr = re[i], ti = im[i];
      re[i] = re[j];
      im[i] = im[j];
      re[j] = tr;
      im[j] = ti;
    }
  }
  for (var len = 2; len <= n; len <<= 1) {
    final ang = -2 * math.pi / len;
    final wr = math.cos(ang), wi = math.sin(ang);
    for (var i = 0; i < n; i += len) {
      var cr = 1.0, ci = 0.0;
      for (var j = 0; j < len ~/ 2; j++) {
        final a = i + j, b = a + len ~/ 2;
        final xr = re[b] * cr - im[b] * ci, xi = re[b] * ci + im[b] * cr;
        re[b] = re[a] - xr;
        im[b] = im[a] - xi;
        re[a] += xr;
        im[a] += xi;
        final nr = cr * wr - ci * wi;
        ci = cr * wi + ci * wr;
        cr = nr;
      }
    }
  }
}
