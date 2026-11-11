// Runs Pro's Vocal cut filter (app/lib/audio_filters.dart) through real
// ffmpeg and measures what it does, so a change to it is heard-tested on
// every build:
//   - a "vocal" in the middle (1 kHz, the same in both speakers) must drop a lot,
//   - an instrument panned hard left (500 Hz) must stay,
//   - the bass in the middle (60 Hz) must stay.
// Needs ffmpeg on the PATH. Run from the repo root: dart run tool/check_vocal_cut.dart
import 'dart:io';

import '../app/lib/audio_filters.dart';

Future<String> ffmpeg(List<String> args) async {
  final r = await Process.run('ffmpeg', ['-hide_banner', '-nostats', ...args]);
  if (r.exitCode != 0) {
    stderr.writeln(r.stderr);
    if (Platform.environment['GITHUB_ACTIONS'] == 'true') {
      final tail = '${r.stderr}'.trim().split('\n').reversed.take(4).toList().reversed.join(' / ');
      print('::error title=ffmpeg failed::${tail.replaceAll('%', '%25')}');
      // The surround filter's options in this ffmpeg, to see what it accepts.
      final h = await Process.run('ffmpeg', ['-hide_banner', '-h', 'filter=surround']);
      final opts = RegExp(r'^\s+(\w+)\s+<', multiLine: true).allMatches('${h.stdout}').map((m) => m.group(1)).toSet();
      print('::notice title=surround options::${opts.join(' ')}');
    }
    exit(2);
  }
  return '${r.stderr}';
}

/// The average level (dB) of [file] around [hz], one channel or both.
Future<double> level(String file, int hz, {String channels = 'both'}) async {
  final pick = switch (channels) { 'left' => 'pan=mono|c0=c0,', 'right' => 'pan=mono|c0=c1,', _ => '' };
  final out = await ffmpeg([
    '-i', file, '-af', '${pick}atrim=start=1,bandpass=f=$hz:width_type=q:w=12,volumedetect', '-f', 'null', '-'
  ]);
  final m = RegExp(r'mean_volume: (-?[\d.]+|-inf) dB').firstMatch(out);
  if (m == null) throw StateError('no level for $hz Hz');
  return m.group(1) == '-inf' ? -150 : double.parse(m.group(1)!);
}

Future<void> main() async {
  final dir = Directory.systemTemp.createTempSync('vocal_cut');
  final mix = '${dir.path}/mix.wav', out = '${dir.path}/cut.wav';
  // The test song: vocal and bass in the middle, a guitar hard left.
  await ffmpeg([
    '-y',
    '-f', 'lavfi', '-i', 'sine=f=1000:d=6:sample_rate=48000',
    '-f', 'lavfi', '-i', 'sine=f=500:d=6:sample_rate=48000',
    '-f', 'lavfi', '-i', 'sine=f=60:d=6:sample_rate=48000',
    '-f', 'lavfi', '-i', 'sine=f=2500:d=6:sample_rate=48000',
    '-filter_complex',
    '[0]pan=stereo|c0=0.5*c0|c1=0.5*c0[v];[1]pan=stereo|c0=0.5*c0|c1=0*c0[g];'
        '[2]pan=stereo|c0=0.5*c0|c1=0.5*c0[b];[3]pan=stereo|c0=0.45*c0|c1=0.15*c0[k];'
        '[v][g][b][k]amix=inputs=4:normalize=0[o]',
    '-map', '[o]', mix,
  ]);
  await ffmpeg(['-y', '-i', mix, '-af', vocalCutGraph, out]);

  final checks = [
    ('vocal in the middle (1 kHz)', 1000, 'both', (double drop) => drop >= 12, 'drop at least 12 dB'),
    ('guitar hard left (500 Hz)', 500, 'left', (double drop) => drop.abs() <= 4, 'stay within 4 dB'),
    ('bass in the middle (60 Hz)', 60, 'both', (double drop) => drop.abs() <= 4, 'stay within 4 dB'),
    ('keys half left (2.5 kHz)', 2500, 'both', (double drop) => drop.abs() <= 9, 'stay within 9 dB'),
  ];
  var failed = false;
  for (final (name, hz, ch, ok, rule) in checks) {
    final before = await level(mix, hz, channels: ch), after = await level(out, hz, channels: ch);
    final drop = before - after;
    final pass = ok(drop);
    failed |= !pass;
    final line = '${pass ? 'PASS' : 'FAIL'}  $name: ${before.toStringAsFixed(1)} dB -> ${after.toStringAsFixed(1)} dB '
        '(${drop >= 0 ? 'down' : 'up'} ${drop.abs().toStringAsFixed(1)} dB; must $rule)';
    print(line);
    // Shown on the run's summary page too, without signing in to read the log.
    if (Platform.environment['GITHUB_ACTIONS'] == 'true') print('::notice title=Vocal cut::$line');
  }
  dir.deleteSync(recursive: true);
  if (failed) {
    print('::error title=Vocal cut::The Vocal cut filter did not do what it should (see above)');
    exit(1);
  }
}
