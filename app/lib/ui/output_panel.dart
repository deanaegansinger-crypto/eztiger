import 'package:flutter/material.dart';

import '../theme.dart';
import 'common.dart';
import 'logo.dart';

/// What the singers see: the CDG lyrics screen or the karaoke video.
class KaraokeScreen extends StatelessWidget {
  const KaraokeScreen({super.key});

  @override
  Widget build(BuildContext context) =>
      ListenableBuilder(listenable: AppScope.of(context).engine, builder: (context, _) => _build(context));

  Widget _build(BuildContext context) {
    final s = AppScope.of(context);
    final e = s.engine;
    final video = AppScope.videoOf(context);
    Widget content;
    if (e.isVideo && video != null) {
      content = video(context);
    } else if (e.hasCdg) {
      content = ValueListenableBuilder(
        valueListenable: e.cdgFrame,
        builder: (context, img, _) => img == null
            ? const SizedBox()
            : Center(
                child: AspectRatio(
                  aspectRatio: 300 / 216,
                  child: RawImage(image: img, fit: BoxFit.fill, filterQuality: FilterQuality.none),
                ),
              ),
      );
    } else {
      final t = e.current;
      content = Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const EzLogo(size: 160),
            const SizedBox(height: 12),
            Text(
              'EZTIGER',
              style: TextStyle(fontSize: 34, fontWeight: FontWeight.w900, color: EzColors.brass, letterSpacing: 6),
            ),
            const SizedBox(height: 8),
            Text(
              t == null ? 'Up next…' : t.title,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 18, color: EzColors.cyan),
            ),
            if (t?.artist != null) Text(t!.artist!, style: TextStyle(fontSize: 13, color: EzColors.vfdSub)),
            if (e.singer != null) Text('🎤 ${e.singer}', style: const TextStyle(fontSize: 13, color: Colors.white70)),
          ],
        ),
      );
    }
    return ColoredBox(color: Colors.black, child: content);
  }
}

/// The floating, draggable and resizable "KARAOKE OUTPUT" panel.
class OutputPanel extends StatefulWidget {
  const OutputPanel({super.key, required this.bounds, this.onFullScreen});
  final Size bounds;
  final VoidCallback? onFullScreen;

  @override
  State<OutputPanel> createState() => _OutputPanelState();
}

class _OutputPanelState extends State<OutputPanel> {
  Offset? pos;
  double width = 420;

  @override
  Widget build(BuildContext context) {
    final h = width * 216 / 300 + 28;
    final b = widget.bounds;
    width = width.clamp(200, (b.width - 16).clamp(200, 2000));
    var p = pos ?? Offset(b.width - width - 16, b.height - h - 16);
    p = Offset(p.dx.clamp(0, (b.width - width).clamp(0, 9999)), p.dy.clamp(0, (b.height - h).clamp(0, 9999)));
    return Positioned(
      left: p.dx,
      top: p.dy,
      width: width,
      height: h,
      child: Material(
        elevation: 12,
        color: context.ez.panel,
        borderRadius: BorderRadius.circular(10),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            GestureDetector(
              onPanUpdate: (d) => setState(() => pos = p + d.delta),
              child: MouseRegion(
                cursor: SystemMouseCursors.move,
                child: Container(
                  height: 28,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  color: context.ez.raised,
                  child: Row(
                    children: [
                      HeadText('Karaoke output', color: EzColors.brass),
                      const Spacer(),
                      if (AppScope.secondScreenOf(context) case final second?)
                        Padding(
                          padding: const EdgeInsets.only(right: 10),
                          child: Tooltip(
                            message: second.isOpen
                                ? 'Close the second-screen output'
                                : 'Show the lyrics or video on a second screen (a TV or projector)',
                            child: InkWell(
                              onTap: second.toggle,
                              child: Row(
                                children: [
                                  Icon(Icons.connected_tv, size: 16, color: second.isOpen ? EzColors.cyan : null),
                                  const SizedBox(width: 4),
                                  Text(
                                    second.isOpen ? 'On 2nd screen' : '2nd screen',
                                    style: TextStyle(fontSize: 11, color: second.isOpen ? EzColors.cyan : null),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      Tooltip(
                        message: 'Full screen, or double-click the lyrics (Esc or double-click to exit)',
                        child: InkWell(onTap: widget.onFullScreen, child: const Icon(Icons.fullscreen, size: 18)),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Expanded(
              child: Stack(
                children: [
                  // Double-click (double-tap on the tablet) for full screen;
                  // double-click again there to come back.
                  Positioned.fill(
                    child: GestureDetector(
                      key: const Key('output-screen'),
                      onDoubleTap: widget.onFullScreen,
                      child: const KaraokeScreen(),
                    ),
                  ),
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: GestureDetector(
                      onPanUpdate: (d) => setState(() {
                        pos = p;
                        width += d.delta.dx;
                      }),
                      child: const MouseRegion(
                        cursor: SystemMouseCursors.resizeDownRight,
                        child: SizedBox(
                          width: 18,
                          height: 18,
                          child: Icon(Icons.south_east, size: 12, color: Colors.white54),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
