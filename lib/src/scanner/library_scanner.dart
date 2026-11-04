import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common/sqlite_api.dart';

import '../data/database.dart';
import '../data/schema.dart';
import '../data/search.dart';
import '../text.dart';
import 'filename_parser.dart';
import 'folder_walker.dart';

const Set<String> audioExtensions = {'.mp3', '.wav', '.wma', '.m4a', '.flac', '.ogg', '.aac'};
const Set<String> videoExtensions = {
  '.mp4',
  '.avi',
  '.mpg',
  '.mpeg',
  '.mkv',
  '.mov',
  '.wmv',
  '.m4v',
  '.webm'
};

/// What one scan did. Shown to Dean after a rescan, and useful when tuning.
class ScanReport {
  int added = 0;
  int updated = 0;
  int removed = 0;
  int unchanged = 0;
  int foldersWalked = 0;
  int duplicateZipsSkipped = 0;
  int lyricSheetsUnmatched = 0;
  final List<String> orphanCdgs = [];
  final List<String> unreadableFolders = [];
  final List<String> missingRoots = [];
  final List<String> errors = [];
  Duration elapsed = Duration.zero;

  bool get changed => added + updated + removed > 0;
  int get tracks => added + updated + unchanged;

  void addAll(ScanReport o) {
    added += o.added;
    updated += o.updated;
    removed += o.removed;
    unchanged += o.unchanged;
    foldersWalked += o.foldersWalked;
    duplicateZipsSkipped += o.duplicateZipsSkipped;
    lyricSheetsUnmatched += o.lyricSheetsUnmatched;
    orphanCdgs.addAll(o.orphanCdgs);
    unreadableFolders.addAll(o.unreadableFolders);
    missingRoots.addAll(o.missingRoots);
    errors.addAll(o.errors);
  }

  @override
  String toString() => 'tracks: $tracks (added $added, updated $updated, removed $removed, '
      'unchanged $unchanged), folders: $foldersWalked, orphan CDGs: ${orphanCdgs.length}, '
      'duplicate zips skipped: $duplicateZipsSkipped, unmatched .txt: $lyricSheetsUnmatched, '
      'unreadable folders: ${unreadableFolders.length}, missing roots: ${missingRoots.length}, '
      'took ${elapsed.inMilliseconds} ms';
}

class _Candidate {
  _Candidate(this.dir, this.file, this.kind);
  final String dir;
  final FileEntry file;
  final String kind;
  String? cdgName;
  int cdgMtime = 0;
  String? lyricsPath;
  int lyricsMtime = 0;
  bool stems = false;
  late ParsedName parsed;

  String get path => p.join(dir, file.name);
  String get stem => p.basenameWithoutExtension(file.name);
  String get ext => p.extension(file.name).toLowerCase();

  /// Freshness is mtime AND this signature: it changes when a .cdg, lyric
  /// sheet or stems file appears, disappears or changes beside an untouched
  /// track, and when the parser rules change.
  String get pairSig => 'v$parserVersion|c:${cdgName ?? '-'}:$cdgMtime|'
      'l:${lyricsPath ?? '-'}:$lyricsMtime|s:${stems ? 1 : 0}';

  String get category {
    final mb = file.size / (1024 * 1024);
    if (kind == 'video') return mb > 1500 ? 'mix' : 'song';
    if (ext == '.wav') return mb > 150 ? 'mix' : 'song';
    if (kind == 'audio') return mb > 60 ? 'mix' : 'song';
    return 'song';
  }
}

class _LyricSheet {
  _LyricSheet(this.dir, this.file, this.key);
  final String dir;
  final FileEntry file;
  final String key;
  bool used = false;
  String get path => p.join(dir, file.name);
}

/// Indexes the library folders into the database.
///
/// Rescans are incremental: unchanged files cost a stat and nothing else,
/// changed files are UPDATEd by id (never `INSERT OR REPLACE`, which would
/// cascade-delete playlists and history), and the search index is rebuilt
/// once at the end, only if something changed.
class LibraryScanner {
  LibraryScanner(this.db);
  final EztigerDatabase db;

