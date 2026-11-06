import 'dart:io';

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:eztiger_core/eztiger_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:window_manager/window_manager.dart';

import 'app_state.dart';
import 'media_kit_backend.dart';
import 'player.dart';
import 'second_screen.dart';
import 'ui/android_folders.dart';
import 'ui/app.dart';

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  if (Platform.isAndroid) return runOnTablet();

  // The second-screen output is a separate window that starts here too.
  final thisWindow = await WindowController.fromCurrentEngine();
  if (isOutputWindow(thisWindow.arguments)) return runOutputWindow();

  MediaKit.ensureInitialized();
  await windowManager.ensureInitialized();
  await windowManager.waitUntilReadyToShow(
    const WindowOptions(title: 'EZTiger Basic', size: Size(1400, 860), minimumSize: Size(1000, 640), center: true),
    () async {
      await windowManager.show();
      await windowManager.focus();
    },
  );

  runApp(const LoadingApp()); // until the song database is open
  sqfliteFfiInit();
  final dir = await getApplicationSupportDirectory();
  await Directory(dir.path).create(recursive: true);
  final db = await EztigerDatabase.open(databaseFactoryFfi, p.join(dir.path, 'eztiger.db'));

  // Two players, for the 2-deck mode; the second waits idle otherwise.
  final backends = <KaraokeEngine, MediaKitBackend>{};
  for (var i = 0; i < 2; i++) {
    final backend = MediaKitBackend();
    backends[KaraokeEngine(backend)] = backend;
  }
  final decks = backends.keys.toList();
  final state = AppState(db, decks[0], deckB: decks[1]);
  await state.init();

  runApp(
    EztigerApp(
      state: state,
      videoBuilder: (_, e) =>
          Video(key: ObjectKey(e), controller: backends[e]!.video, controls: NoVideoControls, fill: Colors.black),
      setFullScreen: windowManager.setFullScreen,
      secondScreen: SecondScreen(() => state.engine),
    ),
  );
  WidgetsBinding.instance.addPostFrameCallback((_) => state.startUp());
}

/// The Android tablet: one screen, landscape, kept awake, and the library on
/// the SD card.
Future<void> runOnTablet() async {
  MediaKit.ensureInitialized();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]);
  await WakelockPlus.enable();

  runApp(const LoadingApp()); // until the song database is open
  sqfliteFfiInit();
  final dir = await getApplicationSupportDirectory();
  await Directory(dir.path).create(recursive: true);
  final db = await EztigerDatabase.open(databaseFactoryFfi, p.join(dir.path, 'eztiger.db'));

  final backend = MediaKitBackend();
  final engine = KaraokeEngine(backend, tempDir: (await getTemporaryDirectory()).path);
  final state = AppState(db, engine);
  // Only rescan once the app is allowed to read the SD card, or the library
  // would look empty.
  final canRead = await hasStorageAccess();
  await state.init(rescanLibrary: canRead);

  runApp(
    EztigerApp(
      state: state,
      videoBuilder: (_, _) => Video(controller: backend.video, controls: NoVideoControls, fill: Colors.black),
      setFullScreen: (full) =>
          SystemChrome.setEnabledSystemUIMode(full ? SystemUiMode.immersiveSticky : SystemUiMode.edgeToEdge),
    ),
  );
  WidgetsBinding.instance.addPostFrameCallback((_) async {
    if (!canRead && state.roots.isNotEmpty && await ensureStorageAccess()) await state.rescan();
    await state.startUp();
  });
}
