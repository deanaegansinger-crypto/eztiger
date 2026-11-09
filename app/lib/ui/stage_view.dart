import 'package:eztiger_core/eztiger_core.dart';
import 'package:flutter/material.dart';

import '../theme.dart';
import 'common.dart';
import '../app_state.dart';
import '../edition.dart';
import 'lock.dart';
import 'pro_sound.dart';
import 'output_panel.dart';
import 'songbook_dialog.dart';
import 'twin_decks.dart';

/// The view for performing, with the tablet on the mic stand: the lyrics or
/// video large on the left; on the right the song and time left in big
/// type, big Restart / Play / Next buttons, the volume, and the next songs.
class StageView extends StatelessWidget {
  const StageView({super.key, this.onFullScreen});

  /// Shows just the lyrics, full screen (double-tap them).
  final VoidCallback? onFullScreen;

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    return ListenableBuilder(
      listenable: s.engine,
      builder: (context, _) => Container(
        color: Colors.black,
        padding: const EdgeInsets.all(10),
        child: LayoutBuilder(
          builder: (context, c) {
            // A narrow window puts the controls under the lyrics instead.
            final side = c.maxWidth >= 900;
            // Pro, 2 decks: both decks across the top of the whole screen,
            // with the transport on them, so the controls beside the
            // lyrics are just the volume and what is next.
            final twin = isPro && s.twoDecks;
            final lyrics = _Lyrics(onFullScreen: onFullScreen);
            final controls = _Controls(compact: twin);
            final sides = [Expanded(flex: 11, child: lyrics), Expanded(flex: 9, child: controls)];
            final body = side
                ? Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      s.stageLyricsRight ? sides[1] : sides[0],
                      const SizedBox(width: 12),
                      s.stageLyricsRight ? sides[0] : sides[1],
                    ],
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(flex: 5, child: lyrics),
                      const SizedBox(height: 10),
                      Expanded(flex: 6, child: controls),
                    ],
                  );
            if (!twin) return body;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const TwinDecks(stage: true),
                const SizedBox(height: 10),
                Expanded(child: body),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _Lyrics extends StatelessWidget {
  const _Lyrics({this.onFullScreen});
  final VoidCallback? onFullScreen;

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(10),
    child: GestureDetector(key: const Key('stage-lyrics'), onDoubleTap: onFullScreen, child: const KaraokeScreen()),
  );
}

class _Controls extends StatelessWidget {
  const _Controls({this.compact = false});

  /// Pro, 2 decks: the song, time and transport are on the decks above.
  final bool compact;

  // This widget is const, so the stage view's own rebuild skips it: listen
  // to the player here, or the time and seek bar stand still while playing.
  @override
  Widget build(BuildContext context) =>
      ListenableBuilder(listenable: AppScope.of(context).engine, builder: (context, _) => _build(context));

