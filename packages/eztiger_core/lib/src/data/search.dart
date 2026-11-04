import 'package:sqflite_common/sqlite_api.dart';

import '../text.dart';
import 'daos.dart' show trackSelect;
import 'models.dart';

const String _typeExpr = "COALESCE(t.user_kind, CASE t.kind WHEN 'cdg' THEN 'CDG' "
    "WHEN 'cdg_zip' THEN 'CDG' WHEN 'video' THEN 'MP4' ELSE 'MP3' END)";

const String _subtreeCte = '''
WITH RECURSIVE sub(id) AS (
  SELECT ? UNION ALL SELECT f2.id FROM folders f2 JOIN sub ON f2.parent_id = sub.id
)''';

/// Rebuilds the whole full-text index. Called once at the end of a scan that
/// changed something.
Future<void> rebuildIndex(DatabaseExecutor ex) async {
  await ex.delete('tracks_fts');
  final ids = (await ex.rawQuery('SELECT id FROM tracks')).map((r) => r['id'] as int).toList();
  await indexTracks(ex, ids, freshTable: true);
}

/// Writes (or rewrites) the index rows for [ids].
Future<void> indexTracks(DatabaseExecutor ex, List<int> ids, {bool freshTable = false}) async {
  if (ids.isEmpty) return;
  final roots = (await ex.rawQuery('SELECT path FROM folders WHERE is_root = 1'))
      .map((r) => r['path'] as String)
      .toList()
    ..sort((a, b) => b.length.compareTo(a.length));
  const chunk = 500;
  for (var i = 0; i < ids.length; i += chunk) {
    final part = ids.sublist(i, i + chunk > ids.length ? ids.length : i + chunk);
    final rows = await ex.rawQuery(
        'SELECT t.*, f.path AS folder_path FROM tracks t JOIN folders f ON f.id = t.folder_id '
        'WHERE t.id IN (${List.filled(part.length, '?').join(',')})',
        part);
    final batch = ex.batch();
    for (final r in rows) {
      final id = r['id'] as int;
      if (!freshTable) batch.delete('tracks_fts', where: 'rowid = ?', whereArgs: [id]);
      final folderPath = r['folder_path'] as String;
      final root = roots.firstWhere((p) => folderPath.startsWith(p), orElse: () => '');
      final stem = (r['file_name'] as String).replaceFirst(RegExp(r'\.[^.]+$'), '');
      batch.insert('tracks_fts', {
        'rowid': id,
        'title': normalize((r['user_title'] ?? r['title']) as String),
        'artist': normalize(((r['user_artist'] ?? r['artist']) as String?) ?? ''),
        'version': normalize('${r['version'] ?? ''} ${r['catalogue_code'] ?? ''}'),
        'folder': normalize(folderPath.substring(root.length)),
        'file': normalize(stem),
        'lyrics': normalize((r['lyrics_text'] as String?) ?? ''),
      });
    }
    await batch.commit(noResult: true);
  }
  await ex.rawInsert("INSERT INTO meta(key, value) VALUES('fts_gen', '1') "
      'ON CONFLICT(key) DO UPDATE SET value = CAST(value AS INTEGER) + 1');
}

class SearchDao {
  /// Finds the best match for each line of a pasted song list, such as a set
  /// list typed in Notepad or copied from Excel. Blank lines are skipped;
  /// a line with no match comes back with a null track.
  Future<List<(String, Track?)>> matchList(String text) async {
    final out = <(String, Track?)>[];
    for (final raw in text.split(RegExp(r'\r?\n'))) {
      final line = cleanListLine(raw);
      if (line.isEmpty) continue;
      final hits = await search(line, limit: 1);
      out.add((line, hits.isEmpty ? null : hits.first.primary));
    }
    return out;
  }

  SearchDao(this.db, this.hasFts);
  final Database db;
  final bool hasFts;

  String? _vocabGen;
  Map<String, int> _vocab = {};
  List<String> _sortedVocab = [];

