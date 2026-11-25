import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:archive/archive_io.dart';
import 'package:eztiger_core/eztiger_core.dart';
import 'package:path/path.dart' as p;

/// Taking a playlist, and the song files themselves, from EZTiger Pro on the
/// PC to the tablet: as a folder or one zip (for a USB stick, an SD card or
/// Dropbox), or straight over the Wi-Fi. The tablet copies the songs into
/// its "EZTiger imports" folder and makes the playlist again, keys and all.
/// A playlist it already has can be updated (only new or changed songs are
/// copied) or kept beside the new one, under a dated name.
///
/// A package is a folder (or zip) holding [manifestName] and a songs folder
/// with each song's files: the song (MP3, zip or video) and its CDG and
/// lyric sheet, under their own names.

const manifestName = 'EZTiger playlist.json';
const songsFolder = 'songs';

/// One song in a package.
class TransferSong {
  TransferSong({required this.title, this.artist, required this.play, required this.files, this.key = 0});

  factory TransferSong.fromJson(Map<String, dynamic> j) => TransferSong(
        title: '${j['title'] ?? ''}',
        artist: j['artist'] as String?,
        play: '${j['play'] ?? ''}',
        files: [for (final f in (j['files'] as List? ?? const [])) '$f'],
        key: (j['key'] as num?)?.toInt() ?? 0,
      );

  final String title;
  final String? artist;

  /// The file that plays, by its name in the songs folder.
  final String play;

  /// All its files (the song, its CDG, its lyric sheet), by name.
  final List<String> files;

  /// EZTiger Pro's key change for the song, in semitones.
  final int key;

  Map<String, Object?> toJson() => {
        'title': title,
        if (artist != null) 'artist': artist,
        'play': play,
        'files': files,
        if (key != 0) 'key': key,
      };
}

/// A playlist with its songs' files.
class PlaylistPackage {
  PlaylistPackage({required this.name, required this.songs, this.sizes = const {}, this.sources = const {}});

  factory PlaylistPackage.fromJson(Map<String, dynamic> j) {
    if (j['eztiger_playlist'] == null) throw const FormatException('This is not an EZTiger playlist export.');
    return PlaylistPackage(
      name: '${j['name'] ?? 'Playlist'}',
      songs: [for (final s in (j['songs'] as List? ?? const [])) TransferSong.fromJson(s as Map<String, dynamic>)],
      sizes: {for (final e in ((j['sizes'] as Map?) ?? const {}).entries) '${e.key}': (e.value as num).toInt()},
    );
  }

  final String name;
  final List<TransferSong> songs;

  /// Each file's size in bytes, by name.
  final Map<String, int> sizes;

  /// Each file's place on this PC, by name (only when exporting).
  final Map<String, String> sources;

  /// Every file, once each, in playlist order.
  List<String> get fileNames => <String>{
        for (final s in songs) ...s.files,
      }.toList();

  int get totalBytes => sizes.values.fold(0, (a, b) => a + b);

  Map<String, Object?> toJson() => {
        'eztiger_playlist': 1,
        'name': name,
        'exported': DateTime.now().toIso8601String(),
        'songs': [for (final s in songs) s.toJson()],
        'sizes': sizes,
      };

  String toJsonText() => const JsonEncoder.withIndent(' ').convert(toJson());

