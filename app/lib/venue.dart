import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'promos.dart';

/// Venue branding for EZTiger karaoke: the same venues Music Bingo and Quiz
/// Night use, kept in Documents\EZTiger Venues (see promos.dart):
///
///     EZTiger Venues\
///         active.json          {"venue": "Hotel Costa Azul", "on": true}
///         apps.json            which EZTiger apps use these venues on this PC
///         Hotel Costa Azul\
///             venue.json       {"name", "tagline", "colour", "logo", "photos": [...]}
///             logo.png  photo-1.jpg …
///             promos.json      the promo slides, pictures in promos\
///
/// EZTiger karaoke works on its own: it makes the folder when it's missing.
/// When bingo or quiz is on this PC as well they share the venues, so choosing
/// one in any app chooses it in all of them.
class Venue {
  Venue({required this.id, required this.name, this.tagline = '', this.colour = defaultColour, this.logo = '', this.photos = const [], required this.dir});
  final String id, name, tagline, colour, logo;
  final List<String> photos;

  /// The venue's folder.
  final String dir;

  static const defaultColour = '#0c6f8a';

  String? get logoPath => logo.isEmpty ? null : '$dir${Platform.pathSeparator}$logo';
  List<String> get photoPaths => [for (final p in photos) '$dir${Platform.pathSeparator}$p'];

  /// The colour as a number (0xFFrrggbb).
  int get colourValue => 0xFF000000 | int.parse(colour.substring(1), radix: 16);
}

class VenueResult {
  const VenueResult(this.ok, [this.error = '', this.venue]);
  final bool ok;
  final String error;
  final Venue? venue;
}

/// An EZTiger app on this PC that shares the venues.
class EzApp {
  const EzApp({required this.key, required this.name, this.version = '', this.path = '', this.seen});
  final String key, name, version, path;

  /// When it last opened (from apps.json); null when it was only found installed.
  final DateTime? seen;
}

/// The three apps, and where each is usually installed.
const ezAppNames = {
  'karaoke': 'EZTiger Pro karaoke',
  'bingo': 'Music Bingo',
  'quiz': 'EZTiger Quiz Night',
};

const _imageTypes = {'.png', '.jpg', '.jpeg', '.webp', '.gif'};
const maxVenuePhotos = 3;
const maxVenueImage = 15 * 1024 * 1024;
const promoThemeNames = {
  'cocktails': '🍸 Cocktails',
  'food': '🍔 Food',
  'activity': '🎯 Activity',
  'pints': '🍺 Pints',
  'tiger': '🐯 Tiger',
};

String _clean(Object? text, [int n = 60]) {
  final s = '${text ?? ''}'.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).join(' ');
  return s.length > n ? s.substring(0, n) : s;
}

String cleanColour(Object? c) {
  final s = '${c ?? ''}'.trim();
  return RegExp(r'^#[0-9a-fA-F]{6}$').hasMatch(s) ? s.toLowerCase() : Venue.defaultColour;
}

class VenueStore {
  VenueStore([String? root]) : root = root ?? venuesFolder() ?? '';

  /// Documents\EZTiger Venues; '' where there is none (Android).
  final String root;
  bool get available => root.isNotEmpty;
  String get _sep => Platform.pathSeparator;
  String _dir(String id) => '$root$_sep${venueFolderName(id)}';

  Object? _read(String path) {
    try {
      return jsonDecode(File(path).readAsStringSync());
    } catch (_) {
      return null;
    }
  }

  void _write(String path, Object data) {
    final f = File(path);
    f.parent.createSync(recursive: true);
    final tmp = File('$path.tmp')..writeAsStringSync(const JsonEncoder.withIndent(' ').convert(data));
    if (f.existsSync()) f.deleteSync();
    tmp.renameSync(path);
  }

  Map<String, dynamic> _map(String path) {
    final j = _read(path);
    return j is Map<String, dynamic> ? j : <String, dynamic>{};
  }

