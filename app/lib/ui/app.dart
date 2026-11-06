import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_state.dart';
import '../second_screen.dart';
import '../theme.dart';
import 'common.dart';
import 'home.dart';
import 'logo.dart';

class EztigerApp extends StatelessWidget {
  const EztigerApp({super.key, required this.state, this.videoBuilder, this.setFullScreen, this.secondScreen});
  final SecondScreen? secondScreen;
  final AppState state;
  final WidgetBuilder? videoBuilder;
  final Future<void> Function(bool)? setFullScreen;

  @override
  Widget build(BuildContext context) => AppScope(
    state: state,
    videoBuilder: videoBuilder,
    secondScreen: secondScreen,
    child: ListenableBuilder(
      listenable: Listenable.merge([state, ?secondScreen]),
      builder: (context, _) => MaterialApp(
        title: 'EZTiger Basic',
        debugShowCheckedModeBanner: false,
        theme: buildTheme(state.dark),
        // Space plays/pauses anywhere, except while typing in a text box
        // (the search box keeps its spaces).
        shortcuts: {
          ...WidgetsApp.defaultShortcuts,
          const SingleActivator(LogicalKeyboardKey.space): const PlayPauseIntent(),
          const SingleActivator(LogicalKeyboardKey.space, control: true): const PlayPauseIntent(),
        },
        actions: {
          ...WidgetsApp.defaultActions,
          PlayPauseIntent: CallbackAction<PlayPauseIntent>(onInvoke: (_) => state.playPause()),
        },
        home: HomeScreen(setFullScreen: setFullScreen),
      ),
    ),
  );
}

class PlayPauseIntent extends Intent {
  const PlayPauseIntent();
}

/// Shown at start-up while the song database opens, before the app is ready.
class LoadingApp extends StatelessWidget {
  const LoadingApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'EZTiger Basic',
    debugShowCheckedModeBanner: false,
    theme: buildTheme(true),
    home: const Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            EzLogo(size: 140),
            SizedBox(height: 16),
            Text(
              'EZTIGER',
              style: TextStyle(fontSize: 30, fontWeight: FontWeight.w900, color: EzColors.brass, letterSpacing: 6),
            ),
            SizedBox(height: 24),
            SizedBox(width: 28, height: 28, child: CircularProgressIndicator(color: EzColors.cyan)),
            SizedBox(height: 16),
            Text('Loading your song library… please wait', style: TextStyle(fontSize: 18, color: EzColors.cyan)),
            SizedBox(height: 6),
            Text(
              'It\'s working: a big collection can take a minute.',
              style: TextStyle(fontSize: 13, color: Colors.white70),
            ),
          ],
        ),
      ),
    ),
  );
}
