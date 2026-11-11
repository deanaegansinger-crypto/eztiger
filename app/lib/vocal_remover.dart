import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:eztiger_core/eztiger_core.dart';
import 'package:path/path.dart' as p;

/// EZTiger Pro on Windows: "Remove vocals (AI)". The Demucs model splits a
/// song into its parts (drums, bass, everything else, vocals); everything
/// but the vocals is mixed back into an instrumental, saved in the Music
/// folder's EZVocalremoved folder as the original's name plus " EZVocrem",
/// with the song's tags (EZVocrem on the end of the title). The CDG (and any
/// lyric sheet) is copied beside it under the same name, so it is a
/// complete karaoke track of its own.
///
/// The tools come with EZTiger Pro, in tools\ beside eztiger.exe:
/// demucs.exe (on the graphics card), demucs-cpu.exe (the same on the
/// processor, slower, for PCs without a suitable graphics card) and
/// ffmpeg.exe. The model (84 MB) downloads by itself the first time.
class VocalRemover {
  VocalRemover({required this.toolsDir, required this.outDir, required this.tempDir, RunTool? run})
      : run = run ?? runTool;

  /// The folder the instrumentals go in, inside the Music folder.
  static const folderName = 'EZVocalremoved';

  /// Added to the file name and the title of each instrumental.
  static const mark = 'EZVocrem';

  final String toolsDir, outDir, tempDir;
  final RunTool run;

  String get _ffmpeg => p.join(toolsDir, 'ffmpeg.exe');
  String get _demucs => p.join(toolsDir, 'demucs.exe');
  String get _demucsCpu => p.join(toolsDir, 'demucs-cpu.exe');

  /// This PC's, when the tools are there (EZTiger Pro on Windows); else null.
  static Future<VocalRemover?> forThisPc() async {
    if (!Platform.isWindows) return null;
    final tools = p.join(p.dirname(Platform.resolvedExecutable), 'tools');
    if (!File(p.join(tools, 'ffmpeg.exe')).existsSync()) return null;
    if (!File(p.join(tools, 'demucs.exe')).existsSync() && !File(p.join(tools, 'demucs-cpu.exe')).existsSync()) {
      return null;
    }
    return VocalRemover(
      toolsDir: tools,
      outDir: p.join(await musicFolder(), folderName),
      tempDir: Directory.systemTemp.path,
    );
  }

  /// The Music folder (wherever Windows keeps it, OneDrive included).
  static Future<String> musicFolder() async {
    try {
      final r = await Process.run('powershell', [
        '-NoProfile',
        '-Command',
        "[Environment]::GetFolderPath('MyMusic')",
      ]);
      final path = '${r.stdout}'.trim();
      if (r.exitCode == 0 && path.isNotEmpty) return path;
    } catch (_) {}
    return p.join(Platform.environment['USERPROFILE'] ?? '.', 'Music');
  }

  /// The instrumental's file name: the original's, with " EZVocrem" before
  /// the extension. Songs come out as MP3 (a zipped MP3+G too); videos as MP4.
  static String fileNameFor(Track t) {
    final base = p.basenameWithoutExtension(t.fileName);
    return '$base $mark${t.kind == 'video' ? '.mp4' : '.mp3'}';
  }

  /// The instrumental's title tag.
  static String titleFor(Track t) => '${t.title} $mark';

  /// True for a file this made.
  static bool isInstrumental(String path) => p.basenameWithoutExtension(path).endsWith(' $mark');