  Widget _build(BuildContext context) {
    final s = AppScope.of(context);
    final e = s.engine;
    final t = e.current;
    final total = e.duration;
    final left = total - e.position;
    final sub = [if (t?.artist != null) t!.artist!, if (e.singer != null) '🎤 ${e.singer}'].join('  ·  ');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text(
              t == null ? 'READY' : (e.playing ? 'NOW PLAYING' : 'CUED · PRESS PLAY'),
              style: TextStyle(fontFamily: vfdFont, fontSize: 14, color: EzColors.vfdSub, letterSpacing: 2),
            ),
            if (isPro) ...[const SizedBox(width: 10), KeyWarning(engine: e, fontSize: 16)],
            const Spacer(),
            // The songbook's QR code, for the audience to scan.
            if (s.songbookUrl.isNotEmpty) ...[
              IconButton(
                key: const Key('stage-qr'),
                tooltip: 'Show the songbook QR code',
                iconSize: 30,
                style: IconButton.styleFrom(
                  minimumSize: const Size(52, 52),
                  side: BorderSide(color: EzColors.cyan),
                  foregroundColor: EzColors.cyan,
                ),
                onPressed: () => showSongbookQr(context),
                icon: const Icon(Icons.qr_code_2),
              ),
              const SizedBox(width: 10),
            ],
            if (isPro && s.lockEnabled) ...[const LockButton(big: true), const SizedBox(width: 10)],
            // Swap the lyrics and the buttons left and right.
            IconButton(
              key: const Key('stage-swap'),
              tooltip: s.stageLyricsRight ? 'Lyrics on the left' : 'Lyrics on the right',
              iconSize: 30,
              style: IconButton.styleFrom(
                minimumSize: const Size(52, 52),
                side: BorderSide(color: EzColors.cyan),
                foregroundColor: EzColors.cyan,
              ),
              onPressed: () => s.setStageLyricsRight(!s.stageLyricsRight),
              icon: const Icon(Icons.swap_horiz),
            ),
            const SizedBox(width: 10),
            _BigButton(
              key: const Key('stage-exit'),
              icon: Icons.library_music,
              label: 'Library',
              onTap: () => s.setStageView(false),
            ),
          ],
        ),
        if (!compact) ...[
          const SizedBox(height: 6),
          Text(
            e.error ?? t?.title ?? 'Pick a song to begin',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 30,
              height: 1.1,
              fontWeight: FontWeight.w800,
              color: e.error != null ? EzColors.red : EzColors.brass,
            ),
          ),
          if (sub.isNotEmpty)
            Text(
              sub,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 20, color: EzColors.cyan),
            ),
          const SizedBox(height: 8),
          if (t != null && total > Duration.zero) ...[
            Row(
              children: [
                Text(fmt(e.position), style: const TextStyle(fontSize: 20, color: Colors.white70)),
                const Spacer(),
                Text(
                  '-${fmt(left.isNegative ? Duration.zero : left)}',
                  key: const Key('stage-time-left'),
                  style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w700, color: Colors.white),
                ),
              ],
            ),
            _StageSeek(position: e.position, total: total, onSeek: e.seek),
          ],
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _RoundButton(key: const Key('stage-restart'), icon: Icons.skip_previous, size: 72, onTap: s.previous),
              _RoundButton(
                key: const Key('stage-play'),
                icon: e.playing ? Icons.pause : Icons.play_arrow,
                size: 104,
                primary: true,
                onTap: s.playPause,
              ),
              _RoundButton(key: const Key('stage-next'), icon: Icons.skip_next, size: 72, onTap: s.next),
            ],
          ),
        ],
        const SizedBox(height: 8),
        Row(
          children: [
            _StageMode(mode: s.mode, onChanged: s.setMode),
            const SizedBox(width: 6),
            IconButton(
              iconSize: 34,
              onPressed: e.toggleMute,
              icon: Icon(e.muted ? Icons.volume_off : Icons.volume_up, color: Colors.white70),
            ),
            Expanded(
              child: SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: 8,
                  thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 14),
                  overlayShape: const RoundSliderOverlayShape(overlayRadius: 26),
                ),
                child: Slider(
                  value: e.muted ? 0 : e.volume,
                  max: 100,
                  activeColor: EzColors.brass,
                  onChanged: e.setVolume,
                ),
              ),
            ),
            SizedBox(
              width: 60,
              child: Text(
                '${(e.muted ? 0 : e.volume).round()}%',
                textAlign: TextAlign.right,
                style: const TextStyle(fontSize: 18, color: Colors.white70),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        const _UpNext(),
      ],
    );
  }
}

/// The songs still to sing, in big type. Double-tap one to play it now.
class _UpNext extends StatelessWidget {
  const _UpNext();

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final waiting = [
      for (final q in s.queue)
        if (!q.played && q.id != s.nowPlayingQueueId) q,
    ];
    // The song titles follow the Text size setting in the menu.
    final scale = s.textScale;
    return Expanded(
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
        decoration: BoxDecoration(
          color: const Color(0xFF15181C),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFF2A2F36)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              waiting.isEmpty ? 'UP NEXT · NOTHING QUEUED' : 'UP NEXT · ${waiting.length}',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: EzColors.brass, letterSpacing: 2),
            ),
            const SizedBox(height: 4),
            Expanded(
              child: ListView(
                children: [
                  for (final (i, q) in waiting.indexed)
                    Row(
                      children: [
                        // The buttons sit outside the double-tap area, so they
                        // answer straight away.
                        Expanded(
                          child: InkWell(
                            key: ValueKey('stage-next-${q.id}'),
                            onDoubleTap: () => s.playEntry(q),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 6),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  SizedBox(
                                    width: 34 * scale,
                                    child: Text(
                                      '${i + 1}',
                                      style: TextStyle(
                                        fontSize: 20 * scale,
                                        color: i == 0 ? EzColors.cyan : Colors.white38,
                                      ),
                                    ),
                                  ),
                                  Expanded(
                                    child: _QueuedSong(entry: q, first: i == 0, scale: scale),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        _QueueButton(
                          key: ValueKey('stage-up-${q.id}'),
                          icon: Icons.arrow_upward,
                          tip: 'Move up',
                          onTap: i == 0 ? null : () => s.nudgeInQueue(q, up: true),
                        ),
                        _QueueButton(
                          key: ValueKey('stage-down-${q.id}'),
                          icon: Icons.arrow_downward,
                          tip: 'Move down',
                          onTap: i == waiting.length - 1 ? null : () => s.nudgeInQueue(q, up: false),
                        ),
                        _QueueButton(
                          key: ValueKey('stage-remove-${q.id}'),
                          icon: Icons.close,
                          tip: 'Take out of $theQueue',
                          onTap: () => s.removeFromQueue(q),
                        ),
                      ],
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

class _QueuedSong extends StatelessWidget {
  const _QueuedSong({required this.entry, required this.first, required this.scale});
  final QueueEntry entry;
  final bool first;
  final double scale;

  @override
  Widget build(BuildContext context) {
    final t = entry.track;
    final sub = [if (t.artist != null) t.artist!, if (entry.singer != null) '🎤 ${entry.singer}'].join('  ·  ');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          t.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 22 * scale,
            fontWeight: first ? FontWeight.w700 : FontWeight.w500,
            color: first ? Colors.white : Colors.white70,
          ),
        ),
        if (sub.isNotEmpty)
          Text(
            sub,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 15 * scale, color: Colors.white54),
          ),
      ],
    );
  }
}

class _StageSeek extends StatefulWidget {
  const _StageSeek({required this.position, required this.total, required this.onSeek});
  final Duration position, total;
  final Future<void> Function(Duration) onSeek;
  @override
  State<_StageSeek> createState() => _StageSeekState();
}

class _StageSeekState extends State<_StageSeek> {
  double? _dragMs;
  @override
  Widget build(BuildContext context) {
    final total = widget.total.inMilliseconds.toDouble();
    final at = (_dragMs ?? widget.position.inMilliseconds.toDouble()).clamp(0.0, total);
    return SliderTheme(
      data: SliderTheme.of(context).copyWith(
        trackHeight: 8,
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 12),
        overlayShape: const RoundSliderOverlayShape(overlayRadius: 24),
        activeTrackColor: EzColors.cyan,
        thumbColor: EzColors.cyan,
        inactiveTrackColor: const Color(0xFF2A2F36),
      ),
      child: Slider(
        value: at,
        max: total,
        onChangeStart: (v) => setState(() => _dragMs = v),
        onChanged: (v) => setState(() => _dragMs = v),
        onChangeEnd: (v) async {
          await widget.onSeek(Duration(milliseconds: v.round()));
          if (mounted) setState(() => _dragMs = null);
        },
      ),
    );
  }
}

