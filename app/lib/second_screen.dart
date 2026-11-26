import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:eztiger_core/eztiger_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:screen_retriever/screen_retriever.dart' as sr;
import 'package:window_manager/window_manager.dart';

import 'player.dart';
import 'promos.dart';
import 'theme.dart';
import 'edition.dart';
import 'venue.dart';
import 'ui/logo.dart';

/// The command-line switch that starts EZTiger as the second-screen output:
/// `eztiger.exe --output-window=<port>`.
const outputWindowSwitch = '--output-window=';

/// The port to talk to the main window on, when this copy of EZTiger was
/// started as the second-screen output; else null.
int? outputWindowPort(List<String> args) {
  for (final a in args) {
    if (a.startsWith(outputWindowSwitch)) return int.tryParse(a.substring(outputWindowSwitch.length));
  }
  return null;
}

/// One message to the output window, as a line of JSON.
String outputMessage(String method, Object? args) => jsonEncode({'m': method, 'a': args});

/// Main-window side: opens the output window on the second screen and keeps
/// it showing what the player is playing.
///
/// The output window is a second copy of EZTiger (a program of its own), told
/// what to show over a private connection on this PC. It used to be a second
/// window inside this program, but on Windows the two windows shared the
/// mouse and keyboard handling, and the main window could stop taking clicks,
/// keys and scrolling for good once the second one opened.
class SecondScreen extends ChangeNotifier {
  SecondScreen(this._engine, {this.startOutput = _startOutput});

  /// The player to show: in 2-deck mode, whichever deck is live.
  final KaraokeEngine Function() _engine;
  KaraokeEngine get engine => _engine();

  /// Starts the output program, told to connect back on [port]; replaced in tests.
  final Future<Process?> Function(int port) startOutput;

  static Future<Process?> _startOutput(int port) =>
      // Detached: its output isn't read here, so it can never fill a pipe and stall.
      Process.start(Platform.resolvedExecutable, ['$outputWindowSwitch$port'], mode: ProcessStartMode.detached);

  bool get isOpen => _socket != null || _opening;
  bool _opening = false;
  ServerSocket? _server;
  Socket? _socket;
  Process? _process;
  Timer? _tick;
  String? _sentTrack;
  bool? _sentPlaying;
  int? _sentDelay;
  final Stopwatch _sinceClock = Stopwatch();

  /// How often the output window is told where the song is. It runs its own
  /// clock in between, so the messages stay few and small.
  static const clockEvery = Duration(milliseconds: 300);

  Future<void> toggle() => isOpen ? close() : open();

  Future<void> open() async {
    if (isOpen) return;
    _opening = true;
    notifyListeners();
    try {
      final server = _server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      _process = await startOutput(server.port);
      final socket = await server.first.timeout(const Duration(seconds: 20));
      await server.close();
      _server = null;
      _socket = socket;
      socket.done.then((_) => _closed(), onError: (_) => _closed());
      socket.listen((_) {}, onDone: _closed, onError: (_) => _closed(), cancelOnError: true);
      _sentTrack = null;
      _sentPlaying = null;
      _sentDelay = null;
      _sinceClock.reset();
      _tick = Timer.periodic(const Duration(milliseconds: 100), (_) => _push());
      _push();
    } catch (_) {
      // It didn't start: tidy up, and the button shows it closed.
      await _server?.close();
      _server = null;
      _process?.kill();
      _process = null;
    } finally {
      _opening = false;
      notifyListeners();
    }
  }

  Future<void> close() async {
    final socket = _socket, process = _process;
    if (socket != null) {
      try {
        socket.writeln(outputMessage('close', null));
        await socket.flush();
      } catch (_) {}
    }
    _closed();
    // It closes itself on 'close'; make sure.
    if (process != null) {
      unawaited(Future<void>.delayed(const Duration(seconds: 3), () => process.kill()));
    }
  }

  /// The output window has gone (closed by hand, or by [close]).
  void _closed() {
    if (_socket == null && _tick == null) return; // already, or EZTiger closing (dispose)
    _tick?.cancel();
    _tick = null;
    try {
      _socket?.destroy();
    } catch (_) {}
    _socket = null;
    _process = null;
    notifyListeners();
  }

  void _send(String method, Object? args) => _socket?.writeln(outputMessage(method, args));

