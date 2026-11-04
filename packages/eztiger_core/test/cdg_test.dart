import 'dart:typed_data';

import 'package:eztiger_core/eztiger_core.dart';
import 'package:test/test.dart';

/// One CD+G packet: command 0x09, [instruction], 16 data bytes.
List<int> packet(int instruction, List<int> data) =>
    [0x09, instruction, 0, 0, ...data, ...List.filled(16 - data.length, 0), 0, 0, 0, 0];

void main() {
  // Palette: colour 1 = pure red (r=15), colour 2 = pure blue (b=15).
  final palette = packet(30, [0, 0, 0x3C, 0x00, 0x00, 0x0F]);
  final clearTo0 = packet(1, [0]);
  // Tile at row 1, col 2: top row all on (colour 1), rest off (colour 2).
  final tile = packet(6, [2, 1, 1, 2, 0x3F, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]);
  final xorTile = packet(38, [0, 3, 1, 2, 0x3F, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]);

  CdgDecoder build(List<List<int>> packets) =>
      CdgDecoder(Uint8List.fromList(packets.expand((p) => p).toList()));
  Duration at(int packets) => Duration(microseconds: packets * 1000000 ~/ 300 + 1);

  test('loads the palette and draws a tile', () {
    final d = build([palette, clearTo0, tile]);
    d.seek(at(3));
    expect(d.pixel(12, 12), 1); // tile top row, colour 1
    expect(d.pixel(12, 13), 2); // rest of tile, colour 2
    expect(d.pixel(0, 0), 0);
    final rgba = d.rgba();
    final o = (12 * CdgDecoder.width + 12) * 4;
    expect(rgba.sublist(o, o + 4), [255, 0, 0, 255]);
  });

  test('XOR tiles change colours in place (the lyric wipe)', () {
    final d = build([palette, clearTo0, tile, xorTile]);
    d.seek(at(4));
    expect(d.pixel(12, 12), 1 ^ 3);
    expect(d.pixel(12, 13), 2);
  });

  test('only decodes what time has reached, and can go backwards', () {
    final d = build([palette, clearTo0, tile]);
    d.seek(at(2));
    expect(d.pixel(12, 12), 0);
    d.seek(at(3));
    expect(d.pixel(12, 12), 1);
    d.seek(Duration.zero);
    expect(d.pixel(12, 12), 0);
    expect(d.position, 0);
  });

  test('border preset and transparent colour', () {
    final d = build([
      packet(2, [5]),
      packet(28, [5])
    ]);
    d.seek(at(2));
    expect(d.pixel(0, 0), 5);
    expect(d.pixel(150, 100), 0);
    expect(d.transparentColor, 5);
    expect(d.rgba()[3], 0); // border is see-through
  });

  test('duration follows the packet count', () {
    final d = build(List.generate(600, (_) => clearTo0));
    expect(d.duration, const Duration(seconds: 2));
  });
}
