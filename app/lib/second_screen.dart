import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:eztiger_core/eztiger_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:screen_retriever/screen_retriever.dart' as sr;
import 'package:window_manager/window_manager.dart';

import 'player.dart';
import 'theme.dart';
import 'edition.dart';
import 'ui/logo.dart';

/// The arguments the output window is opened with.
const outputWindowArgs = '{"window":"output"}';

bool isOutputWindow(String args) {
  try {
    return (jsonDecode(args) as Map)['window'] == 'output';
  } catch (_) {
    return false;
  }
}

const _channel = WindowMethodChannel('eztiger/output', mode: ChannelMode.unidirectional);

/// Main-window side: opens the output window on the second screen and keeps
/// it showing what the player is playing.
class SecondScreen extends ChangeNotifier {
  SecondScreen(this._engine);

  /// The player to show: in 2-deck mode, whichever deck is live.
  final KaraokeEngine Function() _engine;
  KaraokeEngine get engine => _engine();

  bool get isOpen => _window != null;
  WindowController? _window;
  StreamSubscription<void>? _windows;
  Timer? _tick;
  String? _sentTrack;
  bool? _sentPlaying;
  int? _sentDelay;
  final Stopwatch _sinceClock = Stopwatch();
  bool _busy = false;

  /// How often the output window is told where the song is. It runs its own
  /// clock in between, so this stays small: the messages pass through the
  /// same Windows thread as the mouse, and a steady stream of big ones (each
  /// CDG picture, as it was) froze clicks, menus and resizing.
  static const clockEvery = Duration(milliseconds: 300);

  Future<void> toggle() => isOpen ? close() : open();

  Future<void> open() async {
    if (isOpen) return;
    _window = await WindowController.create(
      const WindowConfiguration(arguments: outputWindowArgs, hiddenAtLaunch: true),
    );
    await _window!.show();
    _windows ??= onWindowsChanged.listen((_) => _checkStillOpen());
    _sentTrack = null;
    _sentPlaying = null;
    _sentDelay = null;
    // The output window needs a moment to start its engine.
    _tick = Timer.periodic(const Duration(milliseconds: 100), (_) => _push());
    notifyListeners();
  }

  Future<void> close() async {
    _tick?.cancel();
    _tick = null;
    try {
      await _channel.invokeMethod('close');
    } catch (_) {}
    _window = null;
    notifyListeners();
  }

  Future<void> _checkStillOpen() async {
    final w = _window;
    if (w == null) return;
    final all = await WindowController.getAll();
    if (!all.any((c) => c.windowId == w.windowId)) {
      _tick?.cancel();
      _tick = null;
      _window = null;
      notifyListeners();
    }
  }

  Future<void> _push() async {
    if (_busy) return;
    _busy = true;
    try {
      final e = engine, t = e.current;
      final cdg = e.isVideo ? null : e.cdgPath;
      final track = '${t?.id}|$cdg|${e.singer}';
      if (track != _sentTrack) {
        await _channel.invokeMethod('track', {
          'title': t?.title,
          'artist': t?.artist,
          'singer': e.singer,
          'video': e.isVideo ? t!.path : null,
          'cdg': cdg,
        });
        _sentTrack = track;
        _sentPlaying = null;
      }
      final delay = e.lyricsDelay.inMilliseconds;
      if (_sentPlaying != e.playing || _sentDelay != delay || !_sinceClock.isRunning || _sinceClock.elapsed >= clockEvery) {
        await _channel.invokeMethod('clock', {
          'playing': e.playing,
          'ms': e.position.inMilliseconds,
          'lyricsMs': e.lyricsPosition.inMilliseconds,
          'delayMs': delay,
        });
        _sentPlaying = e.playing;
        _sentDelay = delay;
        _sinceClock
          ..reset()
          ..start();
      }
    } on WindowChannelException {
      // Not ready yet, or closed: try again on the next tick.
      _sentTrack = null;
    } catch (_) {
      _sentTrack = null;
    } finally {
      _busy = false;
    }
  }

  @override
  void dispose() {
    _tick?.cancel();
    _windows?.cancel();
    super.dispose();
  }
}

// ----------------------------------------------------------- output window

/// Runs in the second window's own engine.
Future<void> runOutputWindow() async {
  MediaKit.ensureInitialized();
  await windowManager.ensureInitialized();
  await windowManager.setTitle('EZtiger output');
  await windowManager.setMinimumSize(const Size(320, 240));

  // Go full screen on a second monitor when there is one.
  var fullScreen = false;
  try {
    final primary = await sr.screenRetriever.getPrimaryDisplay();
    final displays = await sr.screenRetriever.getAllDisplays();
    final other = displays.where((d) => d.id != primary.id).firstOrNull;
    if (other != null) {
      final at = other.visiblePosition ?? Offset.zero;
      await windowManager.setBounds(Rect.fromLTWH(at.dx + 40, at.dy + 40, 960, 540));
      await windowManager.setFullScreen(true);
      fullScreen = true;
    } else {
      await windowManager.setSize(const Size(960, 540));
      await windowManager.center();
    }
  } catch (_) {}

  final out = _OutputModel()..fullScreen = fullScreen;
  await _channel.setMethodCallHandler(out.handle);
  runApp(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: buildTheme(true),
      home: _OutputView(model: out),
    ),
  );
}

class _OutputModel extends ChangeNotifier {
  String? title, artist, singer;
  ui.Image? cdg;
  bool fullScreen = false;

  /// The main window's player is playing (Pro shows the logo otherwise).
  bool playing = false;
  Player? _player;
  VideoController? video;
  int _delayMs = 0;

