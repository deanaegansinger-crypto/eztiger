import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:archive/archive_io.dart';
import 'package:eztiger_core/eztiger_core.dart';
import 'package:path/path.dart' as p;

/// Taking a playlist, and the song files themselves, from EZTiger Pro on the
/// PC to the tablet: as a folder or one zip (for a USB stick, an SD card or
/// Dropbox), or straight over the Wi-Fi. The tablet copies every song into
/// its "EZTiger imports" folder and makes the playlist again, keys and all.
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
    final target = File(p.join(songs.path, name));
    final sink = target.openWrite();
    await for (final chunk in File(pkg.sources[name]!).openRead()) {
      sink.add(chunk);
      done += chunk.length;
      onProgress?.call(done, total, name);
    }
    await sink.close();
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

/// Where an imported playlist's songs go, once its name is known.
typedef DestinationFor = String Function(PlaylistPackage pkg);

/// Copies an export (a folder, its playlist file, or a zip) into a folder of
/// its own ([destFor]) and returns what it holds and where it went. The
/// songs end up in that folder's songs folder. Every song is copied, even
/// one already on this device.
Future<(PlaylistPackage, String)> importPackage(String source, DestinationFor destFor,
    {required String workDir, TransferProgress? onProgress}) async {
  if (source.toLowerCase().endsWith('.zip')) {
    onProgress?.call(0, 1, p.basename(source));
    // Straight from the zip to disk, a file at a time, then moved into place
    // once the playlist's name is known.
    final incoming = Directory(p.join(workDir, '.incoming-${DateTime.now().millisecondsSinceEpoch}'))
      ..createSync(recursive: true);
    final names = _unzip(source, incoming.path, onProgress);
    final manifest = File(p.join(incoming.path, manifestName));
    if (!manifest.existsSync()) {
      incoming.deleteSync(recursive: true);
      throw FormatException('This zip is not an EZTiger playlist export '
          '(it holds ${names.take(4).join(', ')}${names.length > 4 ? '…' : ''}).');
    }
    final pkg = PlaylistPackage.fromJson(jsonDecode(manifest.readAsStringSync()) as Map<String, dynamic>);
    final dest = destFor(pkg);
    if (Directory(dest).existsSync()) Directory(dest).deleteSync(recursive: true);
    Directory(p.dirname(dest)).createSync(recursive: true);
    incoming.renameSync(dest);
    onProgress?.call(1, 1, '');
    return (pkg, dest);
  }
  final folder = File(source).existsSync() ? p.dirname(source) : source;
  final manifest = File(p.join(folder, manifestName));
  if (!manifest.existsSync()) throw const FormatException('There is no EZTiger playlist export in that folder.');
  final pkg = PlaylistPackage.fromJson(jsonDecode(manifest.readAsStringSync()) as Map<String, dynamic>);
  final destDir = destFor(pkg);
  final songs = Directory(p.join(destDir, songsFolder))..createSync(recursive: true);
  var done = 0;
  final total = pkg.fileNames.fold<int>(0, (a, n) {
    final f = File(p.join(folder, songsFolder, n));
    return a + (f.existsSync() ? f.lengthSync() : 0);
  });
  for (final name in pkg.fileNames) {
    final from = File(p.join(folder, songsFolder, name));
    if (!from.existsSync()) continue;
    final sink = File(p.join(songs.path, name)).openWrite();
    await for (final chunk in from.openRead()) {
      sink.add(chunk);
      done += chunk.length;
      onProgress?.call(done, total, name);
    }
    await sink.close();
  }
  manifest.copySync(p.join(destDir, manifestName));
  onProgress?.call(total, total, '');
  return (pkg, destDir);
}

/// Unpacks [zip] into [dir], a file at a time (a big zip never sits in
/// memory), and returns the names in it. Names that would climb out of
/// [dir] ("..") are skipped.
List<String> _unzip(String zip, String dir, TransferProgress? onProgress) {
  final input = InputFileStream(zip);
  final names = <String>[];
  try {
    final archive = ZipDecoder().decodeStream(input);
    final total = archive.where((f) => f.isFile).fold<int>(0, (a, f) => a + f.size);
    var done = 0;
    for (final f in archive) {
      final parts = f.name.replaceAll('\\', '/').split('/').where((s) => s.isNotEmpty).toList();
      if (parts.isEmpty || parts.contains('..')) continue;
      names.add(parts.join('/'));
      if (!f.isFile) continue;
      final out = File(p.joinAll([dir, ...parts]));
      out.parent.createSync(recursive: true);
      final stream = OutputFileStream(out.path);
      try {
        f.writeContent(stream);
      } finally {
        stream.closeSync();
      }
      done += f.size;
      onProgress?.call(done, total, parts.last);
    }
  } finally {
    input.closeSync();
  }
  return names;
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
  void Function()? onChange;

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
      } else if (req.uri.path == '/eztiger/playlist') {
        res.headers.contentType = ContentType.json;
        res.write(pkg.toJsonText());
      } else if (req.uri.path == '/eztiger/file') {
        final name = req.uri.queryParameters['name'] ?? '';
        final src = pkg.sources[name];
        if (src == null || !File(src).existsSync()) {
          res.statusCode = HttpStatus.notFound;
        } else {
          sending = name;
          onChange?.call();
          res.headers.contentType = ContentType.binary;
          res.contentLength = File(src).lengthSync();
          await for (final chunk in File(src).openRead()) {
            res.add(chunk);
            bytesSent += chunk.length;
          }
          onChange?.call();
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
/// [code], copying every song into its own folder ([destFor]) and returning
/// what it holds and where it went.
Future<(PlaylistPackage, String)> receivePackage(String host, String code, DestinationFor destFor,
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
    final destDir = destFor(pkg);
    final songs = Directory(p.join(destDir, songsFolder))..createSync(recursive: true);
    var done = 0;
    final total = pkg.totalBytes;
    for (final name in pkg.fileNames) {
      onProgress?.call(done, total, name);
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
        onProgress?.call(done, total, name);
      }
      await sink.close();
      final target = File(p.join(songs.path, name));
      if (target.existsSync()) target.deleteSync();
      part.renameSync(target.path);
    }
    File(p.join(destDir, manifestName)).writeAsStringSync(pkg.toJsonText());
    onProgress?.call(total, total, '');
    return (pkg, destDir);
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
