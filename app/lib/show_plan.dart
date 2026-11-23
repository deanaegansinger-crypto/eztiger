import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive_io.dart';
import 'package:path/path.dart' as p;

/// The show planner (EZTiger Pro on the PC): a singer's evening, planned as
/// a playlist with intervals between the sets, a note on any song, break
/// music for each interval, and a start time, so every song shows when it
/// will start and the plan shows when the show will finish.
///
/// The playlist itself still holds the songs, in order: the plan adds the
/// intervals and notes around them. It travels to the tablet with the
/// playlist ("Send to the tablet").

/// One line of a show: a song, or an interval between two sets.
class ShowItem {
  ShowItem.song(String this.path, {this.note = ''})
      : isBreak = false,
        minutes = 0,
        label = '',
        music = [];

  ShowItem.interval({this.minutes = 20, this.label = 'Interval', List<String>? music, this.note = ''})
      : isBreak = true,
        path = null,
        music = music ?? [];

  factory ShowItem.fromJson(Map<String, dynamic> j) => j['break'] == true
      ? ShowItem.interval(
          minutes: (j['minutes'] as num?)?.toInt() ?? 20,
          label: '${j['label'] ?? 'Interval'}',
          music: [for (final m in (j['music'] as List? ?? const [])) '$m'],
          note: '${j['note'] ?? ''}',
        )
      : ShowItem.song('${j['song'] ?? ''}', note: '${j['note'] ?? ''}');

  /// True for an interval.
  final bool isBreak;

  /// A song's file (null for an interval).
  final String? path;

  /// Anything to remember at this point ("talk to the crowd first").
  String note;

  /// An interval: how long, what it's called, and the music that plays
  /// (MP3s or videos, by their file).
  int minutes;
  String label;
  final List<String> music;

  ShowItem copy() => isBreak
      ? ShowItem.interval(minutes: minutes, label: label, music: [...music], note: note)
      : ShowItem.song(path!, note: note);

  Map<String, Object?> toJson() => isBreak
      ? {
          'break': true,
          'minutes': minutes,
          'label': label,
          if (music.isNotEmpty) 'music': music,
          if (note.isNotEmpty) 'note': note,
        }
      : {'song': path, if (note.isNotEmpty) 'note': note};
}

/// A planned show: its lines in running order and when it starts.
class ShowPlan {
  ShowPlan({this.start, List<ShowItem>? items}) : items = items ?? [];

  factory ShowPlan.fromJson(Map<String, dynamic> j) => ShowPlan(
        start: j['start'] as String?,
        items: [for (final i in (j['items'] as List? ?? const [])) ShowItem.fromJson(i as Map<String, dynamic>)],
      );

  /// The start time as typed ("9:00 pm", "21:00"), or null.
  String? start;
  final List<ShowItem> items;

  /// The songs' files, in running order.
  List<String> get songPaths => [for (final i in items) if (!i.isBreak) i.path!];

  /// Every interval's music, in running order.
  List<String> get musicPaths => [for (final i in items) if (i.isBreak) ...i.music];

  int get songCount => items.where((i) => !i.isBreak).length;
  int get setCount => 1 + items.where((i) => i.isBreak).length;

  /// True when there's more to it than the songs: an interval, a note or a
  /// start time.
  bool get hasExtras => start != null && start!.trim().isNotEmpty || items.any((i) => i.isBreak || i.note.isNotEmpty);

  ShowPlan copy() => ShowPlan(start: start, items: [for (final i in items) i.copy()]);

  Map<String, Object?> toJson() => {
        if (start != null && start!.trim().isNotEmpty) 'start': start,
        'items': [for (final i in items) i.toJson()],
      };