class _RoundButton extends StatelessWidget {
  const _RoundButton({super.key, required this.icon, required this.size, required this.onTap, this.primary = false});
  final IconData icon;
  final double size;
  final VoidCallback onTap;
  final bool primary;

  @override
  Widget build(BuildContext context) => Material(
    color: primary ? EzColors.brass : const Color(0xFF2A2F36),
    shape: const CircleBorder(),
    child: InkWell(
      customBorder: const CircleBorder(),
      onTap: onTap,
      child: SizedBox(
        width: size,
        height: size,
        child: Icon(icon, size: size * 0.6, color: primary ? EzColors.onBrass : Colors.white),
      ),
    ),
  );
}

class _BigButton extends StatelessWidget {
  const _BigButton({super.key, required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => OutlinedButton.icon(
    style: OutlinedButton.styleFrom(
      minimumSize: const Size(0, 52),
      padding: const EdgeInsets.symmetric(horizontal: 18),
      foregroundColor: EzColors.cyan,
      side: BorderSide(color: EzColors.cyan),
    ),
    onPressed: onTap,
    icon: Icon(icon, size: 24),
    label: Text(label, style: const TextStyle(fontSize: 18)),
  );
}

/// Up, down and remove buttons on a song waiting in the stage view's queue.
class _QueueButton extends StatelessWidget {
  const _QueueButton({super.key, required this.icon, required this.tip, required this.onTap});
  final IconData icon;
  final String tip;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: tip,
    iconSize: 28,
    constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
    color: Colors.white70,
    disabledColor: Colors.white12,
    onPressed: onTap,
    icon: Icon(icon),
  );
}

/// Single / Autoplay, big enough to hit on a stand.
class _StageMode extends StatelessWidget {
  const _StageMode({required this.mode, required this.onChanged});
  final PlayMode mode;
  final ValueChanged<PlayMode> onChanged;

  @override
  Widget build(BuildContext context) => Container(
    key: const Key('stage-mode'),
    padding: const EdgeInsets.all(3),
    decoration: BoxDecoration(
      color: const Color(0xFF15181C),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: const Color(0xFF2A2F36)),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final (m, label) in [(PlayMode.single, 'Single'), (PlayMode.autoplay, 'Autoplay')])
          InkWell(
            key: Key('stage-mode-${m.name}'),
            borderRadius: BorderRadius.circular(9),
            onTap: () => onChanged(m),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: m == mode ? EzColors.cyan.withValues(alpha: 0.22) : null,
                borderRadius: BorderRadius.circular(9),
              ),
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: m == mode ? EzColors.cyan : Colors.white60,
                ),
              ),
            ),
          ),
      ],
    ),
  );
}
