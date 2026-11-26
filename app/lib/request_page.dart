import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

/// The song-request page singers open on their phones, built from the
/// host's own library (the same page as the request list's
/// request-template.html, filled in here instead of by a script).
///
/// Each song shows once, with a "version" for each collection it is in:
/// the top folder under the library folder ("Sunfly", "Zoom"…).

/// The app's skins, as the page's colours: bg, panel, raised, line, text,
/// dim, accent, highlight, on-accent.
const _skins = <String, List<String>>{
  'classic': ['#14151C', '#1C1E28', '#23252F', '#2F3140', '#E9E8E2', '#8B8D9A', '#E8B34A', '#3DDBD6', '#1A1508'],
  'classic-light': ['#F2EDE1', '#FFFFFF', '#E9E2D0', '#DDD3BA', '#201D16', '#7A7364', '#E8B34A', '#3DDBD6', '#1A1508'],
  'reactor': ['#020604', '#04110A', '#06180E', '#1F6B35', '#B8FFC9', '#4FA066', '#39FF6A', '#A8FF3E', '#011006'],
  'foundry': ['#1B1D1F', '#2B2E31', '#202325', '#0F1011', '#D4D7D2', '#8A9094', '#F2A531', '#7EE05A', '#1B1D1F'],
  'nightshade': ['#05070F', '#0A0F20', '#0D1430', '#1D2A55', '#B9C7F0', '#6273A0', '#8FB4FF', '#4FD3FF', '#050A1C'],
  'silver': ['#B9BDC3', '#D5D8DC', '#ECEEF0', '#9AA0A8', '#1D2127', '#545A63', '#1A5FC8', '#1A5FC8', '#FFFFFF'],
  'nightdrive': ['#030406', '#0A0C10', '#111419', '#1F2A3A', '#DBE6F5', '#6A7B92', '#2F8BFF', '#38E1FF', '#FFFFFF'],
};

/// Well-known karaoke brands, from a collection's folder name.
final _brands = <RegExp, String>{
  RegExp('Sound Choice', caseSensitive: false): 'Sound Choice',
  RegExp('^Sunfly', caseSensitive: false): 'Sunfly',
  RegExp('^Zoom', caseSensitive: false): 'Zoom',
  RegExp('Music Maestro|^MMPRO', caseSensitive: false): 'Music Maestro',
  RegExp('Legend', caseSensitive: false): 'Legend',
  RegExp('Pocket Songs', caseSensitive: false): 'Pocket Songs',
  RegExp('Pioneer', caseSensitive: false): 'Pioneer',
  RegExp('Mr Entertainer|^MRE|^MRH', caseSensitive: false): 'Mr Entertainer',
  RegExp('^Easy |^EK|^EZ|ESSENTIAL EXTREME', caseSensitive: false): 'Easy Karaoke',
  RegExp('MagicTracks', caseSensitive: false): 'Magic Tracks',
};

String? _knownBrand(String folder) {
  for (final e in _brands.entries) {
    if (e.key.hasMatch(folder)) return e.value;
  }
  return null;
}

/// What a song in a working folder whose name starts with "_" (such as
/// _incoming) shows as, when no known brand's folder sits inside it.
const otherBrand = 'Other';

/// The version name for a song in [folder]: its collection, the top folder
/// under the library folder that holds it. A top folder starting with "_"
/// (_incoming, _new…) is a working folder, not a make of disc: a known
/// brand's folder inside it names the version, or else it shows as Other.
String brandOf(String folder, List<String> roots) {
  final root = roots.where((r) => p.equals(r, folder) || p.isWithin(r, folder)).fold<String?>(
        null,
        (best, r) => best == null || r.length > best.length ? r : best,
      );
  final rel = root == null ? '' : p.relative(folder, from: root);
  final top = rel.isEmpty || rel == '.' ? p.basename(root ?? folder) : p.split(rel).first;
  if (top.startsWith('_')) {
    for (final part in p.split(rel).skip(1)) {
      final b = _knownBrand(part);
      if (b != null) return b;
    }
    return otherBrand;
  }
  final known = _knownBrand(top);
  if (known != null) return known;
  final name = top.replaceAll(RegExp(r'\s*\([^)]*\)\s*'), ' ').trim();
  return name.isEmpty ? 'Karaoke' : name;
}

