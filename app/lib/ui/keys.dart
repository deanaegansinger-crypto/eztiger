import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_state.dart';
import '../edition.dart';
import 'read_me.dart';

/// EZTiger Pro's single keys (Windows), alongside Space for play/pause:
///
/// * M mutes and unmutes.
/// * Q adds the selected songs to Tonight's playlist; Shift+Q makes them
///   the next songs.
/// * S switches between the Stage view and the library.
/// * / jumps to the search box.
/// * F1 opens the Read me.
///
/// They do nothing while typing in a box (the search box gets its letters),
/// or while the screen is locked.
class ProKeys extends StatelessWidget {
  const ProKeys({super.key, required this.state, required this.child});
  final AppState state;
  final Widget child;

  static final keys = <ShortcutActivator, ProKey>{
    const SingleActivator(LogicalKeyboardKey.keyM): ProKey.mute,
    const SingleActivator(LogicalKeyboardKey.keyQ): ProKey.queue,
    const SingleActivator(LogicalKeyboardKey.keyQ, shift: true): ProKey.queueNext,
    const SingleActivator(LogicalKeyboardKey.keyS): ProKey.stage,
    const SingleActivator(LogicalKeyboardKey.slash): ProKey.search,
    const SingleActivator(LogicalKeyboardKey.numpadDivide): ProKey.search,
    const SingleActivator(LogicalKeyboardKey.f1): ProKey.readMe,
  };

  @override
  Widget build(BuildContext context) {
    if (!isPro) return child;
    return Shortcuts(
      shortcuts: {for (final e in keys.entries) e.key: _KeyIntent(e.value)},
      child: Actions(actions: {_KeyIntent: _KeyAction(state, context)}, child: child),
    );
  }
}

enum ProKey { mute, queue, queueNext, stage, search, readMe }

class _KeyIntent extends Intent {
  const _KeyIntent(this.key);
  final ProKey key;
}

class _KeyAction extends Action<_KeyIntent> {
  _KeyAction(this.s, this.context);
  final AppState s;
  final BuildContext context;

  /// Typing in a text box: let the box have the key.
  static bool get _typing =>
      FocusManager.instance.primaryFocus?.context?.findAncestorWidgetOfExactType<EditableText>() != null;

  @override
  bool isEnabled(_KeyIntent intent) => !_typing && !s.locked;

  @override
  Object? invoke(_KeyIntent intent) {
    switch (intent.key) {
      case ProKey.mute:
        s.engine.toggleMute();
      case ProKey.queue:
        s.enqueueAll(s.selectedTracks());
      case ProKey.queueNext:
        s.enqueueNext(s.selectedTracks());
      case ProKey.stage:
        s.setStageView(!s.stageView);
      case ProKey.search:
        if (s.stageView) s.setStageView(false);
        WidgetsBinding.instance.addPostFrameCallback((_) => s.searchFocus.requestFocus());
      case ProKey.readMe:
        if (context.mounted) showReadMe(context);
    }
    return null;
  }
}
