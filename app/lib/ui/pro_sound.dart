import 'dart:async';

import 'package:flutter/material.dart';

import '../platform.dart';
import '../player.dart';
import '../theme.dart';
import 'common.dart';

/// EZTiger Pro, under the volume bar: the key (♭ / ♯ up to 3 semitones,
/// remembered for each song), Level (evens out loudness between songs) and
/// Vocal cut.
class ProSoundRow extends StatelessWidget {
  const ProSoundRow({super.key});

  @override
  Widget build(BuildContext context) =>
      ListenableBuilder(listenable: AppScope.of(context).engine, builder: (context, _) => _build(context));

  Widget _build(BuildContext context) {
    final s = AppScope.of(context);
    final e = s.engine;
    final loaded = e.current != null;
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        children: [
          Text('KEY', style: TextStyle(fontSize: 11, color: context.ez.textDim, letterSpacing: 1)),
          const SizedBox(width: 6),
          _KeyButton(
            key: const Key('key-down'),
            icon: Icons.remove,
            tooltip: 'Key down a semitone',
            onTap: loaded && e.keyShift > KaraokeEngine.minKey ? s.keyDown : null,
          ),
          InkWell(
            key: const Key('key-reset'),
            onTap: loaded && e.keyShift != 0 ? s.keyReset : null,
            child: Tooltip(
              message: 'Back to the song\'s own key',
              child: SizedBox(
                width: 44,
                child: Text(
                  keyLabel(e.keyShift),
                  key: const Key('key-value'),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: vfdFont,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: e.keyShift == 0 ? context.ez.textDim : EzColors.red,
                  ),
                ),
              ),
            ),
          ),
          _KeyButton(
            key: const Key('key-up'),
            icon: Icons.add,
            tooltip: 'Key up a semitone',
            onTap: loaded && e.keyShift < KaraokeEngine.maxKey ? s.keyUp : null,
          ),
          const Spacer(),
          if (audioFilters) ...[
            Tooltip(
              message: 'Even out the loudness, so quiet and loud tracks play at about the same level',
              child: EzSwitch(
                key: const Key('level-loudness'),
                label: 'Level',
                value: e.levelLoudness,
                onChanged: () => s.setLevelLoudness(!e.levelLoudness),
              ),
            ),
            const SizedBox(width: 12),
            Tooltip(
              message: 'Cut the lead vocal (works best on stereo tracks with the singer in the middle)',
              child: EzSwitch(
                key: const Key('vocal-cut'),
                label: 'Vocal cut',
                value: e.vocalCut,
                onChanged: () => s.setVocalCut(!e.vocalCut),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// "0", "+2", "−3".
String keyLabel(int k) => k == 0 ? '0' : (k > 0 ? '+$k' : '−${-k}');

class _KeyButton extends StatelessWidget {
  const _KeyButton({super.key, required this.icon, required this.tooltip, required this.onTap});
  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: tooltip,
    child: Material(
      color: context.ez.raised,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          width: 26,
          height: 26,
          child: Icon(icon, size: 16, color: onTap == null ? context.ez.textDim : context.ez.text),
        ),
      ),
    ),
  );
}

/// "KEY +2": shown on the player while a song is in a changed key. It
/// flashes for the first [flashFor] after the song loads, so a changed key
/// is never a surprise, then stays lit.
class KeyWarning extends StatefulWidget {
  const KeyWarning({super.key, required this.engine, this.fontSize = 10});
  final KaraokeEngine engine;
  final double fontSize;

  static const flashFor = Duration(seconds: 12);

  @override
  State<KeyWarning> createState() => _KeyWarningState();
}

class _KeyWarningState extends State<KeyWarning> {
  Timer? _timer;
  bool _dim = false;
  DateTime? _flashingFor;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _sync() {
    final since = widget.engine.keyWarningSince;
    if (since == _flashingFor) return;
    _flashingFor = since;
    _timer?.cancel();
    _dim = false;
    if (since == null) return;
    _timer = Timer.periodic(const Duration(milliseconds: 450), (t) {
      if (!mounted) return;
      final over = DateTime.now().difference(since) >= KeyWarning.flashFor;
      setState(() => _dim = over ? false : !_dim);
      if (over) t.cancel();
    });
  }

  @override
  Widget build(BuildContext context) {
    _sync();
    final k = widget.engine.keyShift;
    if (k == 0 || widget.engine.current == null) return const SizedBox.shrink();
    return Container(
      key: const Key('key-warning'),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: _dim ? Colors.transparent : EzColors.red,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: EzColors.red),
      ),
      child: Text(
        'KEY ${keyLabel(k)}',
        style: TextStyle(
          fontFamily: vfdFont,
          fontSize: widget.fontSize,
          fontWeight: FontWeight.w800,
          letterSpacing: 1,
          color: _dim ? EzColors.red : Colors.white,
        ),
      ),
    );
  }
}