  // The CDG lyrics, drawn here from the song's .cdg file: the main window
  // only says where the song is (every 300 ms), and this window keeps time
  // in between.
  CdgDecoder? _lyrics;
  Timer? _lyricsTick;
  int _lyricsMs = 0;
  final Stopwatch _sinceClock = Stopwatch();
  bool _drawing = false;

  void _setLyrics(CdgDecoder? d) {
    _lyrics = d;
    _lyricsMs = 0;
    _sinceClock.reset();
    _lyricsTick?.cancel();
    _lyricsTick = d == null ? null : Timer.periodic(const Duration(milliseconds: 40), (_) => _drawLyrics());
    cdg?.dispose();
    cdg = null;
  }

  Future<void> _drawLyrics() async {
    final d = _lyrics;
    if (d == null || _drawing) return;
    final ms = _lyricsMs + (playing ? _sinceClock.elapsedMilliseconds : 0);
    d.seek(Duration(milliseconds: ms));
    if (!d.changed && cdg != null) return;
    _drawing = true;
    try {
      final c = Completer<ui.Image>();
      ui.decodeImageFromPixels(Uint8List.fromList(d.rgba()), CdgDecoder.width, CdgDecoder.height, ui.PixelFormat.rgba8888, c.complete);
      final img = await c.future;
      if (!identical(d, _lyrics)) {
        img.dispose();
        return;
      }
      cdg?.dispose();
      cdg = img;
      notifyListeners();
    } finally {
      _drawing = false;
    }
  }

  Future<dynamic> handle(MethodCall call) async {
    switch (call.method) {
      case 'track':
        final a = Map<String, dynamic>.from(call.arguments as Map);
        title = a['title'] as String?;
        artist = a['artist'] as String?;
        singer = a['singer'] as String?;
        final cdgFile = a['cdg'] as String?;
        CdgDecoder? lyrics;
        if (cdgFile != null) {
          try {
            lyrics = CdgDecoder(await File(cdgFile).readAsBytes());
          } catch (_) {
            // Unreadable: the window shows the title instead.
          }
        }
        _setLyrics(lyrics);
        final path = a['video'] as String?;
        if (path == null) {
          await _player?.stop();
          video = null;
        } else {
          final p = _player ??= Player();
          await p.setVolume(0); // sound comes from the main window
          video ??= VideoController(p);
          await p.open(Media(path), play: false);
        }
        notifyListeners();
      case 'clock':
        final a = Map<String, dynamic>.from(call.arguments as Map);
        final playing = a['playing'] as bool;
        _lyricsMs = a['lyricsMs'] as int? ?? a['ms'] as int;
        _sinceClock
          ..reset()
          ..start();
        if (playing != this.playing) {
          this.playing = playing;
          notifyListeners();
        }
        if (_lyrics != null) unawaited(_drawLyrics());
        final p = _player;
        if (p == null || video == null) return null;
        // The lyrics delay: hold this window's video back too.
        final delayMs = a['delayMs'] as int? ?? 0;
        if (delayMs != _delayMs && p.platform is NativePlayer) {
          _delayMs = delayMs;
          await (p.platform as NativePlayer).setProperty('audio-delay', (-delayMs / 1000).toStringAsFixed(3));
        }
        final at = Duration(milliseconds: a['ms'] as int);
        if (playing != p.state.playing) playing ? await p.play() : await p.pause();
        if ((p.state.position - at).abs() > const Duration(milliseconds: 400)) await p.seek(at);
      case 'close':
        _setLyrics(null);
        await _player?.dispose();
        await windowManager.close();
    }
    return null;
  }

  Future<void> setFullScreen(bool v) async {
    fullScreen = v;
    await windowManager.setFullScreen(v);
    notifyListeners();
  }
}

class _OutputView extends StatelessWidget {
  const _OutputView({required this.model});
  final _OutputModel model;

  @override
  Widget build(BuildContext context) => CallbackShortcuts(
    bindings: {
      const SingleActivator(LogicalKeyboardKey.escape): () => model.setFullScreen(false),
      const SingleActivator(LogicalKeyboardKey.f11): () => model.setFullScreen(!model.fullScreen),
    },
    child: Focus(
      autofocus: true,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: GestureDetector(
          onDoubleTap: () => model.setFullScreen(!model.fullScreen),
          child: ListenableBuilder(
            listenable: model,
            builder: (context, _) {
              final v = model.video;
              final idle = isPro && !model.playing;
              if (v != null && !idle) return Video(controller: v, controls: NoVideoControls, fill: Colors.black);
              final img = model.cdg;
              if (img != null && !idle) {
                return Center(
                  child: AspectRatio(
                    aspectRatio: 300 / 216,
                    child: RawImage(image: img, fit: BoxFit.fill, filterQuality: FilterQuality.none),
                  ),
                );
              }
              return Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const EzLogo(size: 160),
                    const SizedBox(height: 12),
                    Text(
                      'EZTIGER',
                      style: TextStyle(
                        fontSize: 64,
                        fontWeight: FontWeight.w900,
                        color: EzColors.brass,
                        letterSpacing: 10,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      model.title ?? 'Up next…',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 36, color: EzColors.cyan),
                    ),
                    if (model.artist != null)
                      Text(model.artist!, style: TextStyle(fontSize: 24, color: EzColors.vfdSub)),
                    if (model.singer != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Text('🎤 ${model.singer}', style: const TextStyle(fontSize: 28, color: Colors.white70)),
                      ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    ),
  );
}
