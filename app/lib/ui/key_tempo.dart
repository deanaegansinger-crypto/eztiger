import 'package:flutter/material.dart';

import '../player.dart';
import '../theme.dart';

/// The loaded song's key and tempo on a player: "KEY D · 120 BPM". With the
/// key moved, it shows the key it plays in now and the song's own key:
/// "KEY E (D+2)". Worked out the first time a song loads (about a second),
/// then remembered.
class KeyTempo extends StatelessWidget {
  const KeyTempo({super.key, required this.engine, this.fontSize = 10});
  final KaraokeEngine engine;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    if (engine.current == null) return const SizedBox.shrink();
    final a = engine.analysis;
    final style = TextStyle(fontFamily: vfdFont, fontSize: fontSize, letterSpacing: 1, color: EzColors.vfdSub);
    if (a == null) {
      if (!engine.analysing) return const SizedBox.shrink();
      return Text(
        'KEY … BPM …',
        key: const Key('key-tempo'),
        style: style,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      );
    }
    final k = engine.keyShift;
    final own = a.key;
    final playing = engine.playingKey ?? own;
    final shift = k == 0 ? '' : ' ($own${k > 0 ? '+' : '−'}${k.abs()})';
    return Tooltip(
      message: k == 0
          ? 'This song is in $own, at ${a.bpmRounded} beats a minute'
          : 'Playing in $playing: the song is in $own, moved ${k.abs()} semitone${k.abs() == 1 ? '' : 's'} '
                '${k > 0 ? 'up' : 'down'}. ${a.bpmRounded} beats a minute',
      child: Text.rich(
        key: const Key('key-tempo'),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        softWrap: false,
        TextSpan(
          style: style,
          children: [
            const TextSpan(text: 'KEY '),
            TextSpan(
              text: playing,
              style: TextStyle(fontWeight: FontWeight.w800, color: k == 0 ? EzColors.vfdTitle : EzColors.red),
            ),
            if (shift.isNotEmpty) TextSpan(text: shift),
            const TextSpan(text: '  ·  '),
            TextSpan(
              text: '${a.bpmRounded}',
              style: TextStyle(fontWeight: FontWeight.w800, color: EzColors.vfdTitle),
            ),
            const TextSpan(text: ' BPM'),
          ],
        ),
      ),
    );
  }
}