  void _push() {
    if (_socket == null) return;
    try {
      final e = engine, t = e.current;
      final cdg = e.isVideo ? null : e.cdgPath;
      final track = '${t?.id}|$cdg|${e.singer}|$isPro';
      if (track != _sentTrack) {
        _send('track', {
          'title': t?.title,
          'artist': t?.artist,
          'singer': e.singer,
          'video': e.isVideo ? t!.path : null,
          'cdg': cdg,
          'pro': isPro,
        });
        _sentTrack = track;
        _sentPlaying = null;
      }
      final delay = e.lyricsDelay.inMilliseconds;
      if (_sentPlaying != e.playing || _sentDelay != delay || !_sinceClock.isRunning || _sinceClock.elapsed >= clockEvery) {
        _send('clock', {
          'playing': e.playing,
          'ms': e.position.inMilliseconds,
          'lyricsMs': e.lyricsPosition.inMilliseconds,
          'delayMs': delay,
          // where the music ends, so the output window knows a song has finished (promos may show)
          'endMs': e.audioEnd.inMilliseconds,
        });
        _sentPlaying = e.playing;
        _sentDelay = delay;
        _sinceClock
          ..reset()
          ..start();
      }
    } catch (_) {
      _sentTrack = null;
    }
  }

  @override
  void dispose() {
    // EZTiger is closing: tell the output window to go, without waiting.
    _tick?.cancel();
    _tick = null;
    final process = _process;
    try {
      _socket?.writeln(outputMessage('close', null));
      _socket?.close();
    } catch (_) {}
    _socket = null;
    _process = null;
    if (process != null) Timer(const Duration(seconds: 3), process.kill);
    super.dispose();
  }
}

// ----------------------------------------------------------- output window

/// Runs in the second-screen copy of EZTiger: shows what the main window says.
Future<void> runOutputWindow(int port) async {
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
  // Promos between singers: the venue's offers take turns with the "up next" screen.
  out.promos
    ..start()
    ..run(() => out.betweenActs);
  // The venue switched on in ☰ Menu → Venue branding (or in Music Bingo or Quiz Night).
  out.watchVenue();
  runApp(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: buildTheme(true),
      home: _OutputView(model: out),
    ),
  );

  // The main window's messages, one JSON line each. When it goes (closed, or
  // EZTiger quit), this window goes too.
  try {
    final socket = await Socket.connect(InternetAddress.loopbackIPv4, port, timeout: const Duration(seconds: 10));
    // One at a time, in order (a new song's lyrics load before its clock).
    await for (final line in socket.cast<List<int>>().transform(utf8.decoder).transform(const LineSplitter())) {
      try {
        final msg = jsonDecode(line) as Map<String, dynamic>;
        await out.handle(MethodCall(msg['m'] as String, msg['a']));
      } catch (_) {
        // A message it doesn't understand: skip it.
      }
    }
  } catch (_) {}
  await out.handle(const MethodCall('close'));
}

class _OutputModel extends ChangeNotifier {
  String? title, artist, singer;
  ui.Image? cdg;
  bool fullScreen = false;

  /// The main window's player is playing (Pro shows the logo otherwise).
  bool playing = false;

  /// Where the main window's song is, from its last clock message.
  int _atMs = 0;

  /// Promo slides for between singers.
  final PromoPlayer promos = PromoPlayer();

  /// The venue to brand the screen with, or null for EZTiger's own look.
  Venue? venue;
  String _venueKey = '';

  void watchVenue([VenueStore? store]) {
    void read() {
      try {
        final v = (store ?? VenueStore()).active();
        final key = v == null ? '' : '${v.id}|${v.name}|${v.tagline}|${v.colour}|${v.logo}|${v.photos.join(',')}';
        if (key == _venueKey) return;
        _venueKey = key;
        // A logo or photo replaced under the same name: show the new picture.
        for (final f in [?v?.logoPath, ...?v?.photoPaths]) {
          FileImage(File(f)).evict();
        }
        venue = v;
        notifyListeners();
      } catch (_) {}
    }

    read();
    Timer.periodic(const Duration(seconds: 5), (_) => read());
  }

  /// Between singers: nothing playing, and the song (if any) not yet started or
  /// at its end, so a pause in the middle of a song doesn't bring up promos.
  bool get betweenActs => !playing && (title == null || _atMs < 1500 || _ended);
  bool _ended = false;

