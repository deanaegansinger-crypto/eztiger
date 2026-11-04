/// Turns a file name (without extension) into title, artist and version.
///
/// The parser is conservative on purpose: a stripping rule only applies if
/// a separator survives it. That is what stops `Blink 182 - All The Small
/// Things` losing its artist to the catalogue-code rule, and keeps `UB40`,
/// `AC-DC` and `Jay-Z` intact.
///
/// Dean's own performance notes (`down 2`, `Two Semitones Down`, `in G`,
/// `extended`, `with bv`...) are kept as a searchable [ParsedName.version],
/// never thrown away as noise.
library;

import '../text.dart';

class ParsedName {
  ParsedName({
    required this.title,
    this.artist,
    this.version,
    this.catalogueCode,
    this.brand,
    this.orderKnown = false,
    this.artistFromFolder = false,
  });

  String title;
  String? artist;
  final String? version;
  final String? catalogueCode;
  final String? brand;

  /// False when the name split into two parts with no clue which one is the
  /// artist. The scanner then decides using how often each part appears
  /// across the whole library (artists repeat, titles mostly don't).
  bool orderKnown;

  /// The artist came from the folder name, because the file name had none.
  final bool artistFromFolder;

  void swap() {
    final a = artist;
    if (a == null) return;
    artist = title;
    title = a;
  }

  @override
  String toString() => 'ParsedName(title: $title, artist: $artist, version: $version, '
      'code: $catalogueCode, brand: $brand, orderKnown: $orderKnown)';
}

// ---------------------------------------------------------------- patterns

final _emoji =
    RegExp(r'[\u{1F000}-\u{1FFFF}\u{2600}-\u{27BF}\u{2B00}-\u{2BFF}\u{FE0F}\u{200D}]', unicode: true);
final _dashes = RegExp(r'[‐‑‒–—―−]');
final _curlySingle = RegExp(r'[‘’`´]');
final _curlyDouble = RegExp(r'[“”]');

/// Leading track numbers: `02 Thats Amore`, `9.01 My Kind Of Town`,
/// `1.The Lady Is A Tramp`, `09  DEAN MARTIN - SWAY`. Deliberately does not
/// match `9 to 5` or `10cc`.
final _trackNumber = RegExp(
    r'^(?:\d{1,2}\.\d{1,2}\s+|\d{1,2}\.\s*(?=\D)|0\d\s+|\d{1,2}\s{2,}|\d{1,2}\s*-\s+|\d{1,2}-(?=[A-Za-z(]))');

/// Catalogue codes: ZM6S01-02, SC8125-04, SF126-06, PX-006-07, KV-27296,
/// ZMG77 15, STTW1263-4-03, ZOOMPA063-08, MMVE3-01-06, EZA08-07.
final _catalogue = RegExp(r'^([A-Z]{1,8}-?\d[A-Z0-9]*(?:[- ]\d+[A-Z]?)*)\s*-\s*(.+)$');

final _brand = RegExp(
    r'^(zoom karaoke|zoom|sunfly karaoke|sunfly|acoustative|karafun|sound choice|chartbuster|mr entertainer|kjk)\s*-\s*',
    caseSensitive: false);

final _trailingId = RegExp(r'\s+-\s+\d{4,6}$');
final _youtube = RegExp(r'\s*-\s*youtube\s*$', caseSensitive: false);
final _brackets = RegExp(r'\(([^()]*)\)|\[([^\[\]]*)\]');

/// Words that mark a bracketed group as a performance/version note.
final _versionWords = RegExp(
    r'\b(semitones?|down|lower|higher|key|cut|version|remake|edit|extended|intro|ending|outro|live|'
    r'instrumental|solo|solos|remix|mix|clean|slow|upbeat|bv|bvs|backing vocals|no vocals|without|minus|'
    r'multiplex|male|female|play ?off|duet|acoustic|unplugged|short|long|fade|reprise|cover|uptempo)\b|^in [a-g](#|b)?m?$|\bkey of [a-g]',
    caseSensitive: false);