  /// Scans every root folder.
  Future<ScanReport> scanAll({void Function(int folders, String current)? onProgress}) async {
    final total = ScanReport();
    final sw = Stopwatch()..start();
    for (final root in await db.folders.roots()) {
      if (!root.included) continue;
      total.addAll(await scanRoot(root.id, onProgress: onProgress, rebuildIndex: false));
    }
    if (total.changed || await db.getMeta('fts_built') != '1') await _finishIndex();
    total.elapsed = sw.elapsed;
    return total;
  }

  /// Adds [path] as a root folder (if it isn't one) and scans it.
  Future<ScanReport> addAndScan(String path, {void Function(int, String)? onProgress}) async {
    final id = await db.folders.addRoot(path);
    return scanRoot(id, onProgress: onProgress);
  }

  Future<ScanReport> scanRoot(int rootId,
      {void Function(int folders, String current)? onProgress, bool rebuildIndex = true}) async {
    final report = ScanReport();
    final sw = Stopwatch()..start();
    final root = await db.folders.byId(rootId);
    if (root == null) throw ArgumentError('No folder with id $rootId');

    // A missing root is usually an unplugged drive. Do nothing at all:
    // deleting its tracks would wipe every playlist that uses them.
    if (!Directory(root.path).existsSync()) {
      report.missingRoots.add(root.path);
      report.elapsed = sw.elapsed;
      return report;
    }

    // What the database already knows under this root.
    final folderRows = await db.db.rawQuery('''
WITH RECURSIVE sub(id) AS (
  SELECT ? UNION ALL SELECT f.id FROM folders f JOIN sub ON f.parent_id = sub.id
)
SELECT id, path, parent_id, included, track_count, is_root FROM folders WHERE id IN (SELECT id FROM sub)''',
        [rootId]);
    final folderIds = {for (final r in folderRows) r['path'] as String: r['id'] as int};
    final folderCounts = {for (final r in folderRows) r['id'] as int: r['track_count'] as int};
    final protectedDirs = <String>[
      for (final r in folderRows)
        if (r['included'] == 0) r['path'] as String,
    ];
    final excluded = protectedDirs.toSet();
    final trackRows = await db.db.rawQuery('''
SELECT id, path, folder_id, size, mtime, pair_sig, kind, user_title, user_artist FROM tracks
WHERE folder_id IN (${folderIds.isEmpty ? 'NULL' : folderIds.values.join(',')})''');
    final existing = {for (final r in trackRows) r['path'] as String: r};

    // 1. Walk and classify.
    final listings = <DirListing>[];
    final candidates = <_Candidate>[];
    final sheets = <_LyricSheet>[];
    final seenDirs = <String>{};
    for (final listing in walkFolders(root.path, skip: excluded.contains)) {
      report.foldersWalked++;
      onProgress?.call(report.foldersWalked, listing.path);
      seenDirs.add(listing.path);
      seenDirs.addAll(listing.subdirs);
      if (listing.unreadable) {
        report.unreadableFolders.add(listing.path);
        protectedDirs.add(listing.path);
        continue;
      }
      listings.add(listing);
      _classify(listing, candidates, sheets, existing, report);
    }

    // 2. Parse names.
    for (final c in candidates) {
      c.parsed = parseFileName(c.stem, folderName: p.basename(c.dir));
    }

    // 3. Lyric sheets matched by title, including ones kept in another
    //    folder (`motown lyrics`, `duo lyrics`).
    _matchLyricSheets(candidates, sheets, report);

    // 4. Settle `A - B` names with no clue which part is the artist, using
    //    the whole library: artists repeat with many different titles,
    //    titles mostly don't.
    _resolveOrder(candidates);

    // 5. Write everything in one transaction.
    bool under(String path, String dir) => path == dir || path.startsWith('$dir${p.separator}');
    await db.db.transaction((txn) async {
      final perFolder = <int, int>{};
      for (final l in listings) {
        if (!folderIds.containsKey(l.path)) {
          folderIds[l.path] = await txn.insert('folders', {
            'path': l.path,
            'parent_id': folderIds[p.dirname(l.path)],
            'name': p.basename(l.path),
          });
        }
        perFolder[folderIds[l.path]!] = 0;
      }

      final seenTracks = <String>{};
      final now = DateTime.now().millisecondsSinceEpoch;
      for (final c in candidates) {
        final folderId = folderIds[c.dir]!;
        perFolder[folderId] = (perFolder[folderId] ?? 0) + 1;
        final path = c.path;
        seenTracks.add(path);
        final old = existing[path];
        final sig = c.pairSig;
        if (old != null &&
            old['size'] == c.file.size &&
            old['mtime'] == c.file.mtime &&
            old['pair_sig'] == sig &&
            old['folder_id'] == folderId) {
          report.unchanged++;
          continue;
        }
        final values = <String, Object?>{
          'folder_id': folderId,
          'file_name': c.file.name,
          'kind': c.kind,
          'cdg_path': c.cdgName == null ? null : p.join(c.dir, c.cdgName!),
          'lyrics_path': c.lyricsPath,
          'lyrics_text': c.lyricsPath == null ? null : _readText(c.lyricsPath!),
          'has_stems': c.stems ? 1 : 0,
          'category': c.category,
          'size': c.file.size,
          'mtime': c.file.mtime,
          'pair_sig': sig,
          'title': c.parsed.title,
          'artist': c.parsed.artist,
          'version': c.parsed.version,
          'catalogue_code': c.parsed.catalogueCode,
          'group_key': groupKey((old?['user_title'] as String?) ?? c.parsed.title,
              (old?['user_artist'] as String?) ?? c.parsed.artist),
        };
        if (old == null) {
          values['path'] = path;
          values['added_at'] = now;
          await txn.insert('tracks', values);
          report.added++;
        } else {
          // UPDATE by id. Never REPLACE: see schema.dart.
          await txn.update('tracks', values, where: 'id = ?', whereArgs: [old['id']]);
          report.updated++;
        }
      }

      // Files that have gone. Anything under an excluded or unreadable
      // folder is left alone.
      for (final e in existing.entries) {
        if (seenTracks.contains(e.key)) continue;
        final dir = p.dirname(e.key);
        if (protectedDirs.any((d) => under(dir, d))) continue;
        await txn.delete('tracks', where: 'id = ?', whereArgs: [e.value['id']]);
        report.removed++;
      }
      for (final r in folderRows) {
        final path = r['path'] as String;
        if (r['is_root'] == 1 || seenDirs.contains(path)) continue;
        if (protectedDirs.any((d) => under(path, d))) continue;
        await txn.delete('folders', where: 'id = ?', whereArgs: [r['id']]);
        folderIds.remove(path);
      }

      for (final e in perFolder.entries) {
        if (folderCounts[e.key] != e.value) {
          await txn.update('folders', {'track_count': e.value}, where: 'id = ?', whereArgs: [e.key]);
        }
      }
      await _updateTotals(txn, rootId);
      if (rebuildIndex && (report.changed || await _ftsNotBuilt(txn))) {
        await _rebuild(txn);
      }
    });

    report.elapsed = sw.elapsed;
    return report;
  }