  /// The main window is EZTiger Pro (it says so with each song).
  bool pro = isPro;
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
        _ended = false;
        _atMs = 0;
        singer = a['singer'] as String?;
        pro = a['pro'] as bool? ?? pro;
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
        final atMs = a['ms'] as int;
        // Stopped at (or within a couple of seconds of) the end of the music: the song is over, promos may show.
        final endMs = a['endMs'] as int? ?? 0;
        _ended = !playing && endMs > 0 && atMs >= endMs - 2500;
        _atMs = atMs;
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
        try {
          await _player?.dispose();
          await windowManager.close();
        } catch (_) {}
        exit(0);
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
            listenable: Listenable.merge([model, model.promos]),
            builder: (context, _) {
              final promo = model.promos.showing;
              return AnimatedSwitcher(
                duration: const Duration(milliseconds: 800),
                child: promo != null
                    ? PromoSlideView(key: ValueKey('promo-${promo.id}'), slide: promo, folder: model.promos.set.folder)
                    : KeyedSubtree(key: const ValueKey('show'), child: _show(model)),
              );
            },
          ),
        ),
      ),
    ),
  );

  Widget _show(_OutputModel model) {
              final v = model.video;
              final idle = model.pro && !model.playing;
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
              if (model.venue case final venue? when model.pro) {
                return VenueScreen(venue: venue, title: model.title, artist: model.artist, singer: model.singer);
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
  }
}

/// The second screen between singers while a venue is switched on: its photo
/// behind, its logo (or name) in its colour, the tagline, who's up next, and a
/// small "Powered by EZTiger Entertainment".
class VenueScreen extends StatelessWidget {
  const VenueScreen({super.key, required this.venue, this.title, this.artist, this.singer});
  final Venue venue;
  final String? title, artist, singer;

  static const poweredBy = 'Powered by EZTiger Entertainment';

  @override
  Widget build(BuildContext context) {
    final colour = Color(venue.colourValue);
    final photo = venue.photoPaths.firstOrNull;
    final logo = venue.logoPath;
    const shadow = [Shadow(color: Color(0xAA000000), blurRadius: 24, offset: Offset(0, 4))];
    return ColoredBox(
      color: Colors.black,
      child: Center(
        child: FittedBox(
          child: SizedBox(
            width: 1920,
            height: 1080,
            child: Stack(
              fit: StackFit.expand,
              children: [
                DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: RadialGradient(colors: [colour, Color.lerp(colour, Colors.black, 0.8)!], radius: 1.2),
                  ),
                ),
                if (photo != null)
                  Opacity(
                    opacity: 0.45,
                    child: Image.file(File(photo), fit: BoxFit.cover, errorBuilder: (_, _, _) => const SizedBox()),
                  ),
                const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Color(0x33000000), Color(0xCC000000)],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(120, 90, 120, 70),
                  child: Column(
                    children: [
                      if (logo != null)
                        SizedBox(
                          height: 380,
                          child: Image.file(File(logo), key: const Key('venue-screen-logo'), fit: BoxFit.contain,
                              errorBuilder: (_, _, _) => const SizedBox()),
                        )
                      else
                        Text(
                          venue.name,
                          key: const Key('venue-screen-name'),
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 150, fontWeight: FontWeight.w900, color: Colors.white, shadows: shadow),
                        ),
                      if (venue.tagline.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 18),
                          child: Text(venue.tagline, textAlign: TextAlign.center,
                              style: const TextStyle(fontSize: 60, fontStyle: FontStyle.italic, color: Colors.white, shadows: shadow)),
                        ),
                      const Spacer(),
                      Text(
                        title ?? 'Up next…',
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        style: const TextStyle(fontSize: 76, fontWeight: FontWeight.w800, color: Colors.white, shadows: shadow),
                      ),
                      if (artist != null)
                        Text(artist!, style: const TextStyle(fontSize: 50, color: Colors.white70, shadows: shadow)),
                      if (singer != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 16),
                          child: Text('🎤 $singer', style: const TextStyle(fontSize: 60, color: Colors.white, shadows: shadow)),
                        ),
                      const Spacer(),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          const EzLogo(size: 44),
                          const SizedBox(width: 12),
                          Text(poweredBy, style: TextStyle(fontSize: 28, color: Colors.white.withValues(alpha: 0.75))),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
