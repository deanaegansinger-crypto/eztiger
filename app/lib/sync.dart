import 'dart:convert';

import 'package:eztiger_core/eztiger_core.dart';

/// EZTiger Pro: carries playlists and the keys songs are sung in between
/// the PC and the tablet, as one small file (EZtiger-sync.json).
///
/// The two keep the library in different places (C:\Users\…\backing 2024
/// april on the PC, the SD card on the tablet), so songs are written by
/// their path inside the library folder, and found again on the other side
/// by that path, by the end of it (when one side added a sub-folder as its
/// library), or by the file name.
class LibrarySync {
  LibrarySync(this.db);
  final EztigerDatabase db;

  static const fileName = 'EZtiger-sync.json';

  /// The sync file's contents: every playlist, and every song's key.
  Future<String> export({required Map<String, int> keyShifts}) async {
    final lib = await _Library.load(db);
    final playlists = <Map<String, Object?>>[];
    for (final pl in await db.playlists.all()) {
      final songs = await db.playlists.tracks(pl.id);
      playlists.add({
        'name': pl.name,
        'songs': [for (final t in songs) lib.describe(t)],
      });
    }
    final keys = <Map<String, Object?>>[];
    for (final MapEntry(key: path, value: k) in keyShifts.entries) {
      final t = lib.byPath[_norm(path)];
      if (t != null && k != 0) keys.add({...lib.describe(t), 'key': k});
    }
    return const JsonEncoder.withIndent(
      ' ',
    ).convert({'eztiger_sync': 1, 'exported': DateTime.now().toIso8601String(), 'playlists': playlists, 'keys': keys});
  }

  /// Reads a sync file from the other machine. Playlists with the same name
  /// are replaced, others are added; keys are set on the songs found.
  /// [keyShifts] is updated in place.
  Future<SyncResult> import(String json, {required Map<String, int> keyShifts}) async {
    final m = jsonDecode(json) as Map<String, dynamic>;
    if (m['eztiger_sync'] == null) throw const FormatException('This is not an EZtiger sync file.');
    final lib = await _Library.load(db);
    final result = SyncResult();
    final existing = {for (final p in await db.playlists.all()) p.name.toLowerCase(): p.id};
    for (final pl in (m['playlists'] as List? ?? []).cast<Map<String, dynamic>>()) {
      final name = (pl['name'] as String? ?? '').trim();
      if (name.isEmpty) continue;
      final ids = <int>[];
      for (final song in (pl['songs'] as List? ?? []).cast<Map<String, dynamic>>()) {
        final t = lib.find(song);
        if (t == null) {
          result.missing.add(_label(song));
        } else {
          ids.add(t.id);
        }
      }
      var id = existing[name.toLowerCase()];
      if (id != null) {
        await db.playlists.delete(id);
      }
      id = await db.playlists.create(name);
      await db.playlists.addAll(id, ids);
      result.playlists++;
      result.songs += ids.length;
    }
    for (final k in (m['keys'] as List? ?? []).cast<Map<String, dynamic>>()) {
      final t = lib.find(k);
      final semis = (k['key'] as num?)?.toInt() ?? 0;
      if (t == null || semis == 0) continue;
      keyShifts[t.path] = semis.clamp(-3, 3);
      result.keys++;
    }
    return result;
  }

  static String _label(Map<String, dynamic> song) {
    final title = song['title'] as String?, artist = song['artist'] as String?;
    if (title != null && title.isNotEmpty) return artist == null || artist.isEmpty ? title : '$title – $artist';
    return song['file'] as String? ?? '?';
  }
}

class SyncResult {
  int playlists = 0, songs = 0, keys = 0;
  final missing = <String>[];

  String get summary {
    final parts = [
      '$playlists playlist${playlists == 1 ? '' : 's'} with $songs song${songs == 1 ? '' : 's'}',
      '$keys key change${keys == 1 ? '' : 's'}',
    ];
    final s = 'Brought in ${parts.join(' and ')}.';
    return missing.isEmpty
        ? s
        : '$s ${missing.length} song${missing.length == 1 ? ' was' : 's were'} not in this library.';
  }
}

String _norm(String path) => path.replaceAll('\\', '/').toLowerCase();

/// Every song in the library, with its path inside its library folder.
class _Library {
  _Library(this.tracks, this.rel);
  final List<Track> tracks;
  final Map<int, String> rel; // track id -> normalised path inside its library folder
  late final byPath = {for (final t in tracks) _norm(t.path): t};
  late final byRel = {for (final t in tracks) rel[t.id]!: t};
  late final byName = () {
    final m = <String, List<Track>>{};
    for (final t in tracks) {
      (m[t.fileName.toLowerCase()] ??= []).add(t);
    }
    return m;
  }();

  static Future<_Library> load(EztigerDatabase db) async {
    final roots = [for (final f in await db.folders.roots()) _norm(f.path)]
      ..sort((a, b) => b.length.compareTo(a.length));
    final rows = await db.db.rawQuery(
      'SELECT t.*, f.path AS folder_path FROM tracks t JOIN folders f ON f.id = t.folder_id',
    );
    final tracks = rows.map(Track.fromRow).toList();
    final rel = <int, String>{};
    for (final t in tracks) {
      final path = _norm(t.path);
      final root = roots.where((r) => path.startsWith('$r/')).firstOrNull;
      rel[t.id] = root == null ? path.split('/').last : path.substring(root.length + 1);
    }
    return _Library(tracks, rel);
  }

  Map<String, Object?> describe(Track t) => {
    'file': t.fileName,
    'rel': rel[t.id],
    'title': t.title,
    if (t.artist != null) 'artist': t.artist,
  };

  Track? find(Map<String, dynamic> song) {
    final r = (song['rel'] as String?)?.toLowerCase();
    if (r != null && r.isNotEmpty) {
      final exact = byRel[r];
      if (exact != null) return exact;
      // One side's library folder is a sub-folder of the other's.
      for (final t in tracks) {
        final mine = rel[t.id]!;
        if (mine.endsWith('/$r') || r.endsWith('/$mine')) return t;
      }
    }
    final name = (song['file'] as String?)?.toLowerCase();
    final same = name == null ? null : byName[name];
    return same == null || same.isEmpty ? null : same.first;
  }
}