/// Bracketed groups that carry no information worth keeping.
final _noiseWords = RegExp(
    r'karaoke|originally performed|in the style of|style of|with lyrics|lyrics|^\d{3,4}p$|^hd$|^4k$|'
    r'best version|official|^audio$|^video$|custom backing track|backing track|^mp3$|^cdg$|^mp4$|^hq$',
    caseSensitive: false);

/// Unbracketed version notes. Each must sit at the end of the name or just
/// before a ` - ` separator.
final List<RegExp> _looseVersions = [
  r'down \d{1,2}',
  r'up \d{1,2}',
  r'(?:\d{1,2}|one|two|three|four|five|six|seven) semitones? (?:down|up|lower|higher)',
  r'in [A-G](?:#|b)?(?: ?minor| ?major|m)?',
  r'extended(?: version)?',
  r'cut(?: down)?',
  r'clean ending',
  r'slow(?: version)?',
  r'upbeat(?: version)?',
  r'with intro',
  r'with bvs?',
  r'no vocals(?: split by lalalai)?',
  r'original (?:male |female )?key',
  r'short version',
  r'live',
].map((p) => RegExp('\\s+($p)(?=\\s*(?:\$|-\\s))', caseSensitive: false)).toList();

final _noiseLoose = RegExp(
    r'\s*\b(?:karaoke version from zoom(?: karaoke)?|karaoke version|karaoke|with lyrics|lyrics|custom backing track(?: ?-? ?\d+)?|backing track|instrumental version|hq|hd)\b\s*',
    caseSensitive: false);

/// `(Originally Performed By Neil Diamond)`, `(in the Style of Adele)`.
final _styleOf = RegExp(
    r'^(?:karaoke\s+)?(?:originally performed by|made famous by|in the style of|as performed by|style of)\s+(.+)$',
    caseSensitive: false);

final _plainNoise = RegExp(
    r'^(?:(?:karaoke|best|official|lyric|lyrics|hd|hq|audio|music)(?: version| video)?|\d{1,2}[.:]\d{2})$',
    caseSensitive: false);

final _stylePart = RegExp(
    r'\b(cover|version|reimagined|fusion|makeover|lyric video|era blend|remix)\b|^blues|jazz$',
    caseSensitive: false);
final _channelNoise = RegExp(r'\b(the era blend|neosoul machine|hollow blues)\b', caseSensitive: false);

final _meaningless = RegExp(r'^(?:track\s*)?\d{1,3}(?:\s*track)?$', caseSensitive: false);

// ------------------------------------------------------------------ parser

