import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// Promo slides between acts: the venue's food, drink and activity offers on
/// the second screen between singers.
///
/// They are the same slides Music Bingo and Quiz Night show, kept in
/// Documents\EZTiger Venues: the chosen venue's `promos.json` (pictures in its
/// `promos` folder), or `_promos` when no venue is chosen. Those apps have the
/// manager for adding and ordering them; EZTiger reads the same files.
class PromoSlide {
  PromoSlide({required this.id, required this.kind, this.file, this.top = '', this.main = '', this.detail = '', this.theme = 'cocktails'});
  final String id, kind;
  final String? file;
  final String top, main, detail, theme;

  static PromoSlide? fromJson(Object? j) {
    if (j is! Map) return null;
    if (j['on'] == false) return null;
    final id = '${j['id'] ?? ''}';
    if (id.isEmpty) return null;
    if (j['kind'] == 'image') {
      final f = '${j['file'] ?? ''}';
      return f.isEmpty ? null : PromoSlide(id: id, kind: 'image', file: f);
    }
    final s = PromoSlide(id: id, kind: 'text', top: '${j['top'] ?? ''}', main: '${j['main'] ?? ''}', detail: '${j['detail'] ?? ''}', theme: '${j['theme'] ?? 'cocktails'}');
    return (s.top + s.main + s.detail).trim().isEmpty ? null : s;
  }
}

class PromoSet {
  PromoSet({this.on = false, this.seconds = 8, this.gap = 12, this.full = false, this.slides = const [], this.folder = ''});
  final bool on, full;
  final int seconds, gap;
  final List<PromoSlide> slides;

  /// Where the pictures are (the set's `promos` folder).
  final String folder;

  bool get usable => on && slides.isNotEmpty;
  String get key => '$on|$seconds|$gap|$full|$folder|${slides.map((s) => '${s.id}:${s.file}:${s.top}:${s.main}:${s.detail}:${s.theme}').join(',')}';
}

/// Documents\EZTiger Venues (EZ_VENUES overrides it, as in the other apps). Null where there is no such place (Android).
String? venuesFolder() {
  final env = Platform.environment;
  if (env['EZ_VENUES']?.isNotEmpty == true) return env['EZ_VENUES'];
  final home = env['USERPROFILE'] ?? env['HOME'];
  if (home == null || !Platform.isWindows) return null;
  return '$home${Platform.pathSeparator}Documents${Platform.pathSeparator}EZTiger Venues';
}

/// The same Windows-safe folder name the other apps give a venue.
String venueFolderName(String name) {
  var s = name.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).join(' ');
  if (s.length > 60) s = s.substring(0, 60);
  s = s.replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1f]'), '');
  s = s.replaceAll(RegExp(r'^[ .]+|[ .]+$'), '');
  return s.isEmpty ? 'Venue' : s;
}

Map<String, dynamic>? _readJson(String path) {
  try {
    final j = jsonDecode(File(path).readAsStringSync());
    return j is Map<String, dynamic> ? j : null;
  } catch (_) {
    return null;
  }
}

/// Reads the promos in use now; an empty, switched-off set if there are none.
PromoSet readPromos([String? venues]) {
  final root = venues ?? venuesFolder();
  if (root == null) return PromoSet();
  final sep = Platform.pathSeparator;
  var dir = '$root${sep}_promos';
  final venue = '${_readJson('$root${sep}active.json')?['venue'] ?? ''}';
  if (venue.isNotEmpty) {
    final d = '$root$sep${venueFolderName(venue)}';
    if (File('$d${sep}venue.json').existsSync()) dir = d;
  }
  final j = _readJson('$dir${sep}promos.json');
  if (j == null) return PromoSet();
  final pics = '$dir${sep}promos';
  final slides = <PromoSlide>[];
  for (final s in (j['slides'] as List? ?? const [])) {
    final p = PromoSlide.fromJson(s);
    if (p == null) continue;
    if (p.kind == 'image' && !File('$pics$sep${p.file}').existsSync()) continue;
    slides.add(p);
  }
  int n(Object? v, int lo, int hi, int d) => v is num ? v.toInt().clamp(lo, hi) : d;
  return PromoSet(
    on: j['on'] != false,
    seconds: n(j['seconds'], 3, 60, 8),
    gap: n(j['gap'], 3, 120, 12),
    full: j['mix'] == 'full',
    slides: slides,
    folder: pics,
  );
}

/// Decides when a slide shows: between acts the slides take turns with the
/// normal idle screen (slide, idle screen, next slide…), or fill the screen.
class PromoPlayer extends ChangeNotifier {
  PromoPlayer({this.read = readPromos, this.now = _now});
  final PromoSet Function([String? venues]) read;
  final DateTime Function() now;
  static DateTime _now() => DateTime.now();

