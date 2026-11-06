import 'package:flutter/material.dart';

import '../app_state.dart';
import '../player.dart';
import '../theme.dart';
import 'common.dart';
import 'pro_sound.dart';

/// EZTiger Pro, 2 decks: deck A and deck B side by side across the top.
/// The live deck shows ON AIR and the transport; the other shows the song
/// waiting to come in. Drop a song on either: on the live deck it plays
/// now, on the other it becomes the next song.
class TwinDecks extends StatelessWidget {
  const TwinDecks({super.key});

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    return ListenableBuilder(
      listenable: Listenable.merge(s.decks),
      builder: (context, _) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final i in [0, 1]) ...[if (i == 1) const SizedBox(width: 8), Expanded(child: _DeckCard(index: i))],
        ],
      ),
    );
  }
}

class _DeckCard extends StatelessWidget {
  const _DeckCard({required this.index});
  final int index;

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final e = s.decks[index];
    final live = s.liveDeck == index;
    final t = e.current;
    final name = index == 0 ? 'A' : 'B';
    final waiting = !live && s.standbyQueueId != null;
    final status = live
        ? (t == null ? 'READY' : (e.playing ? 'ON AIR' : 'CUED'))
        : (e.playing ? 'FADING OUT' : (waiting ? 'NEXT' : 'EMPTY'));
    final left = e.duration - e.position;
    return DragTarget<SongDrag>(
      key: Key('deck-$name'),
      onAcceptWithDetails: (d) => live ? s.dropOnPlayer(d.data) : s.loadNext(d.data.tracks, queueIds: d.data.queueIds),
      builder: (context, cand, _) => Container(
        padding: const EdgeInsets.fromLTRB(8, 5, 6, 4),
        decoration: BoxDecoration(
          color: EzColors.vfdBg,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: cand.isNotEmpty ? EzColors.cyan : (live ? EzColors.brass : const Color(0xFF0E2A2A)),
            width: cand.isNotEmpty || live ? 2 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Text(
                  'DECK $name',
                  style: TextStyle(fontFamily: vfdFont, fontSize: 9, fontWeight: FontWeight.w800, color: EzColors.cyan),
                ),
                const SizedBox(width: 6),
                Text(
                  cand.isNotEmpty ? (live ? 'DROP TO PLAY NOW' : 'DROP FOR NEXT') : status,
                  style: TextStyle(
                    fontFamily: vfdFont,
                    fontSize: 9,
                    letterSpacing: 1.5,
                    color: live && e.playing ? EzColors.red : EzColors.vfdSub,
                  ),
                ),
                const SizedBox(width: 6),
                KeyWarning(engine: e, fontSize: 9),
                const Spacer(),
                if (t != null && e.duration > Duration.zero)
                  Text(
                    '-${fmt(left.isNegative ? Duration.zero : left)}',
                    style: TextStyle(fontFamily: vfdFont, fontSize: 11, color: EzColors.vfdSub),
                  ),
              ],
            ),
            Text(
              e.error ?? t?.title ?? (live ? 'Pick a song to begin' : 'The next song waits here'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: vfdFont,
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: e.error != null ? EzColors.red : (t == null ? EzColors.vfdSub : EzColors.brass),
              ),
            ),
            Row(
              children: [
                Expanded(
                  child: Text(
                    [if (t?.artist != null) t!.artist!, if (e.singer != null) '🎤 ${e.singer}'].join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontFamily: vfdFont, fontSize: 10, color: EzColors.cyan),
                  ),
                ),
                if (live) ...[
                  _Mini(icon: Icons.skip_previous, tooltip: 'Back to the start', onTap: s.previous),
                  _Mini(
                    key: Key('deck-$name-play'),
                    icon: e.playing ? Icons.pause : Icons.play_arrow,
                    tooltip: e.playing ? 'Pause' : 'Play',
                    primary: true,
                    onTap: s.playPause,
                  ),
                  _Mini(icon: Icons.skip_next, tooltip: 'Next singer', onTap: s.next),
                ] else if (waiting)
                  _Mini(
                    key: Key('deck-$name-mix'),
                    icon: Icons.swap_horiz,
                    tooltip: 'Mix into this song now',
                    primary: true,
                    onTap: s.mixNow,
                  ),
              ],
            ),
            const SizedBox(height: 3),
            _DeckProgress(engine: e),
          ],
        ),
      ),
    );
  }
}