  // ----------------------------------------------------------- classify

  void _classify(DirListing l, List<_Candidate> out, List<_LyricSheet> sheets,
      Map<String, Map<String, Object?>> existing, ScanReport report) {
    final byStem = <String, List<FileEntry>>{};
    final stemTargets = <String>{};
    for (final f in l.files) {
      final lower = f.lowerName;
      if (lower.endsWith('.vdjstems')) {
        stemTargets.add(lower.substring(0, lower.length - '.vdjstems'.length));
        continue;
      }
      byStem.putIfAbsent(p.basenameWithoutExtension(lower), () => []).add(f);
    }
    String ext(FileEntry f) => p.extension(f.lowerName);
    bool playable(FileEntry f) => audioExtensions.contains(ext(f)) || videoExtensions.contains(ext(f));

    final claimedTxt = <String>{};
    FileEntry? txtFor(String stem) {
      for (final key in [stem, 'lyrics $stem', '$stem lyrics', 'lyrics - $stem']) {
        final hit = byStem[key]?.where((f) => ext(f) == '.txt').firstOrNull;
        if (hit != null) return hit;
      }
      return null;
    }

    for (final f in l.files) {
      final e = ext(f);
      final stem = p.basenameWithoutExtension(f.lowerName);
      if (playable(f)) {
        final isVideo = videoExtensions.contains(e);
        // Pairing is case-insensitive: `Reason To Believe.CDG` + `.MP3`.
        final cdg = isVideo ? null : byStem[stem]?.where((x) => ext(x) == '.cdg').firstOrNull;
        final c = _Candidate(l.path, f, cdg != null ? 'cdg' : (isVideo ? 'video' : 'audio'));
        if (cdg != null) {
          c.cdgName = cdg.name;
          c.cdgMtime = cdg.mtime;
        }
        final txt = txtFor(stem);
        if (txt != null) {
          c.lyricsPath = p.join(l.path, txt.name);
          c.lyricsMtime = txt.mtime;
          claimedTxt.add(txt.lowerName);
        }
        c.stems = stemTargets.contains(f.lowerName);
        out.add(c);
      } else if (e == '.cdg') {
        final hasAudio = byStem[stem]!.any((x) => audioExtensions.contains(ext(x)));
        if (!hasAudio) report.orphanCdgs.add(p.join(l.path, f.name));
      } else if (e == '.zip') {
        final zipped = _zipCandidate(l, f, byStem, existing, report);
        if (zipped != null) out.add(zipped);
      }
    }

    for (final f in l.files) {
      if (ext(f) != '.txt' || claimedTxt.contains(f.lowerName)) continue;
      final key = normalize(p
          .basenameWithoutExtension(f.name)
          .replaceFirst(RegExp(r'^lyrics\s*-?\s*|\s*-?\s*lyrics$', caseSensitive: false), ''));
      if (key.length >= 2) sheets.add(_LyricSheet(l.path, f, key));
    }
  }

