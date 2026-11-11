import 'dart:io';

import 'package:eztiger/app_state.dart';
import 'package:eztiger/edition.dart';
import 'package:eztiger/player.dart';
import 'package:eztiger/vocal_remover.dart';
import 'package:eztiger_core/eztiger_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'fakes.dart';

void main() {
  sqfliteFfiInit();
  late Directory lib, tools, music, temp;
  late EztigerDatabase db;
  late FakeBackend backend;
  late AppState state;
  late List<String> calls;
  late List<List<String>> ffmpegCalls;

  /// Stand-ins for the tools: demucs.exe fails (no graphics card), as on a
  /// PC without one; demucs-cpu.exe writes the three stems; ffmpeg writes
  /// whatever file it's asked for.
  Future<ProcessResult> fakeRun(String exe, List<String> args) async {
    final name = p.basename(exe);
    calls.add(name);
    if (name == 'demucs.exe') return ProcessResult(1, 1, '', 'No Vulkan adapter found');
    if (name == 'demucs-cpu.exe') {
      final out = args[args.indexOf('-o') + 1];
      for (final s in ['drums', 'bass', 'other']) {
        File(p.join(out, '$s.wav'))
          ..parent.createSync(recursive: true)
          ..writeAsStringSync(s);
      }
      return ProcessResult(1, 0, '', 'Done!');
    }
    ffmpegCalls.add(args);
    File(args.last)
      ..parent.createSync(recursive: true)
      ..writeAsStringSync('instrumental');
    return ProcessResult(1, 0, '', '');
  }

  setUp(() async {
    isPro = true;
    calls = [];
    ffmpegCalls = [];
    lib = makeLibrary();
    tools = Directory.systemTemp.createTempSync('ezt_tools');
    music = Directory.systemTemp.createTempSync('ezt_music');
    temp = Directory.systemTemp.createTempSync('ezt_temp');
    for (final t in ['demucs.exe', 'demucs-cpu.exe', 'ffmpeg.exe']) {
      File(p.join(tools.path, t)).writeAsStringSync('');
    }
    db = await EztigerDatabase.open(databaseFactoryFfiNoIsolate, inMemoryDatabasePath);
    backend = FakeBackend();
    state = AppState(db, KaraokeEngine(backend, scanEdges: (_) async => null));
    state.vocalRemover = VocalRemover(
      toolsDir: tools.path,
      outDir: p.join(music.path, VocalRemover.folderName),
      tempDir: temp.path,
      run: fakeRun,
    );
    await state.init(rescanLibrary: false);
    await state.addRootFolder(lib.path);
  });

  tearDown(() async {
    state.dispose();
    await db.close();
    for (final d in [lib, tools, music, temp]) {
      if (d.existsSync()) d.deleteSync(recursive: true);
    }
  });

  Track song(String fileName) => state.results.expand((g) => g.versions).firstWhere((t) => t.fileName == fileName);

  Future<void> waitForJobs() async {
    for (var i = 0; i < 200 && (state.vocalJob != null || state.vocalJobs.isNotEmpty); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
  }

  test('names: the original with EZVocrem on the end; a video stays a video', () {
    final waterloo = song('Abba - Waterloo.mp3'), video = song('Queen - Bohemian Rhapsody.mp4');
    expect(VocalRemover.fileNameFor(waterloo), 'Abba - Waterloo EZVocrem.mp3');
    expect(VocalRemover.titleFor(waterloo), 'Waterloo EZVocrem');
    expect(VocalRemover.fileNameFor(video), 'Queen - Bohemian Rhapsody EZVocrem.mp4');
    expect(VocalRemover.isInstrumental(r'C:\Music\EZVocalremoved\Abba - Waterloo EZVocrem.mp3'), isTrue);
    expect(VocalRemover.isInstrumental('Abba - Waterloo.mp3'), isFalse);
  });

  test('Remove vocals makes the instrumental in Music\\EZVocalremoved, with its tags and lyrics', () async {
    final waterloo = song('Abba - Waterloo.mp3');
    state.removeVocals([waterloo]);
    await waitForJobs();

    final folder = p.join(music.path, 'EZVocalremoved');
    final out = p.join(folder, 'Abba - Waterloo EZVocrem.mp3');
    expect(File(out).existsSync(), isTrue, reason: state.status);
    // The CDG goes with it under the same name, so it plays as karaoke on its own.
    expect(File(p.join(folder, 'Abba - Waterloo EZVocrem.cdg')).existsSync(), isTrue);
    // The graphics card first; without one, the processor.
    expect(calls.where((c) => c.startsWith('demucs')), ['demucs.exe', 'demucs-cpu.exe']);
    // Drums, bass and everything else mixed (no vocals), the song's tags kept,
    // EZVocrem on the end of the title.
    final mix = ffmpegCalls.single.join(' ');
    expect(mix, contains('amix=inputs=3'));
    expect(mix, isNot(contains('vocals')));
    expect(mix, contains('-map_metadata 3'));
    expect(mix, contains('title=Waterloo EZVocrem'));
    expect(mix, contains('artist=Abba'));
    expect(mix, contains('libmp3lame'));
    // Remembered, and the instrumental is in the library to search and queue.
    expect(state.vocalRemoved[waterloo.path], out);
    expect(await db.getMeta('vocal_removed'), contains('EZVocrem'));
    expect(state.hasInstrumental(waterloo), isTrue);
    expect(state.roots.any((r) => p.equals(r.path, folder)), isTrue);
    expect(state.status, contains('Vocals removed from 1 song'));
    // Asking again for an instrumental itself does nothing.
    state.removeVocals([await db.tracks.byPath(out) ?? waterloo]);
    expect(state.vocalJobs.where((j) => VocalRemover.isInstrumental(j.path)), isEmpty);
  });

  test('Vocal cut plays the AI instrumental instead of filtering, and swaps back when off', () async {
    final waterloo = song('Abba - Waterloo.mp3');
    state.removeVocals([waterloo]);
    await waitForJobs();
    final out = state.vocalRemoved[waterloo.path]!;

    await state.playNow(waterloo, autostart: false);
    expect(backend.calls.last, 'pause');
    expect(backend.calls, contains('open Abba - Waterloo.mp3'));

    await state.setVocalCut(true);
    expect(backend.calls, contains('open ${p.basename(out)}'));
    expect(state.engine.playingInstrumental, isTrue);
    expect(backend.audioFilter, '', reason: 'no filter on the instrumental');
    expect(state.engine.hasCdg, isTrue, reason: 'the lyrics still come from the song');

    await state.setVocalCut(false);
    expect(backend.calls.last == 'pause' || backend.calls.last == 'play', isTrue);
    expect(backend.calls.where((c) => c == 'open Abba - Waterloo.mp3'), hasLength(2));
    expect(state.engine.playingInstrumental, isFalse);

    // A song without one still gets the live filter.
    final prayer = song('Bon Jovi - Livin On A Prayer.mp3');
    await state.setVocalCut(true);
    await state.playNow(prayer, autostart: false);
    expect(state.engine.playingInstrumental, isFalse);
    expect(backend.audioFilter, contains('surround'));
  });

  test('a failed separation is reported, and the next song still goes ahead', () async {
    final waterloo = song('Abba - Waterloo.mp3'), prayer = song('Bon Jovi - Livin On A Prayer.mp3');
    File(p.join(tools.path, 'demucs-cpu.exe')).deleteSync(); // only the GPU one, which fails here
    state.removeVocals([waterloo, prayer]);
    await waitForJobs();
    expect(state.vocalRemoved, isEmpty);
    expect(state.status, contains('Could not remove vocals'));
    expect(state.status, contains('No Vulkan adapter found'));
  });
}