/// A thin progress bar; click or drag it on the live deck to skip.
class _DeckProgress extends StatelessWidget {
  const _DeckProgress({required this.engine});
  final KaraokeEngine engine;

  @override
  Widget build(BuildContext context) {
    final total = engine.duration.inMilliseconds;
    final at = total <= 0 ? 0.0 : (engine.position.inMilliseconds / total).clamp(0.0, 1.0);
    return LayoutBuilder(
      builder: (context, c) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: total <= 0
            ? null
            : (d) => engine.seek(Duration(milliseconds: (total * d.localPosition.dx / c.maxWidth).round())),
        child: SizedBox(
          height: 8,
          child: Center(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: LinearProgressIndicator(
                value: at,
                minHeight: 4,
                color: EzColors.cyan,
                backgroundColor: const Color(0xFF0E2A2A),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Mini extends StatelessWidget {
  const _Mini({super.key, required this.icon, required this.tooltip, required this.onTap, this.primary = false});
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final bool primary;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(left: 3),
    child: Tooltip(
      message: tooltip,
      child: Material(
        color: primary ? EzColors.brass : context.ez.raised,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox(
            width: primary ? 30 : 26,
            height: primary ? 30 : 26,
            child: Icon(icon, size: primary ? 20 : 16, color: primary ? EzColors.onBrass : context.ez.text),
          ),
        ),
      ),
    ),
  );
}

/// EZTiger Pro: the crossfade time (0, a cut, to 6 seconds), how the two
/// songs meet, the fade curve, and Mix now.
class CrossfadeRow extends StatelessWidget {
  const CrossfadeRow({super.key});

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final secs = s.fadeOutTime.inMilliseconds / 1000;
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Row(
        children: [
          Tooltip(
            message: 'Crossfade into the next song at the end of each one',
            child: EzSwitch(
              key: const Key('xfade-on'),
              label: 'X-fade',
              value: s.crossfade,
              onChanged: s.toggleCrossfade,
            ),
          ),
          Expanded(
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 3,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
              ),
              child: Slider(
                key: const Key('xfade-time'),
                value: secs.clamp(0, AppState.maxFade.inSeconds.toDouble()),
                max: AppState.maxFade.inSeconds.toDouble(),
                divisions: AppState.maxFade.inSeconds * 2,
                activeColor: EzColors.cyan,
                label: secs == 0 ? 'Cut' : '${secs.toStringAsFixed(1)} s',
                onChanged: (v) => s.setFadeOut(Duration(milliseconds: (v * 1000).round())),
              ),
            ),
          ),
          SizedBox(
            width: 34,
            child: Text(
              secs == 0 ? 'Cut' : '${secs.toStringAsFixed(1)}s',
              key: const Key('xfade-label'),
              style: TextStyle(fontSize: 11, color: context.ez.textDim),
            ),
          ),
          Flexible(
            flex: 0,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (s.twoDecks) ...[
                    Tooltip(
                      message: 'Overlap: the next song comes in under the last one.\nIn turn: one fades out, then the next fades in.',
                      child: Segmented<bool>(
                        key: const Key('xfade-style'),
                        options: const {true: 'Overlap', false: 'In turn'},
                        value: s.fadeOverlap,
                        onChanged: s.setFadeOverlap,
                      ),
                    ),
                    const SizedBox(width: 6),
                  ],
                  Segmented<bool>(
                    key: const Key('xfade-curve'),
                    options: const {true: 'Smooth', false: 'Linear'},
                    value: s.smoothFades,
                    onChanged: s.setSmoothFades,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