  /// The plan, matched to the playlist's songs as they are now ([paths], in
  /// order). Songs taken off the playlist go, songs added are in, and the
  /// order is the playlist's. Notes stay with their songs, and each
  /// interval stays after the song it followed (or the nearest one before
  /// that's still there).
  ShowPlan matchedTo(List<String> paths) {
    String k(String path) => path.replaceAll('\\', '/').toLowerCase();
    // A song can be in a show twice: each copy is "path#n".
    final keep = <String>{};
    final seen = <String, int>{};
    for (final path in paths) {
      final n = seen[k(path)] = (seen[k(path)] ?? 0) + 1;
      keep.add('${k(path)}#$n');
    }
    final notes = <String, String>{};
    final after = <String?, List<ShowItem>>{}; // song key (null: the top) -> intervals after it
    String? anchor;
    seen.clear();
    for (final i in items) {
      if (i.isBreak) {
        (after[anchor] ??= []).add(i.copy());
        continue;
      }
      final n = seen[k(i.path!)] = (seen[k(i.path!)] ?? 0) + 1;
      final key = '${k(i.path!)}#$n';
      if (keep.contains(key)) {
        anchor = key;
        if (i.note.isNotEmpty) notes[key] = i.note;
      }
    }
    final out = ShowPlan(start: start, items: [...?after[null]]);
    seen.clear();
    for (final path in paths) {
      final n = seen[k(path)] = (seen[k(path)] ?? 0) + 1;
      final key = '${k(path)}#$n';
      out.items.add(ShowItem.song(path, note: notes[key] ?? ''));
      out.items.addAll(after[key] ?? const []);
    }
    return out;
  }

  /// When each line starts, from the show's start (or 0:00 in), given each
  /// song's length ([lengthOf]; null when it isn't known, then [guess] is
  /// used and the line is marked as a guess). An interval lasts its minutes.
  ShowTimes times(Duration? Function(String path) lengthOf, {Duration guess = const Duration(minutes: 3, seconds: 30)}) {
    final starts = <Duration>[], lengths = <Duration>[], guessed = <bool>[];
    var at = Duration.zero;
    for (final i in items) {
      starts.add(at);
      final known = i.isBreak ? Duration(minutes: i.minutes) : lengthOf(i.path!);
      final len = known ?? guess;
      lengths.add(len);
      guessed.add(known == null);
      at += len;
    }
    return ShowTimes(starts: starts, lengths: lengths, guessed: guessed, total: at, startsAt: parseStartTime(start));
  }

  /// Which set each line is in: 1 until the first interval, then 2, and so
  /// on. An interval belongs to the set after it.
  List<int> get sets {
    var set = 1;
    return [
      for (final i in items)
        if (i.isBreak) ++set else set,
    ];
  }
}

/// When a show's lines start, and how long each lasts.
class ShowTimes {
  ShowTimes({required this.starts, required this.lengths, required this.guessed, required this.total, this.startsAt});

  /// Time into the show at which each line starts.
  final List<Duration> starts;
  final List<Duration> lengths;

  /// True where a song's length wasn't known and a guess was used.
  final List<bool> guessed;
  final Duration total;

  /// The show's start, as time of day (from midnight), when one was given.
  final Duration? startsAt;

  int get guesses => guessed.where((g) => g).length;

  /// The time line [i] starts: the clock time ("9:42 pm") when the show has
  /// a start time, otherwise how far in ("0:42").
  String clockAt(int i) => startsAt == null ? showLength(starts[i]) : clockTime(startsAt! + starts[i]);

  /// When the show finishes, as a clock time, or null without a start time.
  String? get finish => startsAt == null ? null : clockTime(startsAt! + total);
}

/// "9pm", "9:15 pm", "21:15", "9.15" → time from midnight; null if it isn't
/// a time.
Duration? parseStartTime(String? s) {
  if (s == null) return null;
  final m = RegExp(r'^\s*(\d{1,2})(?:[:.](\d{2}))?\s*(am|pm|a|p)?\s*$', caseSensitive: false).firstMatch(s);
  if (m == null) return null;
  var h = int.parse(m.group(1)!);
  final min = int.parse(m.group(2) ?? '0');
  final half = m.group(3)?.toLowerCase();
  if (min > 59 || h > 23) return null;
  if (half != null) {
    if (h < 1 || h > 12) return null;
    if (half.startsWith('p') && h != 12) h += 12;
    if (half.startsWith('a') && h == 12) h = 0;
  }
  return Duration(hours: h, minutes: min);
}

