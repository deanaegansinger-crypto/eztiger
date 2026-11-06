import 'dart:async';
import 'dart:convert';
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
  int? _sentTrack;
  Uint8List? _sentPixels;
  bool? _sentPlaying;
  bool _busy = false;

  Future<void> toggle() => isOpen ? close() : open();

  Future<void> open() async {
    if (isOpen) return;
    _window = await WindowController.create(
      const WindowConfiguration(arguments: outputWindowArgs, hiddenAtLaunch: true),
    );
    await _window!.show();
    _windows ??= onWindowsChanged.listen((_) => _checkStillOpen());
    _sentTrack = null;
    _sentPixels = null;
    _sentPlaying = null;
    // The output window needs a moment to start its engine.
    _tick = Timer.periodic(const Duration(milliseconds: 60), (_) => _push());
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
      final t = engine.current;
      if (t?.id != _sentTrack) {
        await _channel.invokeMethod('track', {
          'title': t?.title,
          'artist': t?.artist,
          'singer': engine.singer,
          'video': engine.isVideo ? t!.path : null,
        });
        _sentTrack = t?.id;
        _sentPixels = null;
        _sentPlaying = null;
      }
      final px = engine.cdgPixels;
      if (!identical(px, _sentPixels)) {
        await _channel.invokeMethod('cdg', px);
        _sentPixels = px;
      }
      if (engine.isVideo || _sentPlaying != engine.playing) {
        await _channel.invokeMethod('clock', {'playing': engine.playing, 'ms': engine.position.inMilliseconds});
        _sentPlaying = engine.playing;
      }
    } on WindowChannelException {
      // Not ready yet, or closed: try again on the next tick.
      _sentTrack = -1;
    } catch (_) {
      _sentTrack = -1;
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
  Player? _player;
  VideoController? video;

  Future<dynamic> handle(MethodCall call) async {
    switch (call.method) {
      case 'track':
        final a = Map<String, dynamic>.from(call.arguments as Map);
        title = a['title'] as String?;
        artist = a['artist'] as String?;
        singer = a['singer'] as String?;
        cdg?.dispose();
        cdg = null;
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
      case 'cdg':
        final px = call.arguments as Uint8List?;
        if (px == null) {
          cdg?.dispose();
          cdg = null;
          notifyListeners();
        } else {
          final c = Completer<ui.Image>();
          ui.decodeImageFromPixels(px, CdgDecoder.width, CdgDecoder.height, ui.PixelFormat.rgba8888, c.complete);
          final img = await c.future;
          cdg?.dispose();
          cdg = img;
          notifyListeners();
        }
      case 'clock':
        final p = _player;
        if (p == null || video == null) return null;
        final a = Map<String, dynamic>.from(call.arguments as Map);
        final playing = a['playing'] as bool;
        final at = Duration(milliseconds: a['ms'] as int);
        if (playing != p.state.playing) playing ? await p.play() : await p.pause();
        if ((p.state.position - at).abs() > const Duration(milliseconds: 400)) await p.seek(at);
      case 'close':
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
              if (v != null) return Video(controller: v, controls: NoVideoControls, fill: Colors.black);
              final img = model.cdg;
              if (img != null) {
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