  /// The playlist [name] and its songs from the library, ready to export.
  /// [keyShifts] are EZTiger Pro's saved keys (song path → semitones).
  static Future<PlaylistPackage> fromPlaylist(EztigerDatabase db, Playlist pl, {Map<String, int> keyShifts = const {}}) async {
    final names = <String, String>{}; // source path → name in the package
    final taken = <String>{};
    final sizes = <String, int>{};
    final sources = <String, String>{};
    // A song's files share a name; if another song already has it, both
    // become "name (2)".
    String nameFor(String stem) {
      var s = stem;
      for (var n = 2; taken.contains(s.toLowerCase()); n++) {
        s = '$stem ($n)';
      }
      taken.add(s.toLowerCase());
      return s;
    }

    final songs = <TransferSong>[];
    for (final t in await db.playlists.tracks(pl.id)) {
      final own = [t.path, t.cdgPath, t.lyricsPath].whereType<String>().where((f) => File(f).existsSync()).toList();
      if (!own.contains(t.path)) continue; // the song's file is gone
      final stem = names[t.path] != null
          ? p.basenameWithoutExtension(names[t.path]!)
          : nameFor(p.basenameWithoutExtension(t.path));
      final files = <String>[];
      for (final f in own) {
        final name = names[f] ??= '$stem${p.extension(f)}';
        files.add(name);
        sources[name] = f;
        sizes[name] = File(f).lengthSync();
      }
      songs.add(TransferSong(
        title: t.title,
        artist: t.artist,
        play: names[t.path]!,
        files: files,
        key: keyShifts[t.path] ?? 0,
      ));
    }
    return PlaylistPackage(name: pl.name, songs: songs, sizes: sizes, sources: sources);
  }
}

/// How far a copy has got.
typedef TransferProgress = void Function(int bytesDone, int bytesTotal, String file);

/// Passes progress on at most ten times a second, and always the end, so
/// redrawing the progress bar doesn't slow the copy down on a slow tablet.
TransferProgress? tenASecond(TransferProgress? f) {
  if (f == null) return null;
  final clock = Stopwatch()..start();
  var last = -1000;
  return (done, total, file) {
    final now = clock.elapsedMilliseconds;
    if (done >= total || now - last >= 100) {
      last = now;
      f(done, total, file);
    }
  };
}

