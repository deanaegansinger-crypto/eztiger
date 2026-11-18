/// Reads a song's title and artist from its tags: ID3v2 (2.2, 2.3, 2.4) and
/// ID3v1 in MP3s, and the iTunes-style ©nam / ©ART items in MP4, M4A and
/// MOV files. Pure Dart, reading only the few bytes it needs.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

typedef SongTags = ({String? title, String? artist});

const _none = (title: null, artist: null);

/// The title and artist tags of [path]; a field is null when the tag is
/// missing or blank (the scanner then uses the file name for that field).
SongTags readTags(String path) {
  try {
    final ext = p.extension(path).toLowerCase();
    if (ext == '.mp3' || ext == '.mp2' || ext == '.wav' || ext == '.aiff') return _readId3(path);
    if (const {'.mp4', '.m4a', '.m4v', '.mov', '.3gp'}.contains(ext)) return _readMp4(path);
  } catch (_) {
    // A damaged or locked file: fall back to the file name.
  }
  return _none;
}

String? _clean(String? s) {
  if (s == null) return null;
  final t = s.replaceAll('\u0000', ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
  if (t.isEmpty) return null;
  // Placeholders some rippers write, which say nothing about the song.
  if (RegExp(r'^(track\s*\d*|\d+|unknown( artist| title)?|untitled|<unknown>|title|artist)$', caseSensitive: false).hasMatch(t)) {
    return null;
  }
  return t;
}

// ---------------------------------------------------------------- ID3 ----

SongTags _readId3(String path) {
  final f = File(path).openSync();
  try {
    final len = f.lengthSync();
    String? title, artist;
    final head = f.readSync(10);
    if (head.length == 10 && head[0] == 0x49 && head[1] == 0x44 && head[2] == 0x33) {
      final major = head[3], flags = head[5];
      final size = _synchsafe(head, 6);
      final body = f.readSync(size.clamp(0, 4 * 1024 * 1024));
      final v2 = _id3v2Frames(body, major, flags);
      title = _clean(v2.title);
      artist = _clean(v2.artist);
    }
    if ((title == null || artist == null) && len >= 128) {
      f.setPositionSync(len - 128);
      final t = f.readSync(128);
      if (t[0] == 0x54 && t[1] == 0x41 && t[2] == 0x47) {
        title ??= _clean(latin1.decode(t.sublist(3, 33)));
        artist ??= _clean(latin1.decode(t.sublist(33, 63)));
      }
    }
    return (title: title, artist: artist);
  } finally {
    f.closeSync();
  }
}

int _synchsafe(List<int> b, int o) => (b[o] & 0x7f) << 21 | (b[o + 1] & 0x7f) << 14 | (b[o + 2] & 0x7f) << 7 | (b[o + 3] & 0x7f);
int _be32(List<int> b, int o) => b[o] << 24 | b[o + 1] << 16 | b[o + 2] << 8 | b[o + 3];

SongTags _id3v2Frames(Uint8List body, int major, int flags) {
  var data = body;
  // Whole-tag unsynchronisation (2.2 / 2.3): FF 00 -> FF.
  if (flags & 0x80 != 0 && major < 4) data = _unsync(data);
  var i = 0;
  if (flags & 0x40 != 0 && major >= 3 && data.length >= 4) {
    i = major == 4 ? _synchsafe(data, 0) : _be32(data, 0) + 4;
  }
  String? title, artist;
  final idLen = major == 2 ? 3 : 4, hdr = major == 2 ? 6 : 10;
  while (i + hdr <= data.length) {
    if (data[i] == 0) break; // padding
    final id = ascii.decode(data.sublist(i, i + idLen), allowInvalid: true);
    final size = major == 2
        ? data[i + 3] << 16 | data[i + 4] << 8 | data[i + 5]
        : major == 4
            ? _synchsafe(data, i + 4)
            : _be32(data, i + 4);
    final start = i + hdr, end = start + size;
    if (size <= 0 || end > data.length) break;
    if (id == 'TIT2' || id == 'TT2') title ??= _id3Text(data.sublist(start, end));
    if (id == 'TPE1' || id == 'TP1') artist ??= _id3Text(data.sublist(start, end));
    if (title != null && artist != null) break;
    i = end;
  }
  return (title: title, artist: artist);
}

Uint8List _unsync(Uint8List b) {
  final out = BytesBuilder(copy: false);
  for (var i = 0; i < b.length; i++) {
    out.addByte(b[i]);
    if (b[i] == 0xff && i + 1 < b.length && b[i + 1] == 0) i++;
  }
  return out.takeBytes();
}

String? _id3Text(Uint8List f) {
  if (f.isEmpty) return null;
  final enc = f[0];
  final b = f.sublist(1);
  String s;
  switch (enc) {
    case 1: // UTF-16 with a byte-order mark
      s = _utf16(b, bigEndian: !(b.length >= 2 && b[0] == 0xff && b[1] == 0xfe), skipBom: b.length >= 2 && (b[0] == 0xff || b[0] == 0xfe));
    case 2:
      s = _utf16(b, bigEndian: true, skipBom: false);
    case 3:
      s = utf8.decode(b, allowMalformed: true);
    default:
      s = latin1.decode(b);
  }
  // Several values are separated by NULs: the first is the one.
  final cut = s.indexOf('\u0000');
  return cut >= 0 ? s.substring(0, cut) : s;
}

String _utf16(Uint8List b, {required bool bigEndian, required bool skipBom}) {
  final units = <int>[];
  for (var i = skipBom ? 2 : 0; i + 1 < b.length; i += 2) {
    units.add(bigEndian ? b[i] << 8 | b[i + 1] : b[i + 1] << 8 | b[i]);
  }
  return String.fromCharCodes(units);
}

// ---------------------------------------------------------------- MP4 ----

SongTags _readMp4(String path) {
  final f = File(path).openSync();
  try {
    final len = f.lengthSync();
    // Find the top-level 'moov' box (it can sit after a huge 'mdat').
    var pos = 0;
    while (pos + 8 <= len) {
      f.setPositionSync(pos);
      final h = f.readSync(16);
      if (h.length < 8) break;
      var size = _be32(h, 0);
      final type = ascii.decode(h.sublist(4, 8), allowInvalid: true);
      var hdr = 8;
      if (size == 1 && h.length >= 16) {
        size = ByteData.sublistView(Uint8List.fromList(h), 8, 16).getUint64(0);
        hdr = 16;
      } else if (size == 0) {
        size = len - pos;
      }
      if (size < hdr) break;
      if (type == 'moov') {
        final n = (size - hdr).clamp(0, 48 * 1024 * 1024);
        f.setPositionSync(pos + hdr);
        return _moov(f.readSync(n));
      }
      pos += size;
    }
    return _none;
  } finally {
    f.closeSync();
  }
}

/// The boxes inside [b] from [start] to [end]: (type, body start, body end).
Iterable<(String, int, int)> _boxes(Uint8List b, int start, int end) sync* {
  var i = start;
  while (i + 8 <= end) {
    var size = _be32(b, i);
    final type = latin1.decode(b.sublist(i + 4, i + 8));
    var hdr = 8;
    if (size == 1 && i + 16 <= end) {
      size = ByteData.sublistView(b, i + 8, i + 16).getUint64(0);
      hdr = 16;
    } else if (size == 0) {
      size = end - i;
    }
    if (size < hdr || i + size > end) return;
    yield (type, i + hdr, i + size);
    i += size;
  }
}

SongTags _moov(Uint8List b) {
  String? title, artist;
  void ilst(int s, int e) {
    for (final (type, bs, be) in _boxes(b, s, e)) {
      final isTitle = type == '©nam', isArtist = type == '©ART' || type == 'aART';
      if (!isTitle && !isArtist) continue;
      for (final (dt, ds, de) in _boxes(b, bs, be)) {
        if (dt != 'data' || de - ds < 8) continue;
        final text = utf8.decode(b.sublist(ds + 8, de), allowMalformed: true);
        if (isTitle) title ??= _clean(text);
        if (type == '©ART') artist = _clean(text) ?? artist;
        if (type == 'aART') artist ??= _clean(text);
      }
    }
  }

  void meta(int s, int e) {
    // 'meta' is a full box (4 bytes of version and flags) in MP4 files, and
    // a plain one in some QuickTime files.
    final looksFull = e - s >= 12 && _be32(b, s) == 0;
    for (final (type, bs, be) in _boxes(b, looksFull ? s + 4 : s, e)) {
      if (type == 'ilst') ilst(bs, be);
    }
  }

  for (final (type, s, e) in _boxes(b, 0, b.length)) {
    if (type == 'udta') {
      for (final (t2, s2, e2) in _boxes(b, s, e)) {
        if (t2 == 'meta') meta(s2, e2);
      }
    } else if (type == 'meta') {
      meta(s, e);
    }
  }
  return (title: title, artist: artist);
}