  PromoSet set = PromoSet();
  PromoSlide? showing;
  int _index = -1;
  String _phase = 'off';
  DateTime _until = DateTime(0);
  Timer? _tick, _reload;

  void start() {
    reload();
    _reload = Timer.periodic(const Duration(seconds: 10), (_) => reload());
  }

  void reload() {
    try {
      final s = read();
      if (s.key != set.key) {
        set = s;
        _index = -1;
        if (showing != null) _next();
      }
    } catch (_) {}
  }

  /// Call often (every 250 ms) with whether it is between acts now.
  void update(bool between) {
    final t = now();
    if (!between || !set.usable) {
      _phase = 'off';
      _show(null);
      return;
    }
    final full = set.full;
    if (_phase == 'off') {
      // Just became between acts: in turns mode the idle screen (up next, singer) shows first.
      _phase = full ? 'slide' : 'gap';
      _until = t.add(Duration(seconds: full ? set.seconds : set.gap.clamp(3, 6)));
      if (full) _next();
      return;
    }
    if (t.isBefore(_until)) return;
    if (_phase == 'slide' && !full) {
      _phase = 'gap';
      _until = t.add(Duration(seconds: set.gap));
      _show(null);
    } else {
      _phase = 'slide';
      _until = t.add(Duration(seconds: set.seconds));
      _next();
    }
  }

  void _next() {
    if (set.slides.isEmpty) return _show(null);
    _index = (_index + 1) % set.slides.length;
    _show(set.slides[_index]);
  }

  void _show(PromoSlide? s) {
    if (identical(s, showing)) return;
    showing = s;
    notifyListeners();
  }

  void run(bool Function() between) {
    _tick?.cancel();
    _tick = Timer.periodic(const Duration(milliseconds: 250), (_) => update(between()));
  }

  @override
  void dispose() {
    _tick?.cancel();
    _reload?.cancel();
    super.dispose();
  }
}

/// The colours of each kind of text slide (the same as in the other apps).
const promoThemes = <String, List<Color>>{
  'cocktails': [Color(0xFFFF5FA2), Color(0xFF7B2CBF), Color(0xFF240046)],
  'food': [Color(0xFFFFB347), Color(0xFFE2521D), Color(0xFF5A1A07)],
  'activity': [Color(0xFF55E6FF), Color(0xFF0077B6), Color(0xFF03045E)],
  'pints': [Color(0xFFFFD166), Color(0xFFD48B00), Color(0xFF3D2600)],
  'tiger': [Color(0xFFFF9A3D), Color(0xFFC4560B), Color(0xFF1A0D02)],
};

/// One slide, drawn on a 1920×1080 stage scaled to fit the window.
class PromoSlideView extends StatelessWidget {
  const PromoSlideView({super.key, required this.slide, required this.folder});
  final PromoSlide slide;
  final String folder;

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: Colors.black,
    child: Center(
      child: FittedBox(
        child: SizedBox(width: 1920, height: 1080, child: slide.kind == 'image' ? _image() : _text()),
      ),
    ),
  );

  Widget _image() {
    final f = File('$folder${Platform.pathSeparator}${slide.file}');
    return Stack(
      fit: StackFit.expand,
      children: [
        ImageFiltered(
          imageFilter: ui.ImageFilter.blur(sigmaX: 36, sigmaY: 36),
          child: ColorFiltered(
            colorFilter: const ColorFilter.mode(Color(0x8C000000), BlendMode.darken),
            child: Image.file(f, fit: BoxFit.cover),
          ),
        ),
        Image.file(f, fit: BoxFit.contain),
      ],
    );
  }

  Widget _text() {
    final c = promoThemes[slide.theme] ?? promoThemes['cocktails']!;
    const shadow = [Shadow(color: Color(0x59000000), blurRadius: 30, offset: Offset(0, 6))];
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: RadialGradient(center: const Alignment(-0.4, -0.6), radius: 1.1, colors: c, stops: const [0, 0.55, 1]),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 120, vertical: 80),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (slide.top.isNotEmpty)
              Text(slide.top, textAlign: TextAlign.center,
                  style: const TextStyle(fontFamily: 'Segoe Script', fontFamilyFallback: ['Brush Script MT'], fontSize: 96,
                      fontStyle: FontStyle.italic, color: Color(0xFFFFE08A), shadows: shadow)),
            if (slide.main.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 18),
                child: Text(slide.main, textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 150, height: 1.02, fontWeight: FontWeight.w900, fontStyle: FontStyle.italic,
                        color: Colors.white, shadows: shadow)),
              ),
            if (slide.detail.isNotEmpty)
              Text(slide.detail.toUpperCase(), textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 54, fontWeight: FontWeight.w700, letterSpacing: 4, color: Colors.white)),
          ],
        ),
      ),
    );
  }
}