  Venue? read(String id) {
    if (!available || id.isEmpty) return null;
    final d = _dir(id);
    final data = _read('$d${_sep}venue.json');
    if (data is! Map) return null;
    bool has(Object? f) => f is String && f.isNotEmpty && !f.contains(RegExp(r'[\\/]')) && File('$d$_sep$f').existsSync();
    final name = venueFolderName(id);
    return Venue(
      id: name,
      name: _clean(data['name']).isEmpty ? name : _clean(data['name']),
      tagline: _clean(data['tagline'], 90),
      colour: cleanColour(data['colour']),
      logo: has(data['logo']) ? data['logo'] as String : '',
      photos: [for (final p in (data['photos'] is List ? data['photos'] as List : const [])) if (has(p)) p as String].take(maxVenuePhotos).toList(),
      dir: d,
    );
  }

  List<Venue> list() {
    if (!available || !Directory(root).existsSync()) return [];
    final dirs = Directory(root).listSync().whereType<Directory>().toList()
      ..sort((a, b) => _base(a.path).toLowerCase().compareTo(_base(b.path).toLowerCase()));
    return [for (final d in dirs) ?read(_base(d.path))];
  }

  String _base(String path) => path.split(RegExp(r'[\\/]')).where((s) => s.isNotEmpty).last;

  /// The chosen venue and whether branding is on.
  ({String venue, bool on}) activeSetting() {
    final a = _map('$root${_sep}active.json');
    return (venue: '${a['venue'] ?? ''}', on: a['on'] == true);
  }

  /// The venue to show on the screens, or null when branding is off.
  Venue? active() {
    final a = activeSetting();
    return a.on && a.venue.isNotEmpty ? read(a.venue) : null;
  }

  VenueResult setActive(String id, bool on) {
    final v = id.isEmpty ? '' : venueFolderName(id);
    if (v.isNotEmpty && read(v) == null) return const VenueResult(false, 'That venue no longer exists.');
    _write('$root${_sep}active.json', {'venue': v, 'on': on && v.isNotEmpty});
    return VenueResult(true, '', v.isEmpty ? null : read(v));
  }

  /// Creates a venue, or updates it ([id] is its folder; renaming moves it).
  VenueResult save({String? id, required String name, String tagline = '', String colour = Venue.defaultColour}) {
    final n = _clean(name);
    if (n.isEmpty) return const VenueResult(false, 'Give the venue a name.');
    final old = id == null || id.isEmpty ? null : venueFolderName(id);
    final neu = venueFolderName(n);
    Directory(root).createSync(recursive: true);
    if (old != null && old != neu && Directory(_dir(old)).existsSync()) {
      if (Directory(_dir(neu)).existsSync() && old.toLowerCase() != neu.toLowerCase()) {
        return VenueResult(false, 'There is already a venue called $neu.');
      }
      Directory(_dir(old)).renameSync(_dir(neu));
      final a = activeSetting();
      if (a.venue == old) _write('$root${_sep}active.json', {'venue': neu, 'on': a.on});
    }
    final cur = _map('$root$_sep$neu${_sep}venue.json');
    cur['name'] = n;
    cur['tagline'] = _clean(tagline, 90);
    cur['colour'] = cleanColour(colour);
    cur.putIfAbsent('logo', () => '');
    cur.putIfAbsent('photos', () => <String>[]);
    _write('$root$_sep$neu${_sep}venue.json', cur);
    return VenueResult(true, '', read(neu));
  }

  String _ext(String path) {
    final dot = path.lastIndexOf('.');
    return dot < 0 ? '' : path.substring(dot).toLowerCase();
  }

  /// Copies a picture in as the venue's logo, or one of its photos.
  VenueResult addImage(String id, {required bool logo, required String from}) {
    final ext = _ext(from);
    if (!_imageTypes.contains(ext)) return const VenueResult(false, 'Use a PNG, JPG, WebP or GIF picture.');
    final src = File(from);
    if (!src.existsSync() || src.lengthSync() == 0 || src.lengthSync() > maxVenueImage) {
      return const VenueResult(false, 'That picture is empty or over 15 MB.');
    }
    final d = _dir(id);
    final cur = _read('$d${_sep}venue.json');
    if (cur is! Map<String, dynamic>) return const VenueResult(false, 'Save the venue first.');
    final photos = [for (final p in (cur['photos'] as List? ?? const [])) if (File('$d$_sep$p').existsSync()) '$p'];
    String name;
    if (logo) {
      final was = '${cur['logo'] ?? ''}';
      if (was.isNotEmpty) _remove('$d$_sep$was');
      name = 'logo$ext';
      cur['logo'] = name;
    } else {
      if (photos.length >= maxVenuePhotos) return const VenueResult(false, 'A venue can have $maxVenuePhotos photos. Remove one first.');
      var n = 1;
      while (photos.any((p) => p.startsWith('photo-$n.'))) {
        n++;
      }
      name = 'photo-$n$ext';
      photos.add(name);
    }
    cur['photos'] = photos;
    src.copySync('$d$_sep$name');
    _write('$d${_sep}venue.json', cur);
    return VenueResult(true, '', read(id));
  }

