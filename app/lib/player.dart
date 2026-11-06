import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:ui' as ui;

import 'package:archive/archive_io.dart';
import 'package:eztiger_core/eztiger_core.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

/// What the karaoke engine needs from an audio/video player. The real one
/// is media_kit (libmpv); tests use a fake.
abstract class MediaBackend {
  /// Opens [path] paused, at [start] if given.
  Future<void> open(String path, {Duration? start});
  Future<void> play();
  Future<void> pause();
  Future<void> stop();
  Future<void> seek(Duration to);

  /// 0-100.
  Future<void> setVolume(double volume);
  Stream<Duration> get position;
  Stream<Duration> get duration;
  Stream<bool> get playing;
  Stream<bool> get completed;
  Future<void> dispose();
}

/// Plays one track at a time: the audio or video through [MediaBackend],
/// and for CDG karaoke the lyrics screen, kept in step with the audio
/// position.
class KaraokeEngine extends ChangeNotifier {
  KaraokeEngine(this.backend, {Future<AudioEdges?> Function(String path)? scanEdges, String? tempDir})
    : scanEdges = scanEdges ?? _scanInIsolate,
      tempDir = tempDir ?? Directory.systemTemp.path {
    _subs = [
      backend.position.listen(_onPosition),
      backend.duration.listen((d) {
        duration = d;
        notifyListeners();
      }),
      backend.playing.listen((v) {
        playing = v;
        notifyListeners();
      }),
      backend.completed.listen((done) {
        if (done && current != null) onFinished?.call();
      }),
    ];
  }

  final MediaBackend backend;

  /// Where zipped MP3+G songs are unpacked (the app's cache folder on
  /// Android, which has no usable system temp folder).
  final String tempDir;

  /// Finds where the music starts and ends in a file (see [findAudioEdges]).
  final Future<AudioEdges?> Function(String path) scanEdges;
  static Future<AudioEdges?> _scanInIsolate(String path) => Isolate.run(() => findAudioEdges(path));
  final Map<String, AudioEdges?> _edgeCache = {};

  /// Where the music starts and ends in the loaded song, when known.
  AudioEdges? edges;

  /// Where the song was cued: its first sound when the silence at the start
  /// was skipped, otherwise the very start. ⏮ goes back here.
  Duration cueStart = Duration.zero;

  /// The end of the music, before any silence at the end of the file.
  Duration get audioEnd {
    final end = edges?.end;
    if (end == null || duration == Duration.zero) return duration;
    return end < duration ? end : duration;
  }

  late final List<StreamSubscription<Object?>> _subs;

  Track? current;
  String? singer;
  Duration position = Duration.zero;
  Duration duration = Duration.zero;
  bool playing = false;
  double volume = 80;
  bool muted = false;
  String? error;

  /// Called when the current track plays to the end.
  VoidCallback? onFinished;

  CdgDecoder? _cdg;
  bool _rendering = false;

  /// The CDG lyrics screen (300x216), or null when the track has none.
  final ValueNotifier<ui.Image?> cdgFrame = ValueNotifier(null);

  /// The same screen as raw RGBA bytes, for the second-screen window.
  Uint8List? cdgPixels;

  bool get isVideo => current?.kind == 'video';
  bool get hasCdg => _cdg != null;

  /// Bumped whenever a fade should stop: a new song, stop, or a volume
  /// change by hand.
  int _fadeId = 0;

  /// A fade-in starts at this share of the volume (where a crossfade's
  /// fade-out ended).
  double fadeInFrom = 1 / 3;
  int _rampId = -1;
  bool get _fading => _rampId == _fadeId;

  /// [fadeIn] starts the song silent and brings the volume up over that time.
  /// [skipSilence] starts the song at its first sound, past any silence at
  /// the start of the file.
  Future<void> load(
    Track track, {
    String? singer,
    bool autostart = true,
    Duration? fadeIn,
    bool skipSilence = false,
  }) async {
    _fadeId++;
    error = null;
    edges = null;
    cueStart = Duration.zero;
    current = track;
    this.singer = singer;
    position = Duration.zero;
    duration = Duration.zero;
    _cdg = null;
    cdgFrame.value = null;
    cdgPixels = null;
    notifyListeners();
    try {
      var media = track.path;
      String? cdgPath = track.cdgPath;
      if (track.kind == 'cdg_zip') {
        final extracted = await _extractZip(track);
        media = extracted.$1;
        cdgPath = extracted.$2;
      }
      if (cdgPath != null && File(cdgPath).existsSync()) {
        _cdg = CdgDecoder(await File(cdgPath).readAsBytes());
        await _render();
      }
      edges = await _edgesOf(media);
      final first = edges?.start ?? Duration.zero;
      if (skipSilence && first > const Duration(milliseconds: 400)) {
        cueStart = first - const Duration(milliseconds: 150); // a breath before the first note
      }
      position = cueStart;
      await backend.open(media, start: cueStart == Duration.zero ? null : cueStart);
      final fading = fadeIn != null && autostart && !muted;
      await backend.setVolume(muted ? 0 : (fading ? volume * fadeInFrom : volume));
      if (autostart) {
        await backend.play();
      } else {
        await backend.pause();
      }
      if (fading) unawaited(_ramp(from: fadeInFrom, to: 1, over: fadeIn));
    } catch (e) {
      error = 'Could not play ${track.fileName}: $e';
    }
    notifyListeners();
  }

