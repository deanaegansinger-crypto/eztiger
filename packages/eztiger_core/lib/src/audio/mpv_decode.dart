import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:path/path.dart' as p;

import 'track_analysis.dart';

/// The libmpv file name for this platform: the one the app already ships
/// for playback (media_kit's).
String defaultLibmpvName() {
  if (Platform.isWindows) return 'libmpv-2.dll';
  if (Platform.isMacOS) return 'libmpv.dylib';
  return 'libmpv.so';
}

/// Decodes up to [maxSeconds] of [mediaPath] (any file mpv plays: MP3, M4A,
/// WAV, MP4 and so on) to mono 16-bit samples at [sampleRate], using its own
/// libmpv instance that writes the sound to a file instead of the speakers,
/// as fast as it can decode (well under a second for a song).
///
/// Blocking: call it from an isolate. Returns null if libmpv can't be
/// loaded or the file can't be decoded.
Int16List? decodeWithMpv(
  String mediaPath, {
  required String tempDir,
  String? libmpvPath,
  int sampleRate = 11025,
  int maxSeconds = 240,
  Duration timeout = const Duration(seconds: 30),
}) {
  final _Mpv mpv;
  try {
    mpv = _Mpv(DynamicLibrary.open(libmpvPath ?? defaultLibmpvName()));
  } catch (_) {
    return null;
  }
  final out = File(p.join(tempDir, 'eztiger_pcm_${pid}_${DateTime.now().microsecondsSinceEpoch}.raw'));
  final handle = mpv.create();
  if (handle == nullptr) return null;
  try {
    final options = {
      'config': 'no',
      'terminal': 'no',
      'idle': 'no',
      'load-scripts': 'no',
      'ytdl': 'no',
      'input-default-bindings': 'no',
      'vid': 'no',
      'sid': 'no',
      'audio-display': 'no',
      'ao': 'pcm',
      'ao-pcm-file': out.path,
      'ao-pcm-waveheader': 'no',
      'audio-format': 's16',
      'audio-channels': 'mono',
      'audio-samplerate': '$sampleRate',
      'length': '$maxSeconds',
    };
    for (final e in options.entries) {
      if (mpv.setOption(handle, e.key, e.value) < 0 && e.key == 'ao') return null;
    }
    if (mpv.initialize(handle) < 0) return null;
    if (mpv.command(handle, ['loadfile', mediaPath]) < 0) return null;
    final until = DateTime.now().add(timeout);
    var ended = false;
    while (DateTime.now().isBefore(until)) {
      final id = mpv.waitEvent(handle, 1);
      if (id == _endFile || id == _shutdown) {
        ended = true;
        break;
      }
    }
    if (!ended) return null;
  } finally {
    mpv.terminateDestroy(handle);
  }
  try {
    if (!out.existsSync()) return null;
    final bytes = out.readAsBytesSync();
    final usable = bytes.length & ~1;
    if (usable == 0) return null;
    return Int16List.view(Uint8List.fromList(bytes.sublist(0, usable)).buffer);
  } finally {
    try {
      out.deleteSync();
    } catch (_) {}
  }
}

/// Decodes [mediaPath] and works out its key and tempo (see [analysePcm]).
/// Blocking: call it from an isolate.
TrackAnalysis? analyseMediaFile(String mediaPath, {required String tempDir, String? libmpvPath}) {
  const rate = 11025;
  final pcm = decodeWithMpv(mediaPath, tempDir: tempDir, libmpvPath: libmpvPath, sampleRate: rate);
  if (pcm == null) return null;
  return analysePcm(pcm, rate);
}

const _shutdown = 1;
const _endFile = 7;

typedef _CreateC = Pointer<Void> Function();
typedef _SetOptionC = Int32 Function(Pointer<Void>, Pointer<Utf8>, Pointer<Utf8>);
typedef _SetOptionD = int Function(Pointer<Void>, Pointer<Utf8>, Pointer<Utf8>);
typedef _InitC = Int32 Function(Pointer<Void>);
typedef _InitD = int Function(Pointer<Void>);
typedef _CommandC = Int32 Function(Pointer<Void>, Pointer<Pointer<Utf8>>);
typedef _CommandD = int Function(Pointer<Void>, Pointer<Pointer<Utf8>>);
typedef _WaitC = Pointer<Int32> Function(Pointer<Void>, Double);
typedef _WaitD = Pointer<Int32> Function(Pointer<Void>, double);
typedef _DestroyC = Void Function(Pointer<Void>);
typedef _DestroyD = void Function(Pointer<Void>);

/// The few libmpv client calls needed to decode a file.
class _Mpv {
  _Mpv(DynamicLibrary lib)
      : create = lib.lookupFunction<_CreateC, _CreateC>('mpv_create'),
        _setOption = lib.lookupFunction<_SetOptionC, _SetOptionD>('mpv_set_option_string'),
        initialize = lib.lookupFunction<_InitC, _InitD>('mpv_initialize'),
        _command = lib.lookupFunction<_CommandC, _CommandD>('mpv_command'),
        _wait = lib.lookupFunction<_WaitC, _WaitD>('mpv_wait_event'),
        terminateDestroy = lib.lookupFunction<_DestroyC, _DestroyD>('mpv_terminate_destroy');

  final Pointer<Void> Function() create;
  final _SetOptionD _setOption;
  final _InitD initialize;
  final _CommandD _command;
  final _WaitD _wait;
  final _DestroyD terminateDestroy;

  int setOption(Pointer<Void> h, String name, String value) {
    final n = name.toNativeUtf8(), v = value.toNativeUtf8();
    try {
      return _setOption(h, n, v);
    } finally {
      malloc.free(n);
      malloc.free(v);
    }
  }

  int command(Pointer<Void> h, List<String> args) {
    final strings = [for (final a in args) a.toNativeUtf8()];
    final argv = malloc<Pointer<Utf8>>(args.length + 1);
    try {
      for (var i = 0; i < strings.length; i++) {
        argv[i] = strings[i];
      }
      argv[args.length] = nullptr;
      return _command(h, argv);
    } finally {
      for (final s in strings) {
        malloc.free(s);
      }
      malloc.free(argv);
    }
  }

  /// The id of the next event (0 when none came within [seconds]).
  int waitEvent(Pointer<Void> h, double seconds) => _wait(h, seconds).value;
}