  /// Makes the instrumental of [t] and returns where it is. [onStep] is told
  /// what it is doing ("Separating…", "Mixing…").
  Future<String> remove(Track t, {void Function(String step)? onStep}) async {
    final work = Directory(p.join(tempDir, 'ezvocrem_${t.id}_${DateTime.now().millisecondsSinceEpoch}'))
      ..createSync(recursive: true);
    try {
      // 1. The sound to split, and the lyric files to copy.
      var source = t.path;
      var cdg = t.cdgPath;
      final lyrics = t.lyricsPath;
      if (t.kind == 'cdg_zip') {
        onStep?.call('Unzipping…');
        final dir = p.join(work.path, 'zip');
        await extractFileToDisk(t.path, dir);
        String? mp3;
        for (final f in Directory(dir).listSync(recursive: true).whereType<File>()) {
          final ext = p.extension(f.path).toLowerCase();
          if (ext == '.cdg') cdg ??= f.path;
          if (audioExtensions.contains(ext)) mp3 ??= f.path;
        }
        if (mp3 == null) throw VocalRemovalException('There is no song inside ${t.fileName}.');
        source = mp3;
      } else if (t.kind == 'video') {
        onStep?.call("Reading the video's sound…");
        source = p.join(work.path, 'sound.wav');
        await _ffmpegRun(['-y', '-i', t.path, '-vn', '-ac', '2', '-c:a', 'pcm_s16le', source]);
      }

      // 2. Split it: the graphics card first, the processor if that fails.
      final stems = p.join(work.path, 'stems');
      final args = ['-m', 'htdemucs', '-s', 'drums,bass,other', '-o', stems, source];
      var done = false;
      final errors = <String>[];
      for (final (exe, step) in [
        (_demucs, 'Separating the vocals…'),
        (_demucsCpu, 'Separating the vocals (on the processor, slower)…'),
      ]) {
        if (!File(exe).existsSync()) continue;
        onStep?.call(step);
        final r = await run(exe, args);
        if (r.exitCode == 0 && _stemsThere(stems)) {
          done = true;
          break;
        }
        errors.add(_lastLines('${r.stderr}'));
      }
      if (!done) throw VocalRemovalException('Demucs could not separate it. ${errors.join(' / ')}');

      // 3. Mix everything but the vocals, with the song's tags.
      onStep?.call('Mixing the instrumental…');
      Directory(outDir).createSync(recursive: true);
      final out = p.join(outDir, fileNameFor(t));
      final partial = p.join(work.path, 'out${p.extension(out)}');
      final parts = [for (final s in _stemNames) p.join(stems, '$s.wav')];
      final tags = [
        '-metadata', 'title=${titleFor(t)}',
        if (t.artist != null) ...['-metadata', 'artist=${t.artist}'],
        '-metadata', 'comment=Vocals removed by EZTiger (Demucs AI)',
      ];
      if (t.kind == 'video') {
        await _ffmpegRun([
          '-y', '-i', t.path, for (final s in parts) ...['-i', s],
          '-filter_complex', '[1:a][2:a][3:a]amix=inputs=3:normalize=0[a]',
          '-map', '0:v', '-map', '[a]', '-c:v', 'copy', '-c:a', 'aac', '-b:a', '256k',
          '-map_metadata', '0', ...tags, partial,
        ]);
      } else {
        await _ffmpegRun([
          '-y', for (final s in parts) ...['-i', s], '-i', source,
          '-filter_complex', '[0:a][1:a][2:a]amix=inputs=3:normalize=0[a]',
          '-map', '[a]', '-map_metadata', '3', ...tags, '-id3v2_version', '3',
          '-c:a', 'libmp3lame', '-q:a', '2', partial,
        ]);
      }
      // Only a finished file goes in the folder.
      if (File(out).existsSync()) File(out).deleteSync();
      File(partial).copySync(out);

      // 4. The lyrics, under the same name, so the pair plays on its own.
      final base = p.basenameWithoutExtension(out);
      if (cdg != null && File(cdg).existsSync()) File(cdg).copySync(p.join(outDir, '$base.cdg'));
      if (lyrics != null && File(lyrics).existsSync()) {
        File(lyrics).copySync(p.join(outDir, '$base${p.extension(lyrics)}'));
      }
      return out;
    } finally {
      try {
        work.deleteSync(recursive: true);
      } catch (_) {}
    }
  }

  static const _stemNames = ['drums', 'bass', 'other'];
  bool _stemsThere(String dir) => _stemNames.every((s) => File(p.join(dir, '$s.wav')).existsSync());

  Future<void> _ffmpegRun(List<String> args) async {
    final r = await run(_ffmpeg, ['-hide_banner', '-loglevel', 'error', ...args]);
    if (r.exitCode != 0) throw VocalRemovalException('ffmpeg: ${_lastLines('${r.stderr}')}');
  }

  static String _lastLines(String s) => s.trim().split(RegExp(r'[\r\n]+')).reversed.take(3).toList().reversed.join(' ');
}

/// Runs a tool and waits for it; replaced in tests.
typedef RunTool = Future<ProcessResult> Function(String exe, List<String> args);

Future<ProcessResult> runTool(String exe, List<String> args) =>
    Process.run(exe, args, stdoutEncoding: utf8, stderrEncoding: utf8, runInShell: false);

class VocalRemovalException implements Exception {
  VocalRemovalException(this.message);
  final String message;
  @override
  String toString() => message;
}
