import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../platform.dart';
import '../theme.dart';
import 'common.dart';
import 'lock.dart';
import 'output_panel.dart';
import 'queue_panel.dart';
import 'rack.dart';
import 'stage_view.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, this.setFullScreen});

  /// Puts the window into or out of full screen (null in tests).
  final Future<void> Function(bool)? setFullScreen;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool fullScreen = false;
  // Taller on the tablet, where the rows are taller for a finger.
  double queueHeight = touchUi ? 330 : 210;

  Future<void> _setFull(bool v) async {
    setState(() => fullScreen = v);
    await widget.setFullScreen?.call(v);
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    // While the screen is locked, the keys and Back do nothing either.
    void unlessLocked(VoidCallback f) {
      if (!s.locked) f();
    }

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () => unlessLocked(() => _setFull(false)),
        const SingleActivator(LogicalKeyboardKey.f11): () => unlessLocked(() => _setFull(!fullScreen)),
        const SingleActivator(LogicalKeyboardKey.arrowRight, control: true): () => unlessLocked(s.next),
      },
      child: PopScope(
        // The tablet's Back button leaves full screen first.
        canPop: !fullScreen && !s.locked,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop && !s.locked) _setFull(false);
        },
        child: Focus(
          autofocus: true,
          child: Scaffold(
            body: LockShield(
              child: fullScreen
                  ? GestureDetector(onDoubleTap: () => _setFull(false), child: const KaraokeScreen())
                  : s.stageView
                  ? SafeArea(child: StageView(onFullScreen: () => _setFull(true)))
                  : SafeArea(
                      child: LayoutBuilder(
                        builder: (context, c) {
                          final rackWidth = (c.maxWidth * 0.42).clamp(400.0, 620.0);
                          return Row(
                            children: [
                              SizedBox(width: rackWidth, child: const Rack()),
                              Expanded(
                                child: _Stage(
                                  queueHeight: queueHeight,
                                  onResize: (h) => setState(() => queueHeight = h),
                                  onFullScreen: () => _setFull(true),
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Stage extends StatelessWidget {
  const _Stage({required this.queueHeight, required this.onResize, required this.onFullScreen});
  final double queueHeight;
  final ValueChanged<double> onResize;
  final VoidCallback onFullScreen;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: RadialGradient(
          center: const Alignment(0, -0.3),
          radius: 1.2,
          colors: [EzColors.brassDim.withValues(alpha: 0.25), context.ez.bg],
        ),
      ),
      child: LayoutBuilder(
        builder: (context, c) {
          final qh = queueHeight.clamp(120.0, c.maxHeight * 0.7);
          return Stack(
            children: [
              Positioned(left: 12, right: 12, top: 12, height: qh, child: const QueuePanel()),
              Positioned(
                left: 12,
                right: 12,
                top: 12 + qh,
                height: 10,
                child: GestureDetector(
                  onVerticalDragUpdate: (d) => onResize(qh + d.delta.dy),
                  child: MouseRegion(
                    cursor: SystemMouseCursors.resizeRow,
                    child: Center(child: Container(width: 40, height: 3, color: context.ez.border)),
                  ),
                ),
              ),
              OutputPanel(bounds: Size(c.maxWidth, c.maxHeight), onFullScreen: onFullScreen),
            ],
          );
        },
      ),
    );
  }
}
