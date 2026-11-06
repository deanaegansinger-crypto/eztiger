import 'dart:async';
import 'dart:io';

import 'package:eztiger/player.dart';
import 'package:path/path.dart' as p;

class FakeBackend implements MediaBackend {
  final _pos = StreamController<Duration>.broadcast();
  final _dur = StreamController<Duration>.broadcast();
  final _playing = StreamController<bool>.broadcast();
  final _done = StreamController<bool>.broadcast();
  final calls = <String>[];
  double volume = 100;

  @override
  Future<void> open(String path, {Duration? start}) async {
    calls.add('open ${p.basename(path)}');
    opensAt.add(start ?? Duration.zero);
    _dur.add(const Duration(minutes: 3));
  }

  @override
  Future<void> play() async {
    calls.add('play');
    _playing.add(true);
  }

  @override
  Future<void> pause() async {
    calls.add('pause');
    _playing.add(false);
  }

  @override
  Future<void> stop() async {
    calls.add('stop');
    _playing.add(false);
  }

  @override
  Future<void> seek(Duration to) async {
    calls.add('seek $to');
    seeks.add(to);
  }

  final seeks = <Duration>[];
  final opensAt = <Duration>[];
  @override
  Future<void> setVolume(double v) async => volume = v;
  String audioFilter = '';
  double pitch = 1;
  @override
  Future<void> setPitch(double ratio) async => pitch = ratio;
  @override
  Future<void> setAudioFilter(String filter) async => audioFilter = filter;
  void finish() => _done.add(true);
  void at(Duration d) => _pos.add(d);

  @override
  Stream<Duration> get position => _pos.stream;
  @override
  Stream<Duration> get duration => _dur.stream;
  @override
  Stream<bool> get playing => _playing.stream;
  @override
  Stream<bool> get completed => _done.stream;
  @override
  Future<void> dispose() async {}
}

/// A tiny karaoke folder on disk.
Directory makeLibrary() {
  final root = Directory.systemTemp.createTempSync('eztiger_app_test');
  void file(String rel, [int bytes = 10]) {
    final f = File(p.join(root.path, rel));
    f.parent.createSync(recursive: true);
    f.writeAsBytesSync(List.filled(bytes, 0));
  }

  file('Pop/Abba - Waterloo.mp3');
  file('Pop/Abba - Waterloo.cdg', 24 * 300);
  file('Pop/Queen - Bohemian Rhapsody.mp4');
  file('Rock/Bon Jovi - Livin On A Prayer.mp3');
  return root;
}
