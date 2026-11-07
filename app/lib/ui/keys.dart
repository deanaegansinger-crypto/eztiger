import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_state.dart';
import '../edition.dart';
import '../player.dart';
import 'read_me.dart';

/// EZTiger Pro's single keys (Windows), alongside Space for play/pause:
///
/// * M mutes and unmutes.
/// * Q adds the selected songs to Tonight's playlist; Shift+Q makes them
///   the next songs.
/// * S switches between the Stage view and the library.
/// * / jumps to the search box.
/// * F1 opens the Read me.
/// * R back to the start, N next song, X mix into the next song now.
/// * Z / C skip back / forward 5 seconds.
/// * U / D volume up / down.
/// * K / L key up / down a semitone, 0 back to the song's own key.
/// * B locks the screen (hold the lock to unlock).
///
/// They do nothing while typing in a box (the search box gets its letters),
/// or while the screen is locked.
class ProKeys extends StatefulWidget {
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
    const SingleActivator(LogicalKeyboardKey.keyR): ProKey.restart,
    const SingleActivator(LogicalKeyboardKey.keyN): ProKey.next,
    const SingleActivator(LogicalKeyboardKey.keyX): ProKey.mix,
    const SingleActivator(LogicalKeyboardKey.keyZ): ProKey.back,
    const SingleActivator(LogicalKeyboardKey.keyC): ProKey.forward,
    const SingleActivator(LogicalKeyboardKey.keyU): ProKey.louder,
    const SingleActivator(LogicalKeyboardKey.keyD): ProKey.quieter,
    const SingleActivator(LogicalKeyboardKey.keyK): ProKey.keyUp,
    const SingleActivator(LogicalKeyboardKey.keyL): ProKey.keyDown,
    const SingleActivator(LogicalKeyboardKey.digit0): ProKey.keyReset,
    const SingleActivator(LogicalKeyboardKey.numpad0): ProKey.keyReset,
    const SingleActivator(LogicalKeyboardKey.keyB): ProKey.lock,
  };

  @override
  State<ProKeys> createState() => _ProKeysState();
}

class _ProKeysState extends State<ProKeys> {
  // A keyboard handler for the whole app, so the keys work wherever the
  // focus is (or isn't), not only when something in the window has it.
  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_onKey);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKey);
    super.dispose();
  }

  bool _onKey(KeyEvent e) {
    if (!isPro || e is! KeyDownEvent || !mounted) return false;
    // Not while a dialog or menu is open over the main screen.
    if (!(ModalRoute.of(context)?.isCurrent ?? true)) return false;
    final hit = ProKeys.keys.entries.where((k) => k.key.accepts(e, HardwareKeyboard.instance)).firstOrNull;
    if (hit == null) return false;
    final action = _KeyAction(widget.state, context);
    final intent = _KeyIntent(hit.value);
    if (!action.isEnabled(intent)) return false;
    action.invoke(intent);
    return true;
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

enum ProKey {
  mute,
  queue,
  queueNext,
  stage,
  search,
  readMe,
  restart,
  next,
  mix,
  back,
  forward,
  louder,
  quieter,
  keyUp,
  keyDown,
  keyReset,
  lock,
}

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
      case ProKey.restart:
        s.previous();
      case ProKey.next:
        s.next();
      case ProKey.mix:
        s.mixNow();
      case ProKey.back || ProKey.forward:
        final e = s.engine;
        if (e.current == null) return null;
        final step = Duration(seconds: intent.key == ProKey.back ? -5 : 5);
        var to = e.position + step;
        if (to < Duration.zero) to = Duration.zero;
        if (to > e.duration) to = e.duration;
        e.seek(to);
      case ProKey.louder || ProKey.quieter:
        final e = s.engine;
        e.setVolume((e.volume + (intent.key == ProKey.louder ? 5 : -5)).clamp(0, 100).toDouble());
      case ProKey.keyUp:
        if (s.engine.current != null && s.engine.keyShift < KaraokeEngine.maxKey) s.keyUp();
      case ProKey.keyDown:
        if (s.engine.current != null && s.engine.keyShift > KaraokeEngine.minKey) s.keyDown();
      case ProKey.keyReset:
        if (s.engine.current != null) s.keyReset();
      case ProKey.lock:
        if (s.lockEnabled) s.setLocked(true);
    }
    return null;
  }
}
