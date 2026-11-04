/// Text helpers shared by the filename parser and search.
library;

const Map<String, String> _foldMap = {
  'à': 'a', 'á': 'a', 'â': 'a', 'ã': 'a', 'ä': 'a', 'å': 'a', //
  'ç': 'c', 'è': 'e', 'é': 'e', 'ê': 'e', 'ë': 'e', //
  'ì': 'i', 'í': 'i', 'î': 'i', 'ï': 'i', 'ñ': 'n', //
  'ò': 'o', 'ó': 'o', 'ô': 'o', 'õ': 'o', 'ö': 'o', 'ø': 'o', //
  'ù': 'u', 'ú': 'u', 'û': 'u', 'ü': 'u', 'ý': 'y', 'ÿ': 'y', 'ß': 'ss',
};

final RegExp _apostrophes = RegExp("['‘’`´]");
final RegExp _nonWord = RegExp(r'[^a-z0-9]+');

/// Lower-cases, folds accents, drops apostrophes (so `cant` finds `Can't`),
/// turns `&` into `and`, and reduces everything else to single spaces.
String normalize(String input) {
  var s = input.toLowerCase();
  final b = StringBuffer();
  for (final rune in s.runes) {
    final ch = String.fromCharCode(rune);
    b.write(_foldMap[ch] ?? ch);
  }
  s = b.toString().replaceAll(_apostrophes, '').replaceAll('&', ' and ');
  return s.replaceAll(_nonWord, ' ').trim();
}

/// Words of [normalize]d text.
List<String> tokens(String input) {
  final n = normalize(input);
  return n.isEmpty ? const [] : n.split(' ');
}

/// Key that groups copies of the same song across folders.
String groupKey(String title, String? artist) {
  final t = normalize(title);
  final a = artist == null ? '' : normalize(artist);
  return '$a|$t';
}

const Set<String> _smallWords = {
  'a', 'an', 'and', 'as', 'at', 'but', 'by', 'for', 'in', 'of', 'on', 'or', //
  'the', 'to', 'vs', 'with', 'from', 'into', 'nor', 'n',
};

/// Title Case for names that arrive ALL CAPS or all lower case. Names that
/// already mix case are left alone, because Dean (or the label) chose it.
String tidyCase(String s, {bool keepShortCaps = false}) {
  final letters = s.replaceAll(RegExp(r'[^A-Za-z]'), '');
  if (letters.isEmpty) return s;
  final allUpper = letters == letters.toUpperCase();
  final allLower = letters == letters.toLowerCase();
  if (!allUpper && !allLower) return s;
  if (keepShortCaps && allUpper && letters.length <= 4 && !s.contains(' ')) {
    return s; // ABBA, UB40
  }
  final words = s.toLowerCase().split(' ');
  for (var i = 0; i < words.length; i++) {
    final w = words[i];
    if (w.isEmpty) continue;
    if (i > 0 && _smallWords.contains(w)) continue;
    words[i] = _capitalise(w);
  }
  return words.join(' ');
}

String _capitalise(String w) {
  // Capitalise the first letter, and the letter after a hyphen or bracket.
  final b = StringBuffer();
  var up = true;
  for (final rune in w.runes) {
    final ch = String.fromCharCode(rune);
    if (up && RegExp(r'[a-z]').hasMatch(ch)) {
      b.write(ch.toUpperCase());
      up = false;
    } else {
      b.write(ch);
      if (RegExp(r'[a-z0-9]').hasMatch(ch)) up = false;
    }
    if (ch == '-' || ch == '(' || ch == '/') up = true;
  }
  return b.toString();
}

/// Levenshtein distance, stopping early once it exceeds [max].
int editDistance(String a, String b, {int max = 3}) {
  if ((a.length - b.length).abs() > max) return max + 1;
  var prev = List<int>.generate(b.length + 1, (i) => i);
  for (var i = 1; i <= a.length; i++) {
    final cur = List<int>.filled(b.length + 1, 0);
    cur[0] = i;
    var rowMin = cur[0];
    for (var j = 1; j <= b.length; j++) {
      final cost = a.codeUnitAt(i - 1) == b.codeUnitAt(j - 1) ? 0 : 1;
      cur[j] = [prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + cost].reduce((x, y) => x < y ? x : y);
      if (cur[j] < rowMin) rowMin = cur[j];
    }
    if (rowMin > max) return max + 1;
    prev = cur;
  }
  return prev[b.length];
}