  /// Searches title, artist, version notes, folder names, file names and
  /// lyric sheets. Matching ignores case, accents, apostrophes and `&`/`and`,
  /// every word is a prefix (`swe car` finds Sweet Caroline), and a word
  /// that matches nothing is corrected to the closest word in the library
  /// (`faling` finds Falling).
  ///
  /// Copies of the same song in different folders come back as one
  /// [SearchGroup]. [folderId] limits the search to that folder and its
  /// subfolders; [type] to CDG, MP4 or MP3. An empty [query] lists everything
  /// in scope, by title.
  ///
  /// [sort] puts the results in A to Z order by title or by artist (songs
  /// without an artist go last); the default keeps the best matches first.
  Future<List<SearchGroup>> search(String query,
      {int? folderId, TrackType? type, int limit = 200, SearchSort sort = SearchSort.relevance}) async {
    final words = tokens(query);
    List<Map<String, Object?>> rows;
    if (words.isEmpty) {
      rows = await _browse(folderId, type, limit * 3, sort);
    } else if (hasFts) {
      final fixed = await _correct(words);
      // Words match as prefixes while typing, except numbers: `down 2`
      // must not match every name containing 20 or 2000.
      final terms = [
        for (var i = 0; i < fixed.length; i++)
          fixed.length > 1 && RegExp(r'^\d+$').hasMatch(fixed[i]) ? '"${fixed[i]}"' : '"${fixed[i]}"*'
      ];
      rows = await _fts(terms.join(' '), folderId, type, limit * 3);
      if (rows.isEmpty && fixed.length > 1) {
        // Nothing has every word: fall back to any word, best first.
        rows = await _fts(terms.join(' OR '), folderId, type, limit * 3);
      }
    } else {
      rows = await _like(words, folderId, type, limit * 3);
    }
    final groups = _group(rows.map(Track.fromRow), limit);
    if (sort != SearchSort.relevance) groups.sort((a, b) => compareForSort(a.primary, b.primary, sort));
    return groups;
  }

  List<SearchGroup> _group(Iterable<Track> tracks, int limit) {
    final groups = <String, List<Track>>{};
    for (final t in tracks) {
      groups.putIfAbsent(t.groupKey, () => []).add(t);
    }
    return groups.values.take(limit).map(SearchGroup.new).toList();
  }

  String _scope(int? folderId, TrackType? type, List<Object?> args) {
    final b = StringBuffer(' AND f.included = 1');
    if (folderId != null) b.write(' AND t.folder_id IN (SELECT id FROM sub)');
    if (type != null) {
      b.write(' AND $_typeExpr = ?');
      args.add(type.label);
    }
    return b.toString();
  }

  Future<List<Map<String, Object?>>> _browse(int? folderId, TrackType? type, int limit, SearchSort sort) {
    final args = <Object?>[if (folderId != null) folderId];
    final where = _scope(folderId, type, args);
    args.add(limit);
    return db.rawQuery('''
${folderId != null ? _subtreeCte : ''}
$trackSelect WHERE 1 = 1 $where
ORDER BY ${sort == SearchSort.artist ? "$_artistExpr IS NULL, $_artistExpr COLLATE NOCASE, " : ''}$_titleExpr COLLATE NOCASE LIMIT ?''',
        args);
  }

  static const _titleExpr = "COALESCE(NULLIF(t.user_title, ''), t.title)";
  static const _artistExpr = "COALESCE(NULLIF(t.user_artist, ''), t.artist)";

  Future<List<Map<String, Object?>>> _fts(String match, int? folderId, TrackType? type, int limit) {
    final args = <Object?>[if (folderId != null) folderId, match];
    final where = _scope(folderId, type, args);
    args.add(limit);
    return db.rawQuery('''
${folderId != null ? _subtreeCte : ''}
SELECT t.*, f.path AS folder_path, bm25(tracks_fts, 10.0, 6.0, 2.0, 1.5, 1.0, 0.3) AS rank
FROM tracks_fts JOIN tracks t ON t.id = tracks_fts.rowid JOIN folders f ON f.id = t.folder_id
WHERE tracks_fts MATCH ? $where
ORDER BY rank LIMIT ?''', args);
  }