/// A name safe for a folder or file on Windows and Android.
String safeName(String s) {
  final t = s.replaceAll(RegExp(r'[\\/:*?"<>|]+'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
  return t.isEmpty ? 'Playlist' : t;
}

/// The folder an export goes in, or a zip's name without ".zip".
String exportName(PlaylistPackage pkg) => 'EZTiger export - ${safeName(pkg.name)}';

/// Copies the package into a new folder in [destDir] and returns it.
Future<String> exportToFolder(PlaylistPackage pkg, String destDir, {TransferProgress? onProgress}) async {
  final out = Directory(p.join(destDir, exportName(pkg)));
  final songs = Directory(p.join(out.path, songsFolder))..createSync(recursive: true);
  var done = 0;
  final total = pkg.totalBytes;
  for (final name in pkg.fileNames) {
    onProgress?.call(done, total, name);
    // The operating system's own copy: much quicker than reading and writing.
    await File(pkg.sources[name]!).copy(p.join(songs.path, name));
    done += pkg.sizes[name] ?? 0;
  }
  File(p.join(out.path, manifestName)).writeAsStringSync(pkg.toJsonText());
  onProgress?.call(total, total, '');
  return out.path;
}

/// Packs the package into one zip in [destDir] and returns it. Songs are
/// stored as they are (MP3s and videos don't get smaller in a zip).
Future<String> exportToZip(PlaylistPackage pkg, String destDir, {TransferProgress? onProgress}) async {
  final path = p.join(destDir, '${exportName(pkg)}.zip');
  final zip = ZipFileEncoder()..create(path, level: ZipFileEncoder.store);
  var done = 0;
  final total = pkg.totalBytes;
  try {
    for (final name in pkg.fileNames) {
      onProgress?.call(done, total, name);
      await zip.addFile(File(pkg.sources[name]!), '$songsFolder/$name', ZipFileEncoder.store);
      done += pkg.sizes[name] ?? 0;
    }
    final manifest = utf8.encode(pkg.toJsonText());
    zip.addArchiveFile(ArchiveFile.bytes(manifestName, manifest));
  } finally {
    await zip.close();
  }
  onProgress?.call(total, total, '');
  return path;
}

/// True if [path] is something [readPackage] can open: an export folder, its
/// playlist file, or an export zip.
bool isPackage(String path) {
  if (Directory(path).existsSync()) return File(p.join(path, manifestName)).existsSync();
  final name = p.basename(path).toLowerCase();
  return name == manifestName.toLowerCase() || (name.endsWith('.zip') && name.startsWith('eztiger export'));
}

/// Where an incoming playlist goes on the tablet, and under what name.
class ImportPlan {
  const ImportPlan({required this.name, required this.folder, this.update = false});

  /// The playlist's name on the tablet.
  final String name;

  /// Its own folder; the songs go in its songs folder.
  final String folder;

  /// True: it updates a playlist already on the tablet. Songs already there
  /// (same name and size) aren't copied again, and ones no longer in the
  /// playlist are taken out of its folder.
  final bool update;
}

/// Decides, once the package's name is known, where it goes and whether it
/// updates a playlist already there. Null cancels.
typedef PlanFor = Future<ImportPlan?> Function(PlaylistPackage pkg);

/// What an import or receive brought in.
class ImportResult {
  const ImportResult(this.pkg, this.plan, {this.copied = 0, this.kept = 0});
  final PlaylistPackage pkg;
  final ImportPlan plan;

  /// Files copied, and files already on the tablet that were left as they were.
  final int copied, kept;
}

/// The import was cancelled when asked Update or Keep both.
class TransferCancelled implements Exception {
  const TransferCancelled();
}

/// True if [f] is already there with [size] bytes, so it needn't be copied.
bool _alreadyThere(File f, int? size) => size != null && f.existsSync() && f.lengthSync() == size;

/// An update: takes out of the songs folder the files no longer in [pkg].
void _tidy(String songsDir, PlaylistPackage pkg) {
  final wanted = {for (final n in pkg.fileNames) n.toLowerCase()};
  final dir = Directory(songsDir);
  if (!dir.existsSync()) return;
  for (final f in dir.listSync().whereType<File>()) {
    if (!wanted.contains(p.basename(f.path).toLowerCase())) f.deleteSync();
  }
}

PlaylistPackage _parse(String json) => PlaylistPackage.fromJson(jsonDecode(json) as Map<String, dynamic>);

/// Copies an export (a folder, its playlist file, or a zip) into the folder
/// [planFor] picks. Songs already there with the same size aren't copied
/// again, so updating a playlist only brings what is new or changed.
Future<ImportResult> importPackage(String source, PlanFor planFor, {TransferProgress? onProgress}) async {
  if (source.toLowerCase().endsWith('.zip')) return _importZip(source, planFor, onProgress);
  final folder = File(source).existsSync() ? p.dirname(source) : source;
  final manifest = File(p.join(folder, manifestName));
  if (!manifest.existsSync()) throw const FormatException('There is no EZTiger playlist export in that folder.');
  final pkg = _parse(manifest.readAsStringSync());
  final plan = await planFor(pkg);
  if (plan == null) throw const TransferCancelled();
  final songs = Directory(p.join(plan.folder, songsFolder))..createSync(recursive: true);
  var done = 0, copied = 0, kept = 0;
  final todo = <String>[];
  for (final name in pkg.fileNames) {
    final from = File(p.join(folder, songsFolder, name));
    if (!from.existsSync()) continue;
    if (_alreadyThere(File(p.join(songs.path, name)), from.lengthSync())) {
      kept++;
    } else {
      todo.add(name);
    }
  }
  final total = todo.fold<int>(0, (a, n) => a + File(p.join(folder, songsFolder, n)).lengthSync());
  for (final name in todo) {
    onProgress?.call(done, total, name);
    final from = File(p.join(folder, songsFolder, name));
    await from.copy(p.join(songs.path, name));
    done += from.lengthSync();
    copied++;
  }
  if (plan.update) _tidy(songs.path, pkg);
  manifest.copySync(p.join(plan.folder, manifestName));
  onProgress?.call(total, total, '');
  return ImportResult(pkg, plan, copied: copied, kept: kept);
}

/// A zip: reads its playlist first, then unpacks the songs straight into
/// place, a file at a time (a big zip never sits in memory). Names that
/// would climb out of the folder ("..") are skipped.
Future<ImportResult> _importZip(String zip, PlanFor planFor, TransferProgress? onProgress) async {
  onProgress?.call(0, 1, p.basename(zip));
  final input = InputFileStream(zip);
  try {
    final archive = ZipDecoder().decodeStream(input);
    List<String> partsOf(ArchiveFile f) => f.name.replaceAll('\\', '/').split('/').where((s) => s.isNotEmpty).toList();
    final manifest = archive.where((f) => f.isFile && partsOf(f).join('/') == manifestName).firstOrNull;
    if (manifest == null) {
      final names = [for (final f in archive) partsOf(f).join('/')];
      throw FormatException('This zip is not an EZTiger playlist export '
          '(it holds ${names.take(4).join(', ')}${names.length > 4 ? '…' : ''}).');
    }
    final bytes = OutputMemoryStream();
    manifest.writeContent(bytes);
    final json = utf8.decode(bytes.getBytes());
    final pkg = _parse(json);
    final plan = await planFor(pkg);
    if (plan == null) throw const TransferCancelled();
    final songs = Directory(p.join(plan.folder, songsFolder))..createSync(recursive: true);
    final entries = [
      for (final f in archive)
        if (f.isFile && partsOf(f).length == 2 && partsOf(f).first == songsFolder && !partsOf(f).contains('..')) f,
    ];
    var copied = 0, kept = 0, done = 0;
    final todo = <ArchiveFile>[];
    for (final f in entries) {
      if (_alreadyThere(File(p.join(songs.path, partsOf(f).last)), f.size)) {
        kept++;
      } else {
        todo.add(f);
      }
    }
    final total = todo.fold<int>(0, (a, f) => a + f.size);
    for (final f in todo) {
      final name = partsOf(f).last;
      final out = OutputFileStream(p.join(songs.path, name));
      try {
        f.writeContent(out);
      } finally {
        out.closeSync();
      }
      done += f.size;
      copied++;
      onProgress?.call(done, total, name);
    }
    if (plan.update) _tidy(songs.path, pkg);
    File(p.join(plan.folder, manifestName)).writeAsStringSync(json);
    onProgress?.call(1, 1, '');
    return ImportResult(pkg, plan, copied: copied, kept: kept);
  } finally {
    input.closeSync();
  }
}

// ------------------------------------------------------------ over Wi-Fi

/// The PC's side of "Send to the tablet over Wi-Fi": serves one playlist's
/// files to whoever has the code, until [stop].
class PlaylistSender {
  PlaylistSender(this.pkg, {this.port = defaultPort, String? code})
      : code = code ?? (1000 + math.Random.secure().nextInt(9000)).toString();

  static const defaultPort = 8085;
  final PlaylistPackage pkg;
  final int port;

  /// The four-digit code the tablet types in.
  final String code;

  HttpServer? _server;

  /// The port it is listening on (the one asked for, or a free one for 0).
  int get boundPort => _server?.port ?? port;

  /// Bytes sent so far, and the file being sent; for the PC's screen.
  int bytesSent = 0;
  String sending = '';

  /// The tablet said it has everything.
  bool finished = false;
  void Function()? onChange;

  // The PC's screen is told at most ten times a second.
  final _clock = Stopwatch()..start();
  var _last = -1000;
  void _changed({bool now = false}) {
    final t = _clock.elapsedMilliseconds;
    if (now || t - _last >= 100) {
      _last = t;
      onChange?.call();
    }
  }

  Future<void> start() async {
    _server = await HttpServer.bind(InternetAddress.anyIPv4, port, shared: true);
    _server!.listen(_handle, onError: (_) {});
  }

  Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
  }

  Future<void> _handle(HttpRequest req) async {
    final res = req.response;
    try {
      if (req.uri.queryParameters['code'] != code) {
        res.statusCode = HttpStatus.forbidden;
        res.write('Wrong code');
      } else if (req.uri.path == '/eztiger/done') {
        // The tablet has it all (songs it already had weren't sent).
        finished = true;
        bytesSent = pkg.totalBytes;
        onChange?.call();
      } else if (req.uri.path == '/eztiger/playlist') {
        // A tablet starting (again): the progress starts over.
        finished = false;
        bytesSent = 0;
        onChange?.call();
        res.headers.contentType = ContentType.json;
        res.write(pkg.toJsonText());
      } else if (req.uri.path == '/eztiger/file') {
        final name = req.uri.queryParameters['name'] ?? '';
        final src = pkg.sources[name];
        if (src == null || !File(src).existsSync()) {
          res.statusCode = HttpStatus.notFound;
        } else {
          sending = name;
          _changed(now: true);
          res.headers.contentType = ContentType.binary;
          res.contentLength = File(src).lengthSync();
          // Streamed in big pieces, at the pace the Wi-Fi takes them.
          await res.addStream(File(src).openRead().map((chunk) {
            bytesSent += chunk.length;
            _changed();
            return chunk;
          }));
          _changed(now: true);
        }
      } else {
        res.statusCode = HttpStatus.notFound;
      }
    } catch (_) {
      // The tablet went away mid-file; it can ask again.
    }
    try {
      await res.close();
    } catch (_) {}
  }
}

/// The tablet's side: fetches the playlist offered by the PC at [host] with
/// [code] into the folder [planFor] picks. Songs already there with the same
/// size aren't fetched again.
Future<ImportResult> receivePackage(String host, String code, PlanFor planFor,
    {int port = PlaylistSender.defaultPort, TransferProgress? onProgress}) async {
  final http = HttpClient()..connectionTimeout = const Duration(seconds: 6);
  try {
    Uri at(String path, [Map<String, String> q = const {}]) =>
        Uri(scheme: 'http', host: host.trim(), port: port, path: path, queryParameters: {'code': code.trim(), ...q});
    final req = await http.getUrl(at('/eztiger/playlist'));
    final res = await req.close();
    final body = await res.transform(utf8.decoder).join();
    if (res.statusCode == HttpStatus.forbidden) throw const TransferException('The code is wrong: check it on the PC.');
    if (res.statusCode != HttpStatus.ok) throw TransferException('The PC answered ${res.statusCode}.');
    final pkg = PlaylistPackage.fromJson(jsonDecode(body) as Map<String, dynamic>);
    final plan = await planFor(pkg);
    if (plan == null) throw const TransferCancelled();
    final songs = Directory(p.join(plan.folder, songsFolder))..createSync(recursive: true);
    var done = 0, copied = 0;
    final todo = [
      for (final name in pkg.fileNames)
        if (!_alreadyThere(File(p.join(songs.path, name)), pkg.sizes[name])) name,
    ];
    final kept = pkg.fileNames.length - todo.length;
    final total = todo.fold<int>(0, (a, n) => a + (pkg.sizes[n] ?? 0));
    final progress = tenASecond(onProgress);
    // Three files at a time, so the Wi-Fi never waits between small files
    // (each song's CDG and lyric sheet).
    final waiting = [...todo];
    Future<void> fetchFiles() async {
      while (waiting.isNotEmpty) {
        final name = waiting.removeAt(0);
        progress?.call(done, total, name);
        final r = await (await http.getUrl(at('/eztiger/file', {'name': name}))).close();
        if (r.statusCode != HttpStatus.ok) {
          await r.drain<void>();
          continue; // gone from the PC: the playlist goes ahead without it
        }
        final part = File(p.join(songs.path, '$name.part'));
        final sink = part.openWrite();
        await for (final chunk in r) {
          sink.add(chunk);
          done += chunk.length;
          progress?.call(done, total, name);
        }
        await sink.close();
        final target = File(p.join(songs.path, name));
        if (target.existsSync()) target.deleteSync();
        part.renameSync(target.path);
        copied++;
      }
    }

    await Future.wait([for (var i = 0; i < math.min(3, todo.length); i++) fetchFiles()]);
    if (plan.update) _tidy(songs.path, pkg);
    File(p.join(plan.folder, manifestName)).writeAsStringSync(pkg.toJsonText());
    try {
      await (await (await http.getUrl(at('/eztiger/done'))).close()).drain<void>();
    } catch (_) {
      // Only the PC's screen misses out.
    }
    onProgress?.call(total, total, '');
    return ImportResult(pkg, plan, copied: copied, kept: kept);
  } on SocketException {
    throw TransferException("Can't reach the PC at $host. Is it on the same Wi-Fi, with Send to tablet open?");
  } finally {
    http.close(force: true);
  }
}

class TransferException implements Exception {
  const TransferException(this.message);
  final String message;
  @override
  String toString() => message;
}

// ------------------------------------------------- back from the tablet

/// The tablet's playlist as a list (running order and keys, no song files),
/// for sending back to the PC. [keyShifts]: song path → semitones.
Future<Map<String, Object?>> playlistBack(EztigerDatabase db, Playlist pl, Map<String, int> keyShifts) async => {
      'eztiger_back': 1,
      'name': pl.name,
      'songs': [
        for (final t in await db.playlists.tracks(pl.id))
          {
            'file': t.fileName,
            'title': t.title,
            if (t.artist != null) 'artist': t.artist,
            if ((keyShifts[t.path] ?? 0) != 0) 'key': keyShifts[t.path],
          },
      ],
    };

/// The tablet's side of "Send back to the PC": hands [list] (from
/// [playlistBack]) to the PC at [host], waiting in "Receive from the tablet"
/// with [code].
Future<void> sendPlaylistBack(String host, String code, Map<String, Object?> list,
    {int port = PlaylistSender.defaultPort}) async {
  final http = HttpClient()..connectionTimeout = const Duration(seconds: 6);
  try {
    final req = await http.postUrl(
        Uri(scheme: 'http', host: host.trim(), port: port, path: '/eztiger/back', queryParameters: {'code': code.trim()}));
    req.headers.contentType = ContentType.json;
    req.write(jsonEncode(list));
    final res = await req.close();
    await res.drain<void>();
    if (res.statusCode == HttpStatus.forbidden) throw const TransferException('The code is wrong: check it on the PC.');
    if (res.statusCode != HttpStatus.ok) throw TransferException('The PC answered ${res.statusCode}.');
  } on SocketException {
    throw TransferException("Can't reach the PC at $host. Is it on the same Wi-Fi, with Receive from the tablet open?");
  } finally {
    http.close(force: true);
  }
}

/// The PC's side: waits, with a four-digit code, for the tablet to send a
/// playlist back. [onReceived] gets it (the list from [playlistBack]).
class PlaylistCatcher {
  PlaylistCatcher({this.port = PlaylistSender.defaultPort, String? code})
      : code = code ?? (1000 + math.Random.secure().nextInt(9000)).toString();

  final int port;
  final String code;
  void Function(Map<String, dynamic> list)? onReceived;

  HttpServer? _server;
  int get boundPort => _server?.port ?? port;

  Future<void> start() async {
    _server = await HttpServer.bind(InternetAddress.anyIPv4, port, shared: true);
    _server!.listen(_handle, onError: (_) {});
  }

  Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
  }

  Future<void> _handle(HttpRequest req) async {
    final res = req.response;
    try {
      if (req.uri.queryParameters['code'] != code) {
        res.statusCode = HttpStatus.forbidden;
        res.write('Wrong code');
      } else if (req.method == 'POST' && req.uri.path == '/eztiger/back') {
        final m = jsonDecode(await utf8.decoder.bind(req).join()) as Map<String, dynamic>;
        if (m['eztiger_back'] == null || m['songs'] is! List) {
          res.statusCode = HttpStatus.badRequest;
        } else {
          res.write('{"ok":true}');
          onReceived?.call(m);
        }
      } else {
        res.statusCode = HttpStatus.notFound;
      }
    } catch (_) {
      try {
        res.statusCode = HttpStatus.badRequest; // not a playlist
      } catch (_) {}
    }
    try {
      await res.close();
    } catch (_) {}
  }
}
