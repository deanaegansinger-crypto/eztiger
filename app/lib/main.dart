import 'dart:io';

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:eztiger_core/eztiger_core.dart';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:window_manager/window_manager.dart';

import 'app_state.dart';
import 'media_kit_backend.dart';
import 'player.dart';
import 'second_screen.dart';
import 'ui/app.dart';

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  // The second-screen output is a separate window that starts here too.
  final thisWindow = await WindowController.fromCurrentEngine();
  if (isOutputWindow(thisWindow.arguments)) return runOutputWindow();

  MediaKit.ensureInitialized();
  await windowManager.ensureInitialized();
  await windowManager.waitUntilReadyToShow(
    const WindowOptions(title: 'EZtiger', size: Size(1400, 860), minimumSize: Size(1000, 640), center: true),
    () async {
      await windowManager.show();
      await windowManager.focus();
    },
  );

  sqfliteFfiInit();
  final dir = await getApplicationSupportDirectory();
  await Directory(dir.path).create(recursive: true);
  final db = await EztigerDatabase.open(databaseFactoryFfi, p.join(dir.path, 'eztiger.db'));

  final backend = MediaKitBackend();
  final engine = KaraokeEngine(backend);
  final state = AppState(db, engine);
  await state.init();

  runApp(
    EztigerApp(
      state: state,
      videoBuilder: (_) => Video(controller: backend.video, controls: NoVideoControls, fill: Colors.black),
      setFullScreen: windowManager.setFullScreen,
      secondScreen: SecondScreen(engine),
    ),
  );
}