String _norm(String s) =>
    s.toLowerCase().replaceAll('&', ' and ').replaceAll(RegExp('[^a-z0-9 ]+'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();

/// A JSON string that is safe inside a <script>.
String _j(String s) => jsonEncode(s.replaceAll(RegExp(r'[\x00-\x1f]'), ' ')).replaceAll('<', r'<');

List<int> _rgb(String hex) {
  final h = hex.replaceFirst('#', '');
  return [for (var i = 0; i < 6; i += 2) int.parse(h.substring(i, i + 2), radix: 16)];
}

String _hex(List<num> c) => '#${c.map((v) => v.round().clamp(0, 255).toRadixString(16).padLeft(2, '0')).join()}';

/// Fills [template] (request-template.html) with the songs, the show
/// [name], the logo (a PNG, base64) and the colours of [skin].
({String html, int count}) requestPageHtml({
  required String template,
  required String name,
  required String logoBase64,
  required String skin,
  bool lightScreen = false,
  required List<({String title, String artist, String brand, String code})> songs,
  // Venue branding: the venue's name is [name] and its logo [logoBase64] (of [logoType]), with its tagline under the name.
  bool venue = false,
  String logoType = 'image/png',
  String tagline = '',
}) {
  if (venue) {
    template = template
        .replaceAll('data:image/png;base64,{{LOGO}}', 'data:$logoType;base64,{{LOGO}}')
        .replaceAll('<h1>{{NAME}}</h1>',
            '<h1>{{NAME}}</h1>${tagline.isEmpty ? '' : '\n    <div class="tag venue-tag">${const HtmlEscape().convert(tagline)}</div>'}')
        .replaceAll('Powered by EZTiger<', 'Powered by EZTiger Entertainment<');
  }
  // Brands biggest first, so the version buttons come in the same order.
  final counts = <String, int>{};
  for (final s in songs) {
    counts[s.brand] = (counts[s.brand] ?? 0) + 1;
  }
  final brandList = counts.keys.toList()..sort((a, b) => counts[b]!.compareTo(counts[a]!));
  final brandNo = {for (var i = 0; i < brandList.length; i++) brandList[i]: i};

  final sorted = [...songs]..sort((a, b) {
      final c = a.title.toLowerCase().compareTo(b.title.toLowerCase());
      return c != 0 ? c : a.artist.toLowerCase().compareTo(b.artist.toLowerCase());
    });
  final unique = <String, ({String title, String artist, List<String> discs})>{};
  for (final s in sorted) {
    // "The Beatles" and "Beatles" are one artist (as in the library's search).
    final key = '${_norm(s.title)}|${_norm(s.artist).replaceFirst(RegExp(r'^the (?=.)'), '')}';
    final disc = '${brandNo[s.brand]}~${s.code}';
    final u = unique[key];
    if (u == null) {
      unique[key] = (title: s.title, artist: s.artist, discs: [disc]);
    } else if (!u.discs.contains(disc)) {
      u.discs.add(disc);
    }
  }
  final songsJs =
      '[${unique.values.map((u) => '[${_j(u.title)},${_j(u.artist)},${_j(u.discs.join('|'))}]').join(',\n')}]';

  final id = skin == 'classic' && lightScreen ? 'classic-light' : skin;
  final c = _skins[id] ?? _skins['classic']!;
  final accent = _rgb(c[6]), highlight = _rgb(c[7]);
  final light = (0.299 * highlight[0] + 0.587 * highlight[1] + 0.114 * highlight[2]) / 255;
  final theme = {
    '{{BG}}': c[0],
    '{{PANEL}}': c[1],
    '{{RAISED}}': c[2],
    '{{LINE}}': c[3],
    '{{TEXT}}': c[4],
    '{{DIM}}': c[5],
    '{{ACCENT}}': c[6],
    '{{HIGHLIGHT}}': c[7],
    '{{BUTTON}}': c[6],
    '{{BUTTON_TOP}}': _hex([for (var i = 0; i < 3; i++) accent[i] + (255 - accent[i]) * 0.25]),
    '{{ON_ACCENT}}': c[8],
    '{{ON_HIGHLIGHT}}': light > 0.55 ? '#111111' : '#ffffff',
    '{{ON_BUTTON}}': c[8],
  };
  var html = template;
  theme.forEach((k, v) => html = html.replaceAll(k, v));
  final count = unique.length.toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',');
  html = html
      .replaceAll('{{NAME}}', const HtmlEscape().convert(name))
      .replaceAll('{{LOGO}}', logoBase64)
      .replaceAll('{{COUNT}}', count)
      .replaceAll('{{SCRIPT_URL}}', '')
      .replaceAll('{{BRANDS}}', '[${brandList.map(_j).join(',')}]')
      .replaceAll('{{SONGS}}', songsJs);
  return (html: html, count: unique.length);
}

/// Where the request list keeps the page and the list on this PC.
String requestDataDir() {
  final base = Platform.environment['LOCALAPPDATA'] ?? Directory.systemTemp.path;
  return p.join(base, 'EZTiger', 'requests');
}

/// The request list's files, installed beside eztiger.exe.
String requestToolsDir() => p.join(p.dirname(Platform.resolvedExecutable), 'requests');