ParsedName parseFileName(String stem, {String? folderName}) {
  var s = stem;

  // 1. Character clean-up.
  s = s.replaceAll(_emoji, ' ');
  s = s.replaceAll(_dashes, '-');
  s = s.replaceAll(_curlySingle, "'").replaceAll(_curlyDouble, '"');
  if (s.contains('_')) {
    // `Frank_Sinatra_Bad_Bad_Leroy_Brown(MP3+CDG_Karaoke)_38412`
    s = s.replaceFirst(RegExp(r'_\d{4,8}$'), '');
    // `You_re`, `Don_t`: the apostrophe became an underscore.
    s = s.replaceAllMapped(
        RegExp(r"([A-Za-z])_(re|ll|ve|t|s|d|m)(?=_|\(|$)", caseSensitive: false), (m) => "${m[1]}'${m[2]}");
    // `11-CYNTHIA SHEELER _ I'LL CRY OVER YOU`, `Ambassadors_ Too much`:
    // in a name that already has spaces, an underscore stood for a colon
    // or dash.
    if (s.contains(' ')) s = s.replaceAll(RegExp(r'\s*_\s+|\s+_\s*'), ' - ');
    s = s.replaceAll(RegExp(r'_+-_+'), ' - ').replaceAll('_', ' ');
  }
  final versions = <String>[];
  if (!s.contains(' ') && RegExp(r'[a-z][A-Z]').allMatches(s).length >= 2) {
    // `SummerOf69BryanAdamsD`, `ChasingPavementsAdeleCm`: split the words
    // and keep a trailing key as a version note.
    s = s
        .replaceAllMapped(RegExp(r'([a-z])([A-Z0-9])'), (m) => '${m[1]} ${m[2]}')
        .replaceAllMapped(RegExp(r'([0-9])([A-Z])'), (m) => '${m[1]} ${m[2]}');
    final key = RegExp(r'\s(?:key\s?)?([A-G](?:b|#)?m?)$', caseSensitive: false).firstMatch(s);
    if (key != null && key.start > 0) {
      versions.add('in ${key[1]}');
      s = s.substring(0, key.start);
    }
  }
  s = s.replaceAll('|', '   ');
  s = s.trim();

  // 2. Leading track number (before whitespace runs are collapsed, so the
  //    double space in `09  DEAN MARTIN` still counts).
  s = s.replaceFirst(_trackNumber, '');

  // Runs of 3+ spaces are where a `|` or ` - ` was stripped by a downloader.
  s = s.replaceAll(RegExp(r'\s{3,}'), ' - ');
  s = s.replaceAll(RegExp(r'\s+'), ' ').trim();
  s = s.replaceFirst(_youtube, '');

  // 3. Bracketed groups: keep versions, drop noise, leave the rest in place.
  String? styleArtist;
  s = s.replaceAllMapped(_brackets, (m) {
    final inner = (m.group(1) ?? m.group(2) ?? '').trim();
    if (inner.isEmpty) return ' ';
    final styleOf = _styleOf.firstMatch(inner);
    if (styleOf != null) {
      styleArtist ??= styleOf.group(1)!.trim();
      return ' ';
    }
    if (_plainNoise.hasMatch(inner)) return ' ';
    if (_noiseWords.hasMatch(inner) && !_versionWords.hasMatch(inner)) return ' ';
    if (_versionWords.hasMatch(inner)) {
      versions.add(inner);
      return ' ';
    }
    if (m.group(2) != null) return ' '; // [BEST VERSION]-style tags
    return m.group(0)!;
  });
  s = s.replaceAll(RegExp(r'\s+'), ' ').trim();

  // 4. Unbracketed noise and version notes.
  s = s.replaceAll(_noiseLoose, ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
  var changed = true;
  while (changed) {
    changed = false;
    for (final re in _looseVersions) {
      final m = re.firstMatch(s);
      if (m != null) {
        // Never strip the whole name down to nothing.
        final rest = (s.substring(0, m.start) + s.substring(m.end)).trim();
        if (rest.replaceAll(RegExp(r'[\s-]'), '').isEmpty) continue;
        versions.insert(0, m.group(1)!);
        s = (s.substring(0, m.start) + s.substring(m.end)).trim();
        changed = true;
      }
    }
  }
  s = s.replaceFirst(_trailingId, '');
  s = _trimJunk(s);

  // 5. Brand prefix and catalogue code (either order: `ZM80003 - Acoustative
  //    - ...`). A code is only stripped if a separator survives it.
  String? brand;
  String? code;
  for (var pass = 0; pass < 2; pass++) {
    final b = _brand.firstMatch(s);
    if (b != null && s.length > b.end) {
      brand = b.group(1);
      s = s.substring(b.end).trim();
    }
    final c = _catalogue.firstMatch(s);
    if (code == null && c != null) {
      final rest = c.group(2)!.trim();
      final digits = c.group(1)!.replaceAll(RegExp(r'\D'), '').length;
      if (rest.contains('-') && digits >= 2) {
        code = c.group(1);
        s = rest;
      }
    }
  }

  // 6. Split into parts.
  List<String> parts;
  if (s.contains(' - ')) {
    parts = s.split(' - ');
  } else if (code != null && s.contains('-')) {
    // SF126-06-BEAUTIFUL SOUTH-PERFECT 10: no spaces around hyphens.
    parts = s.split('-');
  } else if (RegExp(r'\s-|-\s').hasMatch(s)) {
    parts = s.split(RegExp(r'\s+-\s*|\s*-\s+'));
  } else {
    parts = [s];
  }
  parts = parts.map(_trimJunk).where((p) => p.isNotEmpty).toList();
  if (parts.isEmpty) parts = [_trimJunk(stem)];
  // YouTube covers: `Hotel California - Eagles   Soul Blues Rock Fusion`.
  // A part that only describes the style is a version note.
  if (parts.length > 1) {
    final style = parts.skip(1).where(_stylePart.hasMatch).toList();
    for (final st in style) {
      parts.remove(st);
      final cleaned = st.replaceAll(_channelNoise, '').trim();
      if (cleaned.isNotEmpty) versions.add(cleaned);
    }
  }

  String title;
  String? artist;
  var orderKnown = false;
  var fromFolder = false;

  if (parts.length == 1) {
    title = parts.first;
    // `Acoustative - Human (Two Semitones Down) (Killers)`: with a brand
    // prefix, a trailing bracket is the artist.
    final tail = RegExp(r'^(.+?)\s*\(([^()]+)\)$').firstMatch(title);
    if (brand != null && tail != null) {
      title = tail.group(1)!;
      artist = tail.group(2);
      orderKnown = true;
    }
    final bare = stem.trim();
    final meaningless = _meaningless.hasMatch(bare) ? bare : (_meaningless.hasMatch(title) ? title : null);
    if (meaningless != null && folderName != null) {
      final n = RegExp(r'\d+').firstMatch(meaningless)?.group(0);
      title = n == null ? title : 'Track $n';
      artist = folderName;
      fromFolder = true;
      orderKnown = true;
    }
  } else if (parts.length == 2) {
    final a = parts[0], b = parts[1];
    if (brand != null && brand.toLowerCase().startsWith('zoom')) {
      // Zoom Karaoke names are `Title - Artist`.
      title = a;
      artist = b;
      orderKnown = true;
    } else if (_isCommaArtist(b) && !_isCommaArtist(a)) {
      title = a;
      artist = b;
      orderKnown = true;
    } else if (_isCommaArtist(a)) {
      artist = a;
      title = b;
      orderKnown = true;
    } else if (folderName != null && normalize(folderName) == normalize(b)) {
      artist = b;
      title = a;
      orderKnown = true;
    } else if (folderName != null && normalize(folderName) == normalize(a)) {
      artist = a;
      title = b;
      orderKnown = true;
    } else {
      artist = a;
      title = b;
    }
  } else {
    // Three or more parts: first is the artist, the rest is the title.
    artist = parts.first;
    title = parts.sublist(1).join(' - ');
  }

  if (artist == null && styleArtist != null) {
    artist = styleArtist;
    orderKnown = true;
  }
  if (artist != null && !fromFolder) {
    artist = tidyCase(_uncomma(_trimJunk(artist)), keepShortCaps: true);
  }
  title = tidyCase(_trimJunk(title));
  if (title.isEmpty) title = tidyCase(_trimJunk(stem));
  if (artist != null && artist.isEmpty) artist = null;

  return ParsedName(
    title: title,
    artist: artist,
    version: versions.isEmpty ? null : versions.join(', '),
    catalogueCode: code,
    brand: brand,
    orderKnown: orderKnown,
    artistFromFolder: fromFolder,
  );
}

String _trimJunk(String s) =>
    s.replaceAll(RegExp(r'^[\s\-,.;:]+|[\s\-,;:]+$'), '').replaceAll(RegExp(r'\(\s*\)'), '').trim();

/// `Jones, Tom`, `Eagles, The`, `Righteous Brothers, The`.
bool _isCommaArtist(String s) {
  final m = RegExp(r'^([^,]+),\s*([^,]+)$').firstMatch(s);
  if (m == null) return false;
  final right = m.group(2)!.trim();
  if (right.toLowerCase() == 'the') return true;
  final left = m.group(1)!.trim().split(' ').length;
  final rightWords = right.split(' ').length;
  return (left <= 2 && rightWords <= 2) || (left == 1 && rightWords <= 5);
}

String _uncomma(String s) {
  if (!_isCommaArtist(s)) return s;
  final i = s.indexOf(',');
  // `Puckett, Gary And The Union Gap` can't be flipped safely; leave it.
  if (s.substring(i + 1).trim().split(' ').length > 2) return s;
  return '${s.substring(i + 1).trim()} ${s.substring(0, i).trim()}';
}
