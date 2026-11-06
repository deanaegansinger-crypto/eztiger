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
  String _filter = '';
  double _pitch = 1;

  @override
  Future<void> setAudioFilter(String filter) async {
    _filter = filter;
    await _apply();
  }

  /// The key change, the way media_kit's own setPitch does it: mpv plays
  /// faster (or slower) without pitch correction, which moves the pitch, and
  /// scaletempo stretches the tempo back, so the song (and the CDG lyrics,
  /// which follow its position) keep their time. scaletempo is built into
  /// every libmpv, unlike ffmpeg's audio filters.
  @override
  Future<void> setPitch(double ratio) async {
    _pitch = ratio;
    await _apply();
  }

  Future<void> _apply() async {
    final native = player.platform;
    if (native is! NativePlayer) return;
    final shifted = _pitch != 1;
    await native.setProperty('audio-pitch-correction', shifted ? 'no' : 'yes');
    await native.setProperty('speed', _pitch.toStringAsFixed(8));
    await native.setProperty(
      'af',
      [if (shifted) 'scaletempo=scale=${(1 / _pitch).toStringAsFixed(8)}', if (_filter.isNotEmpty) _filter].join(','),
    );
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
