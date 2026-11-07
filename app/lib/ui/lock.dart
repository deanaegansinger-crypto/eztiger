import 'dart:async';

import 'package:flutter/material.dart';

import '../edition.dart';
import '../theme.dart';
import 'common.dart';

/// EZTiger Pro's screen lock, for the tablet on the mic stand: while locked,
/// every tap is ignored, so a bump or a stray finger can't stop, skip or
/// change a song. The song plays on. Press and hold the lock to unlock.
class LockShield extends StatefulWidget {
  const LockShield({super.key, required this.child});
  final Widget child;

  /// How long to press the lock to unlock it.
  static const holdFor = Duration(milliseconds: 800);

  @override
  State<LockShield> createState() => _LockShieldState();
}

class _LockShieldState extends State<LockShield> {
  bool _hint = false;
  Timer? _hintTimer;

  @override
  void dispose() {
    _hintTimer?.cancel();
    super.dispose();
  }

  void _showHint() {
    setState(() => _hint = true);
    _hintTimer?.cancel();
    _hintTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _hint = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    return ListenableBuilder(
      listenable: s,
      builder: (context, child) {
        final locked = isPro && s.locked;
        return Stack(
          children: [
            AbsorbPointer(absorbing: locked, child: child),
            if (locked) ...[
              // Swallows every tap, and says how to unlock.
              Positioned.fill(
                child: GestureDetector(
                  key: const Key('lock-shield'),
                  behavior: HitTestBehavior.opaque,
                  onTap: _showHint,
                  onDoubleTap: _showHint,
                  onLongPress: _showHint,
                  onPanStart: (_) => _showHint(),
                ),
              ),
              Positioned(
                top: 14,
                left: 0,
                right: 0,
                child: Center(
                  child: _UnlockButton(hint: _hint, onUnlock: () => s.setLocked(false)),
                ),
              ),
            ],
          ],
        );
      },
      child: widget.child,
    );
  }
}

/// The lock that sits over the locked screen: press and hold to unlock. A
/// ring fills while it is held.
class _UnlockButton extends StatefulWidget {
  const _UnlockButton({required this.hint, required this.onUnlock});
  final bool hint;
  final VoidCallback onUnlock;

  @override
  State<_UnlockButton> createState() => _UnlockButtonState();
}

class _UnlockButtonState extends State<_UnlockButton> with SingleTickerProviderStateMixin {
  late final _hold = AnimationController(vsync: this, duration: LockShield.holdFor)
    ..addStatusListener((st) {
      if (st == AnimationStatus.completed) widget.onUnlock();
    });

  void _letGo() {
    if (_hold.status != AnimationStatus.completed) _hold.reverse();
  }

  @override
  void dispose() {
    _hold.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Listener(
    // Raw touches rather than a tap, so nothing else can claim the press
    // while it is held.
    key: const Key('lock-unlock'),
    behavior: HitTestBehavior.opaque,
    onPointerDown: (_) => _hold.forward(from: 0),
    onPointerUp: (_) => _letGo(),
    onPointerCancel: (_) => _letGo(),
    child: AnimatedBuilder(
      animation: _hold,
      builder: (context, _) => Container(
        padding: const EdgeInsets.fromLTRB(10, 8, 18, 8),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.82),
          borderRadius: BorderRadius.circular(30),
          border: Border.all(color: widget.hint ? EzColors.red : EzColors.brass, width: 2),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 40,
              height: 40,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  CircularProgressIndicator(
                    value: _hold.value,
                    strokeWidth: 3,
                    color: EzColors.brass,
                    backgroundColor: Colors.white12,
                  ),
                  Icon(Icons.lock, size: 22, color: EzColors.brass),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Text(
              widget.hint ? 'LOCKED · press and hold the lock to unlock' : 'LOCKED',
              style: TextStyle(
                fontFamily: vfdFont,
                fontSize: 15,
                letterSpacing: 1.5,
                color: widget.hint ? EzColors.red : EzColors.brass,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

/// 🔒 in the top bar and the Stage view: locks the screen (Pro, when the
/// lock is switched on in ☰ Menu).
class LockButton extends StatelessWidget {
  const LockButton({super.key, this.big = false});
  final bool big;

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    return IconButton(
      key: const Key('lock-screen'),
      tooltip: 'Lock the screen (press and hold the lock to unlock)',
      iconSize: big ? 30 : 20,
      style: big
          ? IconButton.styleFrom(
              minimumSize: const Size(52, 52),
              side: BorderSide(color: EzColors.brass),
              foregroundColor: EzColors.brass,
            )
          : IconButton.styleFrom(
              foregroundColor: EzColors.brass,
              padding: EdgeInsets.zero,
              minimumSize: const Size(34, 34),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
      onPressed: () => s.setLocked(true),
      icon: const Icon(Icons.lock_open),
    );
  }
}