  /// Starts a loaded (cued) song, bringing the volume up from
  /// [fadeInFrom] over [fadeIn] if given. The 2-deck mode starts the waiting
  /// deck this way.
  Future<void> play({Duration? fadeIn}) async {
    if (current == null) return;
    _fadeId++;
    final fading = fadeIn != null && !muted;
    await backend.setVolume(muted ? 0 : (fading ? volume * fadeInFrom : volume));
    await backend.play();
    if (fading) unawaited(_ramp(from: fadeInFrom, to: 1, over: fadeIn));
  }

  /// Takes the volume and mute setting from the other deck, without a fade.
  Future<void> matchLevel(KaraokeEngine other) async {
    volume = other.volume;
    muted = other.muted;
    if (!_fading) await backend.setVolume(muted ? 0 : volume);
  }

  Future<void> playPause() async {
    if (current == null) return;
    if (_fading) {
      // Pausing stops a crossfade and puts the volume back.
      _fadeId++;
      await backend.setVolume(muted ? 0 : volume);
    }
    playing ? await backend.pause() : await backend.play();
  }

  Future<void> stop() async {
    _fadeId++;
    await backend.stop();
    current = null;
    _cdg = null;
    cdgFrame.value = null;
    cdgPixels = null;
    position = Duration.zero;
    notifyListeners();
  }

  Future<void> restart() => backend.seek(cueStart);

  Future<AudioEdges?> _edgesOf(String path) async {
    if (_edgeCache.containsKey(path)) return _edgeCache[path];
    AudioEdges? e;
    try {
      e = await scanEdges(path).timeout(const Duration(seconds: 3));
    } catch (_) {}
    return _edgeCache[path] = e;
  }

  Future<void> seek(Duration to) => backend.seek(to);

  Future<void> setVolume(double v) async {
    _fadeId++;
    volume = v.clamp(0, 100);
    muted = false;
    await backend.setVolume(volume);
    notifyListeners();
  }

  Future<void> toggleMute() async {
    _fadeId++;
    muted = !muted;
    await backend.setVolume(muted ? 0 : volume);
    notifyListeners();
  }

  /// Fades the volume to silence over [over], for crossfading into the next
  /// song. Returns false if something else (a new song, stop, the volume
  /// slider) interrupted the fade.
  /// [to] is the volume to end at, as a share of the set volume.
  Future<bool> fadeOut({Duration over = const Duration(seconds: 3), double to = 0}) =>
      _ramp(from: 1, to: to, over: over);

  Future<bool> _ramp({required double from, required double to, required Duration over}) async {
    final id = _rampId = ++_fadeId;
    const steps = 20;
    for (var i = 1; i <= steps; i++) {
      await Future<void>.delayed(over ~/ steps);
      if (id != _fadeId) return false;
      await backend.setVolume((muted ? 0 : volume) * (from + (to - from) * i / steps));
    }
    return id == _fadeId;
  }

  void _onPosition(Duration pos) {
    position = pos;
    final cdg = _cdg;
    if (cdg != null) {
      cdg.seek(pos);
      if (cdg.changed && !_rendering) _render();
    }
    notifyListeners();
  }

  Future<void> _render() async {
    final cdg = _cdg;
    if (cdg == null) return;
    _rendering = true;
    final pixels = Uint8List.fromList(cdg.rgba());
    final completer = Completer<ui.Image>();
    ui.decodeImageFromPixels(pixels, CdgDecoder.width, CdgDecoder.height, ui.PixelFormat.rgba8888, completer.complete);
    final image = await completer.future;
    if (identical(cdg, _cdg)) {
      cdgPixels = pixels;
      cdgFrame.value?.dispose();
      cdgFrame.value = image;
    } else {
      image.dispose();
    }
    _rendering = false;
  }

  /// Unzips an MP3+G zip into a temp folder once, and returns the audio and
  /// CDG paths inside it.
  Future<(String, String?)> _extractZip(Track track) async {
    final dir = Directory(p.join(tempDir, 'eztiger', 'zip_${track.id}_${track.mtime}'));
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
      await extractFileToDisk(track.path, dir.path);
    }
    String? audio, cdg;
    for (final f in dir.listSync(recursive: true).whereType<File>()) {
      final ext = p.extension(f.path).toLowerCase();
      if (ext == '.cdg') cdg ??= f.path;
      if (audioExtensions.contains(ext)) audio ??= f.path;
    }
    if (audio == null) throw StateError('no audio inside the zip');
    return (audio, cdg);
  }

  @override
  Future<void> dispose() async {
    for (final s in _subs) {
      await s.cancel();
    }
    await backend.dispose();
    cdgFrame.value?.dispose();
    super.dispose();
  }
}
