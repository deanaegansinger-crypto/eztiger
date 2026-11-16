import 'package:flutter/material.dart';

import '../app_state.dart';
import '../platform.dart';
import '../theme.dart';
import 'common.dart';

/// "0.20 s" for a delay in milliseconds.
String delayLabel(int ms) => '${(ms / 1000).toStringAsFixed(2)} s';

/// By the volume: the lyrics delay, for sound that is heard late (Bluetooth
/// to a mixer, say). A tap switches it on or off, keeping the time set;
/// press and hold (or right-click) to set the time.
class LyricsDelayButton extends StatelessWidget {
  const LyricsDelayButton({super.key, this.big = false});

  /// The Stage view's larger size.
  final bool big;

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    return ListenableBuilder(
      listenable: s,
      builder: (context, _) {
        final on = s.lyricsDelayOn;
        final size = (big ? 13.0 : 11.0) * (touchUi ? 1.2 : 1);
        return Tooltip(
          message: 'Lyrics delay: holds the lyrics and video back to match sound that is heard late '
              '(Bluetooth, a mixer). Tap to switch on or off; press and hold (or right-click) to set the time.',
          child: GestureDetector(
            onSecondaryTap: () => showLyricsDelay(context),
            child: InkWell(
              key: const Key('lyrics-delay'),
              onTap: () => s.setLyricsDelayOn(!on),
              onLongPress: () => showLyricsDelay(context),
              borderRadius: BorderRadius.circular(10),
              child: Container(
                padding: EdgeInsets.symmetric(horizontal: touchUi ? 12 : 8, vertical: touchUi ? 8 : 3),
                decoration: BoxDecoration(
                  color: on ? EzColors.cyan : context.ez.raised,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: on ? EzColors.cyan : context.ez.border),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.timer_outlined, size: size + 3, color: on ? EzColors.onBrass : context.ez.textDim),
                    const SizedBox(width: 4),
                    Text(
                      on ? '+${(s.lyricsDelayMs / 1000).toStringAsFixed(2)}s' : 'Delay',
                      key: const Key('lyrics-delay-label'),
                      style: TextStyle(
                        fontSize: size,
                        fontWeight: on ? FontWeight.w700 : FontWeight.normal,
                        color: on ? EzColors.onBrass : context.ez.textDim,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Sets the lyrics delay: on or off, and how long (0 to 1 second).
Future<void> showLyricsDelay(BuildContext context) {
  final s = AppScope.of(context);
  return showDialog<void>(
    context: context,
    builder: (context) => ListenableBuilder(
      listenable: s,
      builder: (context, _) {
        final ms = s.lyricsDelayMs;
        Widget step(String label, int by) => OutlinedButton(
          key: Key('lyrics-delay-step$by'),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size(0, 40),
            padding: const EdgeInsets.symmetric(horizontal: 8),
          ),
          // The time now, not when the dialog last redrew: quick taps all count.
          onPressed: () => s.setLyricsDelayMs(s.lyricsDelayMs + by),
          child: Text(label, style: const TextStyle(fontSize: 12)),
        );
        return AlertDialog(
          title: const Text('Lyrics delay'),
          content: SizedBox(
            width: 440,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'When the sound goes out over Bluetooth (to a mixer or speaker) it can reach the room late, '
                  'so the lyrics run ahead of the music. This holds the lyrics and video back to match.',
                ),
                const SizedBox(height: 10),
                Text(
                  'Play a song, then move the time until the words change colour with the singing.',
                  style: TextStyle(fontSize: 12, color: context.ez.textDim),
                ),
                const SizedBox(height: 14),
                SwitchListTile(
                  key: const Key('lyrics-delay-on'),
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Delay the lyrics and video'),
                  value: s.lyricsDelayOn,
                  onChanged: s.setLyricsDelayOn,
                ),
                Row(
                  children: [
                    step('−0.05', -50),
                    const SizedBox(width: 4),
                    step('−0.01', -10),
                    Expanded(
                      child: Text(
                        delayLabel(ms),
                        key: const Key('lyrics-delay-value'),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          color: s.lyricsDelayOn ? EzColors.brass : context.ez.textDim,
                        ),
                      ),
                    ),
                    step('+0.01', 10),
                    const SizedBox(width: 4),
                    step('+0.05', 50),
                  ],
                ),
                Slider(
                  key: const Key('lyrics-delay-slider'),
                  value: ms.toDouble(),
                  max: AppState.maxLyricsDelayMs.toDouble(),
                  divisions: AppState.maxLyricsDelayMs ~/ 10,
                  activeColor: EzColors.brass,
                  onChanged: (v) => s.setLyricsDelayMs(v.round()),
                ),
                Text(
                  'Most Bluetooth links need about 0.15 to 0.30 s. EZTiger remembers the time, '
                  'and the button by the volume switches it on and off.',
                  style: TextStyle(fontSize: 12, color: context.ez.textDim),
                ),
              ],
            ),
          ),
          actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Done'))],
        );
      },
    ),
  );
}