/// A time of day as "9:05 pm" (past midnight goes round again).
String clockTime(Duration fromMidnight) {
  final mins = fromMidnight.inMinutes % (24 * 60);
  final h24 = mins ~/ 60, m = mins % 60;
  final h12 = h24 % 12 == 0 ? 12 : h24 % 12;
  return '$h12:${m.toString().padLeft(2, '0')} ${h24 < 12 ? 'am' : 'pm'}';
}

/// A length as "3:05", or "1:02:05" over an hour.
String showLength(Duration d) {
  final h = d.inHours, m = d.inMinutes.remainder(60), s = d.inSeconds.remainder(60);
  final ss = s.toString().padLeft(2, '0');
  return h > 0 ? '$h:${m.toString().padLeft(2, '0')}:$ss' : '$m:$ss';
}

/// A length in words for a total: "1 hr 25 min", "48 min".
String showLengthWords(Duration d) {
  final mins = (d.inSeconds / 60).round();
  final h = mins ~/ 60, m = mins % 60;
  return h == 0 ? '$m min' : (m == 0 ? '$h hr' : '$h hr $m min');
}

// ----------------------------------------------------------- song lengths

/// A song's length, worked out from its files without playing it: a CDG's
/// size (300 packets of 24 bytes a second), an MP3's frame header (and its
/// VBR header when it has one), a WAV's header. Null for what it can't tell
/// (videos, other audio): the planner then guesses, or uses the length
/// heard when the song was previewed or played.
Duration? estimateLength(String path, {String? cdgPath}) {
  try {
    if (cdgPath != null && File(cdgPath).existsSync()) return _cdgLength(File(cdgPath).lengthSync());
    final ext = p.extension(path).toLowerCase();
    if (ext == '.cdg') return _cdgLength(File(path).lengthSync());
    if (ext == '.zip') return _zipCdgLength(path);
    if (ext == '.mp3') {
      // An MP3+G pair: the CDG beside it is exact.
      final beside = [p.setExtension(path, '.cdg'), p.setExtension(path, '.CDG')].where((f) => File(f).existsSync()).firstOrNull;
      return beside != null ? _cdgLength(File(beside).lengthSync()) : mp3Length(path);
    }
    if (ext == '.wav') return wavLength(path);
  } catch (_) {
    // Unreadable: not known.
  }
  return null;
}

Duration? _cdgLength(int bytes) => bytes <= 0 ? null : Duration(milliseconds: bytes * 1000 ~/ (24 * 300));

Duration? _zipCdgLength(String zip) {
  final input = InputFileStream(zip);
  try {
    final archive = ZipDecoder().decodeStream(input);
    final cdg = archive.where((f) => f.isFile && f.name.toLowerCase().endsWith('.cdg')).firstOrNull;
    return cdg == null ? null : _cdgLength(cdg.size);
  } finally {
    input.closeSync();
  }
}

Uint8List _head(String path, int bytes) {
  final f = File(path).openSync();
  try {
    return f.readSync(bytes);
  } finally {
    f.closeSync();
  }
}

const _mp3Rates1 = [0, 32, 40, 48, 56, 64, 80, 96, 112, 128, 160, 192, 224, 256, 320];
const _mp3Rates2 = [0, 8, 16, 24, 32, 40, 48, 56, 64, 80, 96, 112, 128, 144, 160];
const _mp3Samples = {3: [44100, 48000, 32000], 2: [22050, 24000, 16000], 0: [11025, 12000, 8000]};

