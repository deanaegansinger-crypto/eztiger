import 'package:eztiger_core/eztiger_core.dart';
import 'package:flutter/material.dart';

import '../app_state.dart';
import '../edition.dart';
import '../platform.dart';
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
    return ListText(child: _build(context, s));
  }

  Widget _build(BuildContext context, AppState s) {
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
            ListControls(
              child: Row(
                children: [
                  // The title gives way to the buttons on a narrow screen.
                  Expanded(
                    flex: 2,
                    child: HeadText(
                      '$queueTitle · ${s.queue.length - s.playedCount} to sing'
                      '${s.playedCount > 0 ? ' · ${s.playedCount} played' : ''}',
                      color: EzColors.brass,
                    ),
                  ),
                  // On a narrow screen the buttons scroll sideways rather than spill over.
                  Flexible(
                    flex: 3,
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      reverse: true,
                      child: Row(
                        children: [
                          const _LoadPlaylistButton(),
                          if (isPro && s.queuePlaylist != null && s.queue.isNotEmpty)
                            TextButton(
                              key: const Key('save-changes-button'),
                              style: TextButton.styleFrom(visualDensity: tapDensity),
                              onPressed: () => s.replacePlaylistWithQueue(s.queuePlaylistId!),
                              child: Text(
                                '💾 Save to ${s.queuePlaylist!.name}',
                                style: TextStyle(fontSize: 11, color: EzColors.brass),
                              ),
                            ),
                          if (s.queue.isNotEmpty) const _SaveQueueButton(),
                          if (s.playedCount > 0)
                            TextButton(
                              key: const Key('clear-played'),
                              style: TextButton.styleFrom(visualDensity: tapDensity),
                              onPressed: s.clearPlayed,
                              child: const Text('Clear played', style: TextStyle(fontSize: 11)),
                            ),
                          if (s.queue.isNotEmpty)
                            TextButton(
                              style: TextButton.styleFrom(visualDensity: tapDensity),
                              onPressed: s.clearQueue,
                              child: const Text('Clear', style: TextStyle(fontSize: 11)),
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(vertical: 3),
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: context.ez.border)),
              ),
              child: Row(
                children: [
                  SizedBox(width: listSize(context, 28), child: const HeadText('#')),
                  const Expanded(flex: 5, child: HeadText('Title')),
                  const Expanded(flex: 5, child: HeadText('Artist — Singer')),
                  SizedBox(width: listSize(context, 44), child: const HeadText('Type')),
                  SizedBox(width: listSize(context, 96), child: const HeadText('Played')),
                  const Expanded(flex: 2, child: HeadText('Location')),
                  SizedBox(width: listSize(context, 24)),
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
                      itemExtent: listSize(context, 28),
                      itemBuilder: (context, i) => _QueueRow(key: ValueKey(s.queue[i].id), entry: s.queue[i], index: i),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// "📂 Load playlist": puts a saved playlist's songs at the end of the queue.
class _LoadPlaylistButton extends StatelessWidget {
  const _LoadPlaylistButton();

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    return PopupMenuButton<int>(
      key: const Key('load-playlist'),
      tooltip: 'Add a saved playlist to $theQueue',
      itemBuilder: (_) => [
        if (s.playlists.isEmpty)
          const PopupMenuItem(enabled: false, child: Text('No playlists yet: use "★ Save as playlist" first'))
        else
          for (final p in s.playlists)
            PopupMenuItem(
              value: p.id,
              child: Text('★ ${p.name}  (${p.trackCount == 1 ? '1 song' : '${p.trackCount} songs'})'),
            ),
      ],
      onSelected: s.loadPlaylistIntoQueue,
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: touchUi ? 12 : 8, vertical: touchUi ? 12 : 4),
        child: Text('📂 Load playlist', style: TextStyle(fontSize: 11, color: EzColors.brass)),
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
      tooltip: isPro ? "Save Tonight's playlist as a playlist of its own" : 'Save the queue as a playlist',
      itemBuilder: (_) => [
        if (isPro && s.queuePlaylist != null)
          PopupMenuItem(
            key: const Key('save-changes'),
            value: 'replace:${s.queuePlaylist!.id}',
            child: Text('💾 Save changes to ${s.queuePlaylist!.name}'),
          ),
        PopupMenuItem(value: 'new', child: Text('★ New playlist from $theQueue ($n)…')),
        if (isPro)
          for (final p in s.playlists)
            if (p.id != s.queuePlaylistId)
              PopupMenuItem(value: 'replace:${p.id}', child: Text('💾 Replace ${p.name} with $theQueue')),
        for (final p in s.playlists) PopupMenuItem(value: 'pl:${p.id}', child: Text('★ Add $theQueue to ${p.name}')),
      ],
      onSelected: (c) async {
        if (c == 'new') {
          final name = await askText(context, title: 'New playlist from $theQueue ($n)', label: 'Name');
          if (name != null) await s.createPlaylist(name, tracks: tracks);
        } else if (c.startsWith('replace:')) {
          await s.replacePlaylistWithQueue(int.parse(c.substring(8)));
        } else if (c.startsWith('pl:')) {
          await s.addToPlaylist(int.parse(c.substring(3)), tracks);
        }
      },
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: touchUi ? 12 : 8, vertical: touchUi ? 12 : 4),
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
            height: listSize(context, 24),
            color: playing ? EzColors.brass.withValues(alpha: 0.2) : null,
            child: Opacity(
              opacity: played ? 0.55 : 1,
              child: Row(
                children: [
                  SizedBox(
                    width: listSize(context, 28),
                    child: playing
                        ? Icon(Icons.play_arrow, size: 14, color: EzColors.brass)
                        : played
                        ? Icon(Icons.check, size: 14, color: EzColors.green)
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
                              style: TextStyle(color: EzColors.cyan),
                            ),
                        ],
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                  SizedBox(
                    width: listSize(context, 44),
                    child: Align(alignment: Alignment.centerLeft, child: TypeChip(t.type)),
                  ),
                  SizedBox(
                    width: listSize(context, 96),
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
                    width: listSize(context, 24),
                    child: InkWell(
                      onTap: () => s.removeFromQueue(entry),
                      child: Icon(Icons.close, size: 14, color: EzColors.red),
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
