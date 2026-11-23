import 'dart:async';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:eztiger_core/eztiger_core.dart';
import 'package:media_kit/media_kit.dart';
import 'package:path/path.dart' as p;

import 'player.dart' show keyRatio;

/// A sound output the preview can play through.
typedef PreviewDevice = ({String id, String name});

/// The show planner's preview player (EZTiger Pro on the PC): a third
/// player, apart from the two decks, so a song can be auditioned through
/// headphones (or any output picked) while the room hears the live deck.
/// It plays a song in the key it's planned in. Tests use a fake.
abstract class PreviewOutput {
  /// The sound outputs on this PC ("auto" is Windows' own choice).
  Future<List<PreviewDevice>> devices();
  Future<void> setDevice(String id);

  /// Plays [path] (an MP3, a zipped MP3+G, a video's sound) from [start],
  /// [key] semitones up or down.
  Future<void> play(String path, {int key = 0, Duration start = Duration.zero});
  Future<void> stop();

  /// The length of what's playing, once known; the planner remembers it.
  Stream<Duration> get duration;

  /// True while it plays.
  Stream<bool> get playing;
  Future<void> dispose();
}

/// The real preview player: libmpv through media_kit, sound only.
class MediaKitPreview implements PreviewOutput {
  MediaKitPreview(this.tempDir) {
    final native = player.platform;
    if (native is NativePlayer) unawaited(native.setProperty('vid', 'no'));
  }

  final Player player = Player();

  /// Where zipped MP3+G songs are unpacked to be heard.
  final String tempDir;

  @override
  Future<List<PreviewDevice>> devices() async {
    var list = player.state.audioDevices;
    if (list.length <= 1) {
      try {
        list = await player.stream.audioDevices.firstWhere((l) => l.length > 1).timeout(const Duration(seconds: 2));
      } catch (_) {
        list = player.state.audioDevices;
      }
    }
    return [
      for (final d in list) (id: d.name, name: d.name == 'auto' ? 'Windows sound output' : (d.description.isEmpty ? d.name : d.description)),
    ];
  }

  @override
  Future<void> setDevice(String id) async {
    final d = player.state.audioDevices.where((d) => d.name == id).firstOrNull;
    await player.setAudioDevice(d ?? AudioDevice.auto());
  }

  @override
  Future<void> play(String path, {int key = 0, Duration start = Duration.zero}) async {
    final media = path.toLowerCase().endsWith('.zip') ? await _unzipAudio(path) : path;
    await player.open(Media(media, start: start), play: false);
    final native = player.platform;
    if (native is NativePlayer) {
      // The key, as the decks do it: mpv plays faster or slower without
      // pitch correction, and scaletempo stretches the tempo back.
      final ratio = keyRatio(key);
      final shifted = ratio != 1;
      await native.setProperty('audio-pitch-correction', shifted ? 'no' : 'yes');
      await native.setProperty('speed', ratio.toStringAsFixed(8));
      await native.setProperty('af', shifted ? 'scaletempo=scale=${(1 / ratio).toStringAsFixed(8)}' : '');
    }
    await player.play();
  }

  Future<String> _unzipAudio(String zip) async {
    final dir = Directory(p.join(tempDir, 'eztiger', 'preview_${p.basenameWithoutExtension(zip).hashCode}'));
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
      await extractFileToDisk(zip, dir.path);
    }
    for (final f in dir.listSync(recursive: true).whereType<File>()) {
      if (audioExtensions.contains(p.extension(f.path).toLowerCase())) return f.path;
    }
    throw StateError('no audio inside the zip');
  }

  @override
  Future<void> stop() => player.stop();

  @override
  Stream<Duration> get duration => player.stream.duration;

  @override
  Stream<bool> get playing => player.stream.playing;

  @override
  Future<void> dispose() => player.dispose();
}
