import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:archive/archive_io.dart';
import 'package:eztiger_core/eztiger_core.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

/// What the karaoke engine needs from an audio/video player. The real one
/// is media_kit (libmpv); tests use a fake.
abstract class MediaBackend {
  Future<void> open(String path);
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
  KaraokeEngine(this.backend) {
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

  Future<void> load(Track track, {String? singer, bool autostart = true}) async {
    error = null;
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
      await backend.open(media);
      await backend.setVolume(muted ? 0 : volume);
      if (autostart) {
        await backend.play();
      } else {
        await backend.pause();
      }
    } catch (e) {
      error = 'Could not play ${track.fileName}: $e';
    }
    notifyListeners();
  }

  Future<void> playPause() async {
    if (current == null) return;
    playing ? await backend.pause() : await backend.play();
  }

  Future<void> stop() async {
    await backend.stop();
    current = null;
    _cdg = null;
    cdgFrame.value = null;
    cdgPixels = null;
    position = Duration.zero;
    notifyListeners();
  }

  Future<void> restart() => backend.seek(Duration.zero);

  Future<void> seek(Duration to) => backend.seek(to);

  Future<void> setVolume(double v) async {
    volume = v.clamp(0, 100);
    muted = false;
    await backend.setVolume(volume);
    notifyListeners();
  }

  Future<void> toggleMute() async {
    muted = !muted;
    await backend.setVolume(muted ? 0 : volume);
    notifyListeners();
  }

  /// Fades the volume to silence over [over], for crossfading into the next
  /// song.
  Future<void> fadeOut({Duration over = const Duration(seconds: 3)}) async {
    const steps = 15;
    for (var i = steps - 1; i >= 0; i--) {
      await backend.setVolume((muted ? 0 : volume) * i / steps);
      await Future<void>.delayed(over ~/ steps);
    }
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
    ui.decodeImageFromPixels(
        pixels, CdgDecoder.width, CdgDecoder.height, ui.PixelFormat.rgba8888, completer.complete);
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
    final dir = Directory(p.join(Directory.systemTemp.path, 'eztiger', 'zip_${track.id}_${track.mtime}'));
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