  /// A .zip holding MP3+G is indexed as karaoke (the player unzips it).
  /// Skipped if an extracted copy sits beside it.
  _Candidate? _zipCandidate(DirListing l, FileEntry f, Map<String, List<FileEntry>> byStem,
      Map<String, Map<String, Object?>> existing, ScanReport report) {
    bool hasPlayable(String stem) =>
        (byStem[stem] ?? const []).any((x) => audioExtensions.contains(p.extension(x.lowerName)));
    final stem = p.basenameWithoutExtension(f.lowerName);
    if (hasPlayable(stem)) {
      report.duplicateZipsSkipped++;
      return null;
    }
    final path = p.join(l.path, f.name);
    final old = existing[path];
    if (old != null && old['size'] == f.size && old['mtime'] == f.mtime) {
      return _Candidate(l.path, f, 'cdg_zip'); // Known MP3+G zip, unchanged.
    }
    InputFileStream? input;
    try {
      input = InputFileStream(path);
      final archive = ZipDecoder().decodeStream(input);
      final names = archive.files.where((x) => x.isFile).map((x) => x.name.toLowerCase()).toList();
      final hasCdg = names.any((n) => n.endsWith('.cdg'));
      final audio = names.where((n) => audioExtensions.contains(p.extension(n))).toList();
      if (!hasCdg || audio.isEmpty) return null;
      if (audio.any((n) => hasPlayable(p.basenameWithoutExtension(n)))) {
        report.duplicateZipsSkipped++;
        return null;
      }
      return _Candidate(l.path, f, 'cdg_zip');
    } catch (e) {
      report.errors.add('Could not read zip $path: $e');
      return null;
    } finally {
      input?.closeSync();
    }
  }

  void _matchLyricSheets(List<_Candidate> candidates, List<_LyricSheet> sheets, ScanReport report) {
    final byKey = <String, List<_LyricSheet>>{};
    for (final s in sheets) {
      byKey.putIfAbsent(s.key, () => []).add(s);
    }
    for (final c in candidates) {
      if (c.lyricsPath != null || c.kind == 'cdg_zip') continue;
      final keys = {
        normalize(c.parsed.title),
        normalize(c.stem),
        // Order not settled yet, so the "artist" may really be the title.
        if (!c.parsed.orderKnown && c.parsed.artist != null) normalize(c.parsed.artist!),
      };
      _LyricSheet? best;
      String? bestKey;
      var bestScore = -1;
      for (final k in keys) {
        for (final s in byKey[k] ?? const <_LyricSheet>[]) {
          int score;
          if (s.dir == c.dir) {
            score = 1 << 20;
          } else if (p.basename(s.dir).toLowerCase().contains('lyric') &&
              (c.dir == p.dirname(s.dir) || c.dir.startsWith('${p.dirname(s.dir)}${p.separator}'))) {
            score = p.dirname(s.dir).length;
          } else {
            continue;
          }
          if (score > bestScore) {
            best = s;
            bestKey = k;
            bestScore = score;
          }
        }
      }
      if (best != null) {
        c.lyricsPath = best.path;
        c.lyricsMtime = best.file.mtime;
        best.used = true;
        // The lyric sheet is named after the song, so it settles which part
        // of an `A - B` name is the title.
        final a = c.parsed.artist;
        if (!c.parsed.orderKnown &&
            a != null &&
            bestKey == normalize(a) &&
            bestKey != normalize(c.parsed.title)) {
          c.parsed.swap();
          c.parsed.orderKnown = true;
        }
      }
    }
    report.lyricSheetsUnmatched += sheets.where((s) => !s.used).length;
  }