  Future<List<Map<String, Object?>>> _like(List<String> words, int? folderId, TrackType? type, int limit) {
    final args = <Object?>[if (folderId != null) folderId];
    final conds = <String>[];
    String col(String c) => "REPLACE(LOWER($c), '''', '')";
    // `&` in a name never matches the word `and`, so leave it out here.
    final useful = words.where((w) => w != 'and').toList();
    for (final w in useful.isEmpty ? words : useful) {
      conds.add('(${[
        col('COALESCE(t.user_title, t.title)'),
        col("COALESCE(t.user_artist, t.artist, '')"),
        col("COALESCE(t.version, '')"),
        col('t.file_name'),
        col('f.path'),
        col("COALESCE(t.lyrics_text, '')"),
      ].map((c) => '$c LIKE ?').join(' OR ')})');
      args.addAll(List.filled(6, '%$w%'));
    }
    final where = _scope(folderId, type, args);
    args.add(limit);
    return db.rawQuery('''
${folderId != null ? _subtreeCte : ''}
$trackSelect WHERE ${conds.join(' AND ')} $where
ORDER BY COALESCE(t.user_title, t.title) COLLATE NOCASE LIMIT ?''', args);
  }

  // ---------------------------------------------------- spelling correction

  Future<void> _loadVocab() async {
    final gen =
        (await db.query('meta', where: 'key = ?', whereArgs: ['fts_gen'])).map((r) => r['value'] as String).firstOrNull;
    if (gen == _vocabGen) return;
    await db.execute("CREATE VIRTUAL TABLE IF NOT EXISTS tracks_fts_vocab USING fts5vocab(tracks_fts, 'row')");
    final rows = await db.rawQuery('SELECT term, doc FROM tracks_fts_vocab');
    _vocab = {for (final r in rows) r['term'] as String: r['doc'] as int};
    _sortedVocab = _vocab.keys.toList()..sort();
    _vocabGen = gen;
  }

  bool _hasPrefix(String w) {
    var lo = 0, hi = _sortedVocab.length;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (_sortedVocab[mid].compareTo(w) < 0) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    return lo < _sortedVocab.length && _sortedVocab[lo].startsWith(w);
  }

  Future<List<String>> _correct(List<String> words) async {
    await _loadVocab();
    if (_vocab.isEmpty) return words;
    return [
      for (final w in words)
        if (_hasPrefix(w) || w.length < 3 || RegExp(r'^\d+$').hasMatch(w)) w else _closest(w) ?? w
    ];
  }

  String? _closest(String w) {
    final max = w.length <= 4 ? 1 : 2;
    String? best;
    var bestD = max + 1;
    var bestDocs = 0;
    for (final e in _vocab.entries) {
      final d = editDistance(w, e.key, max: max);
      if (d < bestD || (d == bestD && d <= max && e.value > bestDocs)) {
        best = e.key;
        bestD = d;
        bestDocs = e.value;
      }
    }
    return bestD <= max ? best : null;
  }
}

/// Tidies one line of a pasted song list: drops numbering ("1.", "02 -"),
/// bullets, file extensions and Excel tabs.
String cleanListLine(String raw) {
  var s = raw.replaceAll('\t', ' - ').trim();
  s = s.replaceFirst(RegExp(r'^[\-\*•·]+\s*'), '');
  s = s.replaceFirst(RegExp(r'^\d{1,3}\s*[.):\-]\s*'), '');
  s = s.replaceFirst(RegExp(r'\.(mp3|cdg|zip|mp4|wav|avi|mkv|m4a|wma)$', caseSensitive: false), '');
  s = s.replaceAll(RegExp(r'(\s*-\s*)+$'), '');
  return s.trim();
}

/// The order search results come back in.
enum SearchSort { relevance, title, artist }

/// Compares two songs for [sort]: A to Z, ignoring case and accents, with
/// songs that have no artist after the rest when sorting by artist.
int compareForSort(Track a, Track b, SearchSort sort) {
  int byTitle() => normalize(a.title).compareTo(normalize(b.title));
  if (sort == SearchSort.artist) {
    final x = a.artist, y = b.artist;
    if (x == null || y == null) {
      if (x != y) return x == null ? 1 : -1;
    } else {
      final c = normalize(x).compareTo(normalize(y));
      if (c != 0) return c;
    }
  }
  return byTitle();
}
