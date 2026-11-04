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
    return DragTarget<Track>(
      onAcceptWithDetails: (d) => s.enqueue(d.data),
      builder: (context, cand, _) => Container(
        decoration: BoxDecoration(
          color: context.ez.panel.withValues(alpha: 0.94),
          border: Border.all(color: cand.isNotEmpty ? EzColors.cyan : context.ez.border, width: cand.isNotEmpty ? 2 : 1),
          borderRadius: BorderRadius.circular(10),
        ),
        padding: const EdgeInsets.fromLTRB(10, 8, 10, 6),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            HeadText('Queue · ${s.queue.length} ${s.queue.length == 1 ? 'song' : 'songs'}', color: EzColors.brass),
            const Spacer(),
            if (s.queue.isNotEmpty)
              TextButton(
                style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                onPressed: s.clearQueue,
                child: const Text('Clear', style: TextStyle(fontSize: 11)),
              ),
          ]),
          Container(
            padding: const EdgeInsets.symmetric(vertical: 3),
            decoration: BoxDecoration(border: Border(bottom: BorderSide(color: context.ez.border))),
            child: const Row(children: [
              SizedBox(width: 28, child: HeadText('#')),
              Expanded(flex: 5, child: HeadText('Title')),
              Expanded(flex: 5, child: HeadText('Artist — Singer')),
              SizedBox(width: 44, child: HeadText('Type')),
              Expanded(flex: 3, child: HeadText('Location')),
              SizedBox(width: 24),
            ]),
          ),
          Expanded(
            child: s.queue.isEmpty
                ? Center(
                    child: Text('Double-click a song, or drag it here, to queue it.',
                        style: TextStyle(fontSize: 12, color: context.ez.textDim)))
                : ReorderableListView.builder(
                    buildDefaultDragHandles: false,
                    itemCount: s.queue.length,
                    onReorderItem: (from, to) {
                      s.moveInQueue(s.queue[from], to);
                    },
                    itemBuilder: (context, i) => _QueueRow(key: ValueKey(s.queue[i].id), entry: s.queue[i], index: i),
                  ),
          ),
        ]),
      ),
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
    return ReorderableDragStartListener(
      index: index,
      child: GestureDetector(
        onSecondaryTapDown: (d) async {
          final c = await showMenuAt<String>(context, d.globalPosition, const [
            PopupMenuItem(value: 'play', child: Text('▶ Play now')),
            PopupMenuItem(value: 'singer', child: Text('🎤 Set singer…')),
            PopupMenuItem(value: 'edit', child: Text('✏️ Edit tags…')),
            PopupMenuItem(value: 'remove', child: Text('✕ Remove')),
          ]);
          if (!context.mounted) return;
          switch (c) {
            case 'play':
              await s.playEntry(entry);
            case 'singer':
              final name = await askText(context, title: 'Who is singing?', label: 'Singer', initial: entry.singer ?? '');
              if (name != null) await s.setSinger(entry, name);
            case 'edit':
              await showEditTags(context, t);
            case 'remove':
              await s.removeFromQueue(entry);
          }
        },
        child: InkWell(
          onDoubleTap: () => s.playEntry(entry),
          child: Container(
            height: 26,
            color: playing ? EzColors.brass.withValues(alpha: 0.2) : null,
            child: Row(children: [
              SizedBox(
                width: 28,
                child: playing
                    ? const Icon(Icons.play_arrow, size: 14, color: EzColors.brass)
                    : Text('${index + 1}', style: TextStyle(fontSize: 11, color: context.ez.textDim)),
              ),
              Expanded(flex: 5, child: Text(t.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12))),
              Expanded(
                flex: 5,
                child: Text.rich(
                  TextSpan(children: [
                    TextSpan(text: t.artist ?? '—', style: TextStyle(color: context.ez.textDim)),
                    if (entry.singer != null) const TextSpan(text: ' — '),
                    if (entry.singer != null) TextSpan(text: entry.singer, style: const TextStyle(color: EzColors.cyan)),
                  ]),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12),
                ),
              ),
              SizedBox(width: 44, child: Align(alignment: Alignment.centerLeft, child: TypeChip(t.type))),
              Expanded(
                  flex: 3,
                  child: Text(locationOf(t),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 10, fontFamily: vfdFont, color: context.ez.textDim))),
              SizedBox(
                width: 24,
                child: InkWell(
                  onTap: () => s.removeFromQueue(entry),
                  child: const Icon(Icons.close, size: 14, color: EzColors.red),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}
