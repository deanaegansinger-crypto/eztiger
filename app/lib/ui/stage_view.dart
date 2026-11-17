import 'package:eztiger_core/eztiger_core.dart';
import 'package:flutter/material.dart';

import '../theme.dart';
import 'common.dart';
import '../app_state.dart';
import '../edition.dart';
import '../platform.dart';
import '../player.dart';
import 'lock.dart';
import 'lyrics_delay.dart';
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
            // Upright (the singer app's portrait Stage view): the decks, the
            // volume and Up next in the top half, the lyrics filling the
            // bottom half.
            if (c.maxHeight > c.maxWidth) {
              return Column(
                key: const Key('stage-portrait'),
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (twin) ...[const TwinDecks(stage: true, scale: 1.15), const SizedBox(height: 6)],
                        Expanded(child: _Controls(compact: twin, portrait: true)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Expanded(child: lyrics),
                ],
              );
            }
            // A short screen (a phone on its side) gets the slimmer controls.
            final controls = _Controls(compact: twin, small: c.maxHeight < 640);
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
  const _Controls({this.compact = false, this.portrait = false, bool small = false}) : small = small || portrait;

  /// A short screen (a phone on its side) or the portrait view: the title on
  /// one line, the transport and the key on one line.
  final bool small;

  /// Pro, 2 decks: the song, time and transport are on the decks above.
  final bool compact;

  /// The portrait Stage view: smaller, to leave room for Up next.
  final bool portrait;

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
            Flexible(
              child: Text(
                t == null ? 'READY' : (e.playing ? 'NOW PLAYING' : 'CUED · PRESS PLAY'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontFamily: vfdFont, fontSize: 14, color: EzColors.vfdSub, letterSpacing: 2),
              ),
            ),
            if (isPro) ...[const SizedBox(width: 10), KeyWarning(engine: e, fontSize: 16)],
            const Spacer(),
            // The songbook's QR code, for the audience to scan (the host's
            // tool: not in the singer app).
            if (!singerApp && s.songbookUrl.isNotEmpty) ...[
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
            // The singer app: turn the tablet upright, or back.
            if (singerApp) ...[
              IconButton(
                key: const Key('stage-rotate'),
                tooltip: s.stagePortrait ? 'Landscape' : 'Portrait',
                iconSize: 30,
                style: IconButton.styleFrom(
                  minimumSize: const Size(52, 52),
                  side: BorderSide(color: EzColors.cyan),
                  foregroundColor: EzColors.cyan,
                ),
                onPressed: () => s.setStagePortrait(!s.stagePortrait),
                icon: const Icon(Icons.screen_rotation),
              ),
              const SizedBox(width: 10),
            ],
            // Swap the lyrics and the buttons left and right.
            if (!portrait) ...[
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
            ],
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
            maxLines: small ? 1 : 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: small ? 26 : 30,
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
          if (small)
            // Upright, or a short screen: the transport and the key share one line, shrinking
            // to fit a phone's width, so Up next keeps its room.
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ..._transport(s, e, small: true),
                  if (isPro) ...[const SizedBox(width: 28), _StageKey(engine: e)],
                ],
              ),
            )
          else ...[
            Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: _transport(s, e)),
            // The key, big enough to hit on the mic stand (with 2 decks it
            // is on each deck instead).
            if (isPro) ...[const SizedBox(height: 8), _StageKey(engine: e)],
          ],
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
              flex: 4,
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
            const SizedBox(width: 8),
            const Flexible(
              child: FittedBox(fit: BoxFit.scaleDown, child: LyricsDelayButton(big: true)),
            ),
          ],
        ),
        const SizedBox(height: 6),
        const _UpNext(),
      ],
    );
  }
}

/// The warning when Tonight's playlist is running out: the text, and true
/// for the last song (red rather than orange). Null while there are more
/// than [AppState.lowSongsWarning] songs to come, or nothing loaded at all.
(String, bool)? lowSongsMessage(AppState s) {
  final waiting = s.queue.where((q) => !q.played && q.id != s.nowPlayingQueueId).length;
  final playing = s.nowPlayingQueueId != null && s.queue.any((q) => q.id == s.nowPlayingQueueId && !q.played);
  if (waiting > AppState.lowSongsWarning || (waiting == 0 && !playing)) return null;
  return switch (waiting) {
    0 => ('Last song! Nothing after this one: load more', true),
    1 => ('Only 1 song left after this: load more', true),
    _ => ('Only $waiting songs left: load more soon', false),
  };
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
            // Running out: Tonight's playlist down to its last 2 songs.
            if (lowSongsMessage(s) case (final text, final last)?)
              Container(
                key: const Key('stage-low-songs'),
                margin: const EdgeInsets.only(top: 6),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: (last ? EzColors.red : const Color(0xFFFF9800)).withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: last ? EzColors.red : const Color(0xFFFF9800), width: 2),
                ),
                child: Row(
                  children: [
                    Icon(Icons.warning_amber_rounded, size: 26, color: last ? EzColors.red : const Color(0xFFFF9800)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        text,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Colors.white),
                      ),
                    ),
                  ],
                ),
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

/// Restart, Play / Pause and Next: smaller in the portrait Stage view.
List<Widget> _transport(AppState s, KaraokeEngine e, {bool small = false}) => [
  _RoundButton(key: const Key('stage-restart'), icon: Icons.skip_previous, size: small ? 60 : 72, onTap: s.previous),
  if (small) const SizedBox(width: 14),
  _RoundButton(
    key: const Key('stage-play'),
    icon: e.playing ? Icons.pause : Icons.play_arrow,
    size: small ? 84 : 104,
    primary: true,
    onTap: s.playPause,
  ),
  if (small) const SizedBox(width: 14),
  _RoundButton(key: const Key('stage-next'), icon: Icons.skip_next, size: small ? 60 : 72, onTap: s.next),
];

/// KEY − +2 + in the Stage view: the song on the player down or up a
/// semitone (remembered for the song); tap the number to put it back.
class _StageKey extends StatelessWidget {
  const _StageKey({required this.engine});
  final KaraokeEngine engine;

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final k = engine.keyShift;
    final loaded = engine.current != null;
    Widget step(String key, IconData icon, VoidCallback? onTap) => IconButton(
      key: Key(key),
      iconSize: 30,
      style: IconButton.styleFrom(
        minimumSize: const Size(56, 52),
        side: BorderSide(color: onTap == null ? const Color(0xFF2A2F36) : EzColors.cyan),
        foregroundColor: EzColors.cyan,
        disabledForegroundColor: Colors.white24,
      ),
      onPressed: onTap,
      icon: Icon(icon),
    );
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('KEY', style: TextStyle(fontSize: 16, color: EzColors.vfdSub, letterSpacing: 2)),
        const SizedBox(width: 12),
        step('stage-key-down', Icons.remove, loaded && k > KaraokeEngine.minKey ? s.keyDown : null),
        InkWell(
          onTap: loaded && k != 0 ? s.keyReset : null,
          child: SizedBox(
            width: 72,
            child: Text(
              keyLabel(k),
              key: const Key('stage-key'),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: vfdFont,
                fontSize: 26,
                fontWeight: FontWeight.w800,
                color: k == 0 ? Colors.white70 : EzColors.red,
              ),
            ),
          ),
        ),
        step('stage-key-up', Icons.add, loaded && k < KaraokeEngine.maxKey ? s.keyUp : null),
      ],
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
