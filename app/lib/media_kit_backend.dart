import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import 'player.dart';

/// The real player: libmpv through media_kit. Plays MP3, WAV, WMA, M4A and
/// MP4, AVI, MPG video.
class MediaKitBackend implements MediaBackend {
  MediaKitBackend() {
    video = VideoController(player);
  }

  final Player player = Player();
  late final VideoController video;

  @override
  Future<void> open(String path, {Duration? start}) => player.open(Media(path, start: start), play: false);
  @override
  Future<void> play() => player.play();
  @override
  Future<void> pause() => player.pause();
  @override
  Future<void> stop() => player.stop();
  @override
  Future<void> seek(Duration to) => player.seek(to);
  @override
  Future<void> setVolume(double volume) => player.setVolume(volume);
  @override
  Future<void> setAudioFilter(String filter) async {
    final native = player.platform;
    if (native is NativePlayer) await native.setProperty('af', filter);
  }

  @override
  Stream<Duration> get position => player.stream.position;
  @override
  Stream<Duration> get duration => player.stream.duration;
  @override
  Stream<bool> get playing => player.stream.playing;
  @override
  Stream<bool> get completed => player.stream.completed;
  @override
  Future<void> dispose() => player.dispose();
}