  void _remove(String path) {
    try {
      File(path).deleteSync();
    } catch (_) {}
  }

  VenueResult removeImage(String id, String file) {
    final d = _dir(id);
    final cur = _read('$d${_sep}venue.json');
    if (cur is! Map<String, dynamic>) return const VenueResult(false);
    if (cur['logo'] == file) cur['logo'] = '';
    cur['photos'] = [for (final p in (cur['photos'] as List? ?? const [])) if (p != file) p];
    if (!file.contains(RegExp(r'[\\/]'))) _remove('$d$_sep$file');
    _write('$d${_sep}venue.json', cur);
    return VenueResult(true, '', read(id));
  }

  /// Deletes a venue's folder (and switches branding off if it was chosen).
  void delete(String id) {
    final d = Directory(_dir(id));
    if (d.existsSync() && d.parent.path == Directory(root).path) d.deleteSync(recursive: true);
    if (activeSetting().venue == venueFolderName(id)) _write('$root${_sep}active.json', {'venue': '', 'on': false});
  }

  // ------------------------------------------------------------------ promos

  /// The folder holding the promos in use: the chosen venue's, or `_promos`.
  String promoDir() {
    final v = activeSetting().venue;
    return v.isNotEmpty && read(v) != null ? _dir(v) : '$root${_sep}_promos';
  }

  /// promos.json as it is on disk (settings and every slide, shown or hidden).
  Map<String, dynamic> readPromoFile() {
    final j = _map('${promoDir()}${_sep}promos.json');
    j['slides'] = [for (final s in (j['slides'] as List? ?? const [])) if (s is Map) Map<String, dynamic>.from(s)];
    return j;
  }

  void savePromoFile(Map<String, dynamic> data) {
    final d = promoDir();
    final cur = _map('$d${_sep}promos.json')..addAll(data);
    int n(Object? v, int lo, int hi, int def) => v is num ? v.toInt().clamp(lo, hi) : def;
    cur['on'] = cur['on'] != false;
    cur['seconds'] = n(cur['seconds'], 3, 60, 8);
    cur['gap'] = n(cur['gap'], 3, 120, 12);
    cur['mix'] = cur['mix'] == 'full' ? 'full' : 'turns';
    _write('$d${_sep}promos.json', cur);
  }

  String _id(String prefix) => '$prefix-${math.Random().nextInt(1 << 24).toRadixString(16).padLeft(6, '0')}';

  /// Adds a text slide; returns its id.
  String addTextPromo({String top = '', String main = '', String detail = '', String theme = 'cocktails'}) {
    final j = readPromoFile();
    final id = _id('txt');
    (j['slides'] as List).add({
      'id': id,
      'kind': 'text',
      'top': _clean(top, 40),
      'main': _clean(main, 48),
      'detail': _clean(detail, 70),
      'theme': promoThemeNames.containsKey(theme) ? theme : 'cocktails',
      'on': true,
    });
    savePromoFile(j);
    return id;
  }