/// An MP3's length: from its Xing/Info or VBRI header (VBR files), else
/// from the first frame's bit rate and the file size.
Duration? mp3Length(String path) {
  final size = File(path).lengthSync();
  final b = _head(path, 128 * 1024);
  var i = 0;
  // Skip an ID3v2 tag.
  if (b.length > 10 && b[0] == 0x49 && b[1] == 0x44 && b[2] == 0x33) {
    final tag = (b[6] & 0x7f) << 21 | (b[7] & 0x7f) << 14 | (b[8] & 0x7f) << 7 | (b[9] & 0x7f);
    i = 10 + tag + ((b[5] & 0x10) != 0 ? 10 : 0);
  }
  for (; i + 4 < b.length; i++) {
    if (b[i] != 0xff || (b[i + 1] & 0xe0) != 0xe0) continue;
    final version = (b[i + 1] >> 3) & 3, layer = (b[i + 1] >> 1) & 3;
    final rateIndex = b[i + 2] >> 4, srIndex = (b[i + 2] >> 2) & 3;
    if (version == 1 || layer != 1 || rateIndex == 0 || rateIndex == 15 || srIndex == 3) continue;
    final mpeg1 = version == 3;
    final kbps = (mpeg1 ? _mp3Rates1 : _mp3Rates2)[rateIndex];
    final sampleRate = _mp3Samples[version]![srIndex];
    final samplesPerFrame = mpeg1 ? 1152 : 576;
    final mono = (b[i + 3] >> 6) == 3;
    // A VBR header in the first frame gives the frame count.
    final side = mpeg1 ? (mono ? 17 : 32) : (mono ? 9 : 17);
    final x = i + 4 + side;
    int? frames;
    if (x + 12 <= b.length) {
      final tag = String.fromCharCodes(b.sublist(x, x + 4));
      if ((tag == 'Xing' || tag == 'Info') && (b[x + 7] & 1) != 0) {
        frames = b[x + 8] << 24 | b[x + 9] << 16 | b[x + 10] << 8 | b[x + 11];
      }
    }
    final v = i + 4 + 32;
    if (frames == null && v + 18 <= b.length && String.fromCharCodes(b.sublist(v, v + 4)) == 'VBRI') {
      frames = b[v + 14] << 24 | b[v + 15] << 16 | b[v + 16] << 8 | b[v + 17];
    }
    if (frames != null && frames > 0) {
      return Duration(microseconds: frames * samplesPerFrame * 1000000 ~/ sampleRate);
    }
    final audioBytes = size - i - (_hasId3v1(path, size) ? 128 : 0);
    return Duration(milliseconds: audioBytes * 8 ~/ kbps);
  }
  return null;
}

bool _hasId3v1(String path, int size) {
  if (size < 128) return false;
  final f = File(path).openSync();
  try {
    f.setPositionSync(size - 128);
    final t = f.readSync(3);
    return t.length == 3 && t[0] == 0x54 && t[1] == 0x41 && t[2] == 0x47; // "TAG"
  } finally {
    f.closeSync();
  }
}

/// A WAV's length, from its byte rate and the size of its data.
Duration? wavLength(String path) {
  final b = _head(path, 4096);
  if (b.length < 44 || String.fromCharCodes(b.sublist(0, 4)) != 'RIFF') return null;
  final bd = ByteData.sublistView(b);
  int? byteRate;
  var i = 12;
  while (i + 8 <= b.length) {
    final id = String.fromCharCodes(b.sublist(i, i + 4));
    final len = bd.getUint32(i + 4, Endian.little);
    if (id == 'fmt ' && i + 16 <= b.length) byteRate = bd.getUint32(i + 16, Endian.little);
    if (id == 'data') {
      if (byteRate == null || byteRate == 0) return null;
      final data = len == 0 || len == 0xffffffff ? File(path).lengthSync() - i - 8 : len;
      return Duration(milliseconds: data * 1000 ~/ byteRate);
    }
    i += 8 + len + (len & 1);
  }
  return null;
}