  void _resolveOrder(List<_Candidate> candidates) {
    final partners = <String, Set<String>>{};
    final known = <String>{};
    for (final c in candidates) {
      final a = c.parsed.artist;
      if (a == null || c.parsed.artistFromFolder) continue;
      final na = normalize(a), nt = normalize(c.parsed.title);
      partners.putIfAbsent(na, () => {}).add(nt);
      partners.putIfAbsent(nt, () => {}).add(na);
      if (c.parsed.orderKnown) known.add(na);
    }
    for (final c in candidates) {
      final a = c.parsed.artist;
      if (a == null || c.parsed.orderKnown) continue;
      final na = normalize(a), nt = normalize(c.parsed.title);
      final titleIsArtist = known.contains(nt) && !known.contains(na);
      // Needs a clear margin: a title covered by two artists (`The
      // Wanderer` by Dion and by Status Quo) must not look like an artist.
      final moreLikely =
          !known.contains(na) && (partners[nt]?.length ?? 0) >= (partners[na]?.length ?? 0) + 2;
      if (titleIsArtist || moreLikely) c.parsed.swap();
    }
  }

  // ------------------------------------------------------------- helpers

  String? _readText(String path) {
    try {
      final f = File(path);
      if (f.lengthSync() > 256 * 1024) return null;
      final bytes = f.readAsBytesSync();
      final utf = utf8.decode(bytes, allowMalformed: true);
      // Old Windows text files are often Latin-1, not UTF-8.
      if ('�'.allMatches(utf).length > 3) return latin1.decode(bytes);
      return utf.startsWith('﻿') ? utf.substring(1) : utf;
    } on FileSystemException {
      return null;
    }
  }

  Future<void> _updateTotals(Transaction txn, int rootId) async {
    final rows = await txn.rawQuery('''
WITH RECURSIVE sub(id) AS (
  SELECT ? UNION ALL SELECT f.id FROM folders f JOIN sub ON f.parent_id = sub.id
)
SELECT id, parent_id, track_count, total_count FROM folders WHERE id IN (SELECT id FROM sub)''', [rootId]);
    final children = <int, List<int>>{};
    final own = <int, int>{};
    final stored = <int, int>{};
    for (final r in rows) {
      final id = r['id'] as int;
      own[id] = r['track_count'] as int;
      stored[id] = r['total_count'] as int;
      final parent = r['parent_id'] as int?;
      if (parent != null && id != rootId) children.putIfAbsent(parent, () => []).add(id);
    }
    final totals = <int, int>{};
    int total(int id) => totals[id] ??= own[id]! + (children[id] ?? const []).fold(0, (s, c) => s + total(c));
    for (final id in own.keys) {
      if (total(id) != stored[id]) {
        await txn.update('folders', {'total_count': totals[id]}, where: 'id = ?', whereArgs: [id]);
      }
    }
  }

  Future<bool> _ftsNotBuilt(DatabaseExecutor ex) async {
    if (!db.hasFts) return false;
    final r = await ex.query('meta', where: 'key = ?', whereArgs: ['fts_built']);
    return r.isEmpty || r.first['value'] != '1';
  }

  Future<void> _rebuild(DatabaseExecutor ex) async {
    if (!db.hasFts) return;
    await rebuildIndex(ex);
    await ex.rawInsert("INSERT INTO meta(key, value) VALUES('fts_built', '1') "
        'ON CONFLICT(key) DO UPDATE SET value = excluded.value');
  }

  Future<void> _finishIndex() => db.db.transaction(_rebuild);
}
