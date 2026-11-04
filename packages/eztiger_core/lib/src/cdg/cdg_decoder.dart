/// CD+G (karaoke graphics) decoder.
///
/// A `.cdg` file is a stream of 24-byte packets played at 300 packets per
/// second alongside the matching `.mp3`. Each packet draws on a 300x216
/// screen of 16 palette colours: filling the screen or border, drawing a
/// 6x12 tile (normally or XORed, which is how the lyric "wipe" works),
/// loading the palette, or scrolling.
///
/// Pure Dart and UI-free: the app calls [seek] with the audio position on
/// every frame and paints [rgba] when [changed] is true.
library;

import 'dart:typed_data';

class CdgDecoder {
  CdgDecoder(Uint8List bytes) : _data = bytes {
    reset();
  }

  static const int width = 300;
  static const int height = 216;
  static const int packetSize = 24;
  static const int packetsPerSecond = 300;
  static const int tileWidth = 6;
  static const int tileHeight = 12;

  final Uint8List _data;
  final Uint8List _pixels = Uint8List(width * height); // palette indices
  final Uint32List _palette = Uint32List(16); // 0xAARRGGBB
  final Uint8List _rgba = Uint8List(width * height * 4);
  int _packet = 0;
  int _borderColor = 0;
  int _hOffset = 0;
  int _vOffset = 0;
  int _transparent = -1;
  bool _dirty = true;

  int get packetCount => _data.length ~/ packetSize;
  Duration get duration => Duration(milliseconds: packetCount * 1000 ~/ packetsPerSecond);

  /// Packets decoded so far.
  int get position => _packet;

  /// True if the picture changed since [rgba] was last read.
  bool get changed => _dirty;

  /// Fine-scroll offsets in pixels (0-5 across, 0-11 down). Players shift
  /// the visible window by these.
  int get hOffset => _hOffset;
  int get vOffset => _vOffset;

  /// Palette index that should show the video underneath, or -1.
  int get transparentColor => _transparent;

  void reset() {
    _packet = 0;
    _pixels.fillRange(0, _pixels.length, 0);
    _palette.fillRange(0, 16, 0xFF000000);
    _borderColor = 0;
    _hOffset = 0;
    _vOffset = 0;
    _transparent = -1;
    _dirty = true;
  }

  /// Brings the picture to [time] in the song. Going forwards decodes only
  /// the new packets; going backwards replays from the start (a whole song
  /// decodes in a few milliseconds).
  void seek(Duration time) {
    var target = time.inMicroseconds * packetsPerSecond ~/ Duration.microsecondsPerSecond;
    if (target > packetCount) target = packetCount;
    if (target < _packet) reset();
    while (_packet < target) {
      _decode(_packet * packetSize);
      _packet++;
    }
  }

  /// Palette index at (x, y), for tests.
  int pixel(int x, int y) => _pixels[y * width + x];

  /// The screen as RGBA bytes, 300x216, top-left first.
  Uint8List rgba() {
    if (_dirty) {
      for (var i = 0; i < _pixels.length; i++) {
        final idx = _pixels[i];
        final c = _palette[idx];
        final o = i * 4;
        _rgba[o] = (c >> 16) & 0xFF;
        _rgba[o + 1] = (c >> 8) & 0xFF;
        _rgba[o + 2] = c & 0xFF;
        _rgba[o + 3] = idx == _transparent ? 0 : 0xFF;
      }
      _dirty = false;
    }
    return _rgba;
  }

  // ------------------------------------------------------------ decoding

  void _decode(int o) {
    if ((_data[o] & 0x3F) != 0x09) return; // not a CD+G graphics packet
    final instruction = _data[o + 1] & 0x3F;
    final d = o + 4; // 16 data bytes
    switch (instruction) {
      case 1:
        _memoryPreset(d);
      case 2:
        _borderPreset(d);
      case 6:
        _tileBlock(d, xor: false);
      case 20:
        _scroll(d, copy: false);
      case 24:
        _scroll(d, copy: true);
      case 28:
        _transparent = _data[d] & 0x0F;
        _dirty = true;
      case 30:
        _loadPalette(d, 0);
      case 31:
        _loadPalette(d, 8);
      case 38:
        _tileBlock(d, xor: true);
    }
  }

  void _memoryPreset(int d) {
    _pixels.fillRange(0, _pixels.length, _data[d] & 0x0F);
    _dirty = true;
  }

  void _borderPreset(int d) {
    final c = _data[d] & 0x0F;
    _borderColor = c;
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        if (x < tileWidth || x >= width - tileWidth || y < tileHeight || y >= height - tileHeight) {
          _pixels[y * width + x] = c;
        }
      }
    }
    _dirty = true;
  }

  void _tileBlock(int d, {required bool xor}) {
    final color0 = _data[d] & 0x0F;
    final color1 = _data[d + 1] & 0x0F;
    final row = _data[d + 2] & 0x1F;
    final col = _data[d + 3] & 0x3F;
    final x0 = col * tileWidth;
    final y0 = row * tileHeight;
    if (x0 + tileWidth > width || y0 + tileHeight > height) return;
    for (var y = 0; y < tileHeight; y++) {
      final bits = _data[d + 4 + y] & 0x3F;
      final base = (y0 + y) * width + x0;
      for (var x = 0; x < tileWidth; x++) {
        final on = (bits >> (5 - x)) & 1 == 1;
        final c = on ? color1 : color0;
        _pixels[base + x] = xor ? (_pixels[base + x] ^ c) : c;
      }
    }
    _dirty = true;
  }

  void _loadPalette(int d, int first) {
    for (var i = 0; i < 8; i++) {
      final hi = _data[d + i * 2] & 0x3F;
      final lo = _data[d + i * 2 + 1] & 0x3F;
      final r = (hi >> 2) & 0x0F;
      final g = ((hi & 0x03) << 2) | ((lo >> 4) & 0x03);
      final b = lo & 0x0F;
      _palette[first + i] = 0xFF000000 | (r * 17) << 16 | (g * 17) << 8 | (b * 17);
    }
    _dirty = true;
  }

  void _scroll(int d, {required bool copy}) {
    final color = _data[d] & 0x0F;
    final h = _data[d + 1] & 0x3F;
    final v = _data[d + 2] & 0x3F;
    final hCmd = (h & 0x30) >> 4;
    final vCmd = (v & 0x30) >> 4;
    _hOffset = h & 0x07;
    _vOffset = v & 0x0F;
    final dx = hCmd == 1 ? tileWidth : (hCmd == 2 ? -tileWidth : 0);
    final dy = vCmd == 1 ? tileHeight : (vCmd == 2 ? -tileHeight : 0);
    if (dx != 0 || dy != 0) {
      final old = Uint8List.fromList(_pixels);
      for (var y = 0; y < height; y++) {
        for (var x = 0; x < width; x++) {
          var sx = x - dx, sy = y - dy;
          int value;
          if (sx >= 0 && sx < width && sy >= 0 && sy < height) {
            value = old[sy * width + sx];
          } else if (copy) {
            sx %= width;
            sy %= height;
            value = old[sy * width + sx];
          } else {
            value = color;
          }
          _pixels[y * width + x] = value;
        }
      }
    }
    _dirty = true;
  }

  /// Border colour last set by a border-preset packet.
  int get borderColor => _borderColor;
}