  /// Copies a poster or photo in as a picture slide.
  VenueResult addPromoImage(String from) {
    final ext = _ext(from);
    if (!_imageTypes.contains(ext)) return const VenueResult(false, 'Use a PNG, JPG, WebP or GIF picture.');
    final src = File(from);
    if (!src.existsSync() || src.lengthSync() == 0 || src.lengthSync() > maxVenueImage) {
      return const VenueResult(false, 'That picture is empty or over 15 MB.');
    }
    final pics = Directory('${promoDir()}${_sep}promos')..createSync(recursive: true);
    var n = 1;
    while (File('${pics.path}${_sep}promo-$n$ext').existsSync()) {
      n++;
    }
    src.copySync('${pics.path}${_sep}promo-$n$ext');
    final j = readPromoFile();
    (j['slides'] as List).add({'id': _id('img$n'), 'kind': 'image', 'file': 'promo-$n$ext', 'on': true});
    savePromoFile(j);
    return const VenueResult(true);
  }

  void removePromo(String id) {
    final j = readPromoFile();
    final slides = j['slides'] as List;
    for (final s in slides.where((s) => s['id'] == id).toList()) {
      if (s['kind'] == 'image') _remove('${promoDir()}${_sep}promos$_sep${s['file']}');
      slides.remove(s);
    }
    savePromoFile(j);
  }

  // ------------------------------------------------------------- the apps

  /// Says this app is on this PC (apps.json), so bingo and quiz can see it.
  void registerApp(String key, {String version = '', String? path, DateTime? now}) {
    if (!available) return;
    try {
      final j = _map('$root${_sep}apps.json');
      final apps = j['apps'] is Map ? Map<String, dynamic>.from(j['apps'] as Map) : <String, dynamic>{};
      apps[key] = {
        'name': ezAppNames[key] ?? key,
        'version': version,
        'path': path ?? Platform.resolvedExecutable,
        'seen': (now ?? DateTime.now()).toUtc().toIso8601String(),
      };
      _write('$root${_sep}apps.json', {'apps': apps});
    } catch (_) {
      // A read-only Documents folder: the venues still work.
    }
  }

  /// The EZTiger apps on this PC: those that have opened (apps.json), and those
  /// found installed in the usual places but not opened since they could say so.
  List<EzApp> apps({Map<String, String>? env}) {
    final out = <String, EzApp>{};
    final j = available ? _map('$root${_sep}apps.json') : <String, dynamic>{};
    if (j['apps'] is Map) {
      (j['apps'] as Map).forEach((k, v) {
        if (v is! Map) return;
        final path = '${v['path'] ?? ''}';
        if (path.isNotEmpty && !File(path).existsSync()) return; // uninstalled since
        out['$k'] = EzApp(
          key: '$k',
          name: '${v['name'] ?? ezAppNames[k] ?? k}',
          version: '${v['version'] ?? ''}',
          path: path,
          seen: DateTime.tryParse('${v['seen'] ?? ''}'),
        );
      });
    }
    installedPaths(env ?? Platform.environment).forEach((k, path) {
      out.putIfAbsent(k, () => EzApp(key: k, name: ezAppNames[k]!, path: path));
    });
    return [for (final k in ezAppNames.keys) ?out[k]];
  }

  /// Where each app is usually installed (Windows), for those found there.
  static Map<String, String> installedPaths(Map<String, String> env) {
    if (!Platform.isWindows) return {};
    final home = env['USERPROFILE'] ?? '';
    final start = '${env['APPDATA'] ?? ''}\\Microsoft\\Windows\\Start Menu\\Programs';
    final places = {
      'karaoke': [
        '${env['ProgramFiles'] ?? r'C:\Program Files'}\\EZtiger\\eztiger.exe',
        '${env['ProgramFiles(x86)'] ?? r'C:\Program Files (x86)'}\\EZtiger\\eztiger.exe',
      ],
      'bingo': [
        '$home\\Downloads\\Music Bingo\\Music Bingo.exe',
        '$start\\Music Bingo.lnk',
        '$home\\Desktop\\Music Bingo.lnk',
      ],
      'quiz': [
        '$home\\Downloads\\EZTiger Quiz\\EZTiger Quiz.exe',
        '$start\\EZTiger Quiz.lnk',
        '$home\\Desktop\\EZTiger Quiz.lnk',
      ],
    };
    final found = <String, String>{};
    places.forEach((k, paths) {
      for (final p in paths) {
        if (home.isNotEmpty && File(p).existsSync()) {
          found[k] = p;
          break;
        }
      }
    });
    return found;
  }
}
