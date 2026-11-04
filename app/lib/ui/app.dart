import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_state.dart';
import '../second_screen.dart';
import '../theme.dart';
import 'common.dart';
import 'home.dart';

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
        title: 'EZtiger',
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
