import 'package:eztiger_core/eztiger_core.dart';
import 'package:flutter/material.dart';

import '../theme.dart';
import 'common.dart';
import 'dialogs.dart';
import 'rack.dart';

/// "QUEUE · N songs" at the top of the stage.
class QueuePanel extends StatelessWidget {
  const QueuePanel({super.key});

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    return DragTarget<SongDrag>(
      onAcceptWithDetails: (d) => s.dropIntoQueue(d.data, s.queue.length),
      builder: (context, cand, _) => Container(
        decoration: BoxDecoration(
          color: context.ez.panel.withValues(alpha: 0.94),
          border: Border.all(
            color: cand.isNotEmpty ? EzColors.cyan : context.ez.border,
            width: cand.isNotEmpty ? 2 : 1,
          ),
          borderRadius: BorderRadius.circular(10),
        ),
        padding: const EdgeInsets.fromLTRB(10, 8, 10, 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                HeadText(
                  'Queue · ${s.queue.length - s.playedCount} to sing'
                  '${s.playedCount > 0 ? ' · ${s.playedCount} played' : ''}',
                  color: EzColors.brass,
                ),
                const Spacer(),
                if (s.queue.isNotEmpty) const _SaveQueueButton(),
                if (s.playedCount > 0)
                  TextButton(
                    key: const Key('clear-played'),
                    style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                    onPressed: s.clearPlayed,
                    child: const Text('Clear played', style: TextStyle(fontSize: 11)),
                  ),
                if (s.queue.isNotEmpty)
                  TextButton(
                    style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                    onPressed: s.clearQueue,
                    child: const Text('Clear', style: TextStyle(fontSize: 11)),
                  ),
              ],
            ),
            Container(
              padding: const EdgeInsets.symmetric(vertical: 3),
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: context.ez.border)),
              ),
              child: const Row(
                children: [
                  SizedBox(width: 28, child: HeadText('#')),
                  Expanded(flex: 5, child: HeadText('Title')),
                  Expanded(flex: 5, child: HeadText('Artist — Singer')),
                  SizedBox(width: 44, child: HeadText('Type')),
                  SizedBox(width: 96, child: HeadText('Played')),
                  Expanded(flex: 2, child: HeadText('Location')),
                  SizedBox(width: 24),
                ],
              ),
            ),
            Expanded(
              child: s.queue.isEmpty
                  ? Center(
                      child: Text(
                        'Drag songs here, or press Enter on them in the list.',
                        style: TextStyle(fontSize: 12, color: context.ez.textDim),
                      ),
                    )
                  : ListView.builder(
                      itemCount: s.queue.length,
                      itemExtent: 28,
                      itemBuilder: (context, i) => _QueueRow(key: ValueKey(s.queue[i].id), entry: s.queue[i], index: i),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// "★ Save as playlist": the songs in the queue become a new playlist, or are
/// added to one already made. It can also be dragged onto a playlist.
class _SaveQueueButton extends StatelessWidget {
  const _SaveQueueButton();

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final tracks = [for (final e in s.queue) e.track];
    final n = tracks.length == 1 ? '1 song' : '${tracks.length} songs';
    final button = PopupMenuButton<String>(
      key: const Key('save-queue'),
      tooltip: 'Save the queue as a playlist',
      itemBuilder: (_) => [
        PopupMenuItem(value: 'new', child: Text('★ New playlist from the queue ($n)…')),
        for (final p in s.playlists) PopupMenuItem(value: 'pl:${p.id}', child: Text('★ Add the queue to ${p.name}')),
      ],
      onSelected: (c) async {
        if (c == 'new') {
          final name = await askText(context, title: 'New playlist from the queue ($n)', label: 'Name');
          if (name != null) await s.createPlaylist(name, tracks: tracks);
        } else if (c.startsWith('pl:')) {
          await s.addToPlaylist(int.parse(c.substring(3)), tracks);
        }
      },
      child: const Padding(
        padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Text('★ Save as playlist', style: TextStyle(fontSize: 11, color: EzColors.brass)),
      ),
    );
    // Dragging the button carries the whole queue, to drop on a playlist.
    // (Marked as queue songs, so letting go over the queue changes nothing.)
    final drag = SongDrag(tracks, queueIds: [for (final e in s.queue) e.id]);
    return Draggable<SongDrag>(
      data: drag,
      dragAnchorStrategy: pointerDragAnchorStrategy,
      feedback: dragChip(drag),
      child: button,
    );
  }
}

class _QueueRow extends StatelessWidget {
  const _QueueRow({super.key, required this.entry, required this.index});
  final QueueEntry entry;
  final int index;

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final t = entry.track;
    final playing = s.nowPlayingQueueId == entry.id;
    final played = entry.played && !playing;
    final dim = context.ez.textDim;
    final drag = SongDrag([t], queueIds: [entry.id]);
    return InsertTarget(
      index: index,
      onDrop: s.dropIntoQueue,
      child: SongDraggable(
        data: drag,
        onMenu: (at) async {
          final c = await showMenuAt<String>(context, at, [
            const PopupMenuItem(value: 'play', child: Text('▶ Play now')),
            const PopupMenuItem(value: 'singer', child: Text('🎤 Set singer…')),
            const PopupMenuItem(value: 'edit', child: Text('✏️ Edit tags…')),
            const PopupMenuDivider(),
            const PopupMenuItem(value: 'new', child: Text('★ New playlist with this song…')),
            for (final p in s.playlists) PopupMenuItem(value: 'pl:${p.id}', child: Text('★ Add to ${p.name}')),
            const PopupMenuDivider(),
            const PopupMenuItem(value: 'remove', child: Text('✕ Remove')),
          ]);
          if (!context.mounted) return;
          switch (c) {
            case 'play':
              await s.playEntry(entry);
            case 'singer':
              final name = await askText(
                context,
                title: 'Who is singing?',
                label: 'Singer',
                initial: entry.singer ?? '',
              );
              if (name != null) await s.setSinger(entry, name);
            case 'edit':
              await showEditTags(context, t);
            case 'new':
              final name = await askText(context, title: 'New playlist', label: 'Name');
              if (name != null) await s.createPlaylist(name, tracks: [t]);
            case 'remove':
              await s.removeFromQueue(entry);
            default:
              if (c != null && c.startsWith('pl:')) await s.addToPlaylist(int.parse(c.substring(3)), [t]);
          }
        },
        child: InkWell(
          onDoubleTap: () => s.playEntry(entry),
          child: Container(
            height: 24,
            color: playing ? EzColors.brass.withValues(alpha: 0.2) : null,
            child: Opacity(
              opacity: played ? 0.55 : 1,
              child: Row(
                children: [
                  SizedBox(
                    width: 28,
                    child: playing
                        ? const Icon(Icons.play_arrow, size: 14, color: EzColors.brass)
                        : played
                        ? const Icon(Icons.check, size: 14, color: EzColors.green)
                        : Text('${index + 1}', style: TextStyle(fontSize: 11, color: dim)),
                  ),
                  Expanded(
                    flex: 5,
                    child: Text(
                      t.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                  Expanded(
                    flex: 5,
                    child: Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: t.artist ?? '—',
                            style: TextStyle(color: context.ez.textDim),
                          ),
                          if (entry.singer != null) const TextSpan(text: ' — '),
                          if (entry.singer != null)
                            TextSpan(
                              text: entry.singer,
                              style: const TextStyle(color: EzColors.cyan),
                            ),
                        ],
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                  SizedBox(
                    width: 44,
                    child: Align(alignment: Alignment.centerLeft, child: TypeChip(t.type)),
                  ),
                  SizedBox(
                    width: 96,
                    child: Text(
                      entry.playedAt != null
                          ? whenText(entry.playedAt!)
                          : entry.lastSung != null
                          ? 'last ${whenText(entry.lastSung!)}'
                          : '',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 11, color: entry.playedAt != null ? EzColors.green : dim),
                    ),
                  ),
                  Expanded(
                    flex: 2,
                    child: Text(
                      locationOf(t),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 10, fontFamily: vfdFont, color: context.ez.textDim),
                    ),
                  ),
                  SizedBox(
                    width: 24,
                    child: InkWell(
                      onTap: () => s.removeFromQueue(entry),
                      child: const Icon(Icons.close, size: 14, color: EzColors.red),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

/// "20:51" today, otherwise "4 Nov 20:51".
String whenText(DateTime t, {DateTime? now}) {
  final n = now ?? DateTime.now();
  final hm = '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
  if (t.year == n.year && t.month == n.month && t.day == n.day) return hm;
  return '${t.day} ${_months[t.month - 1]}${t.year == n.year ? '' : ' ${t.year}'} $hm';
}
