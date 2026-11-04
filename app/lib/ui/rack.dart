import 'package:eztiger_core/eztiger_core.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_state.dart';
import '../theme.dart';
import 'common.dart';
import 'dialogs.dart';
import 'logo.dart';

/// The left column of the mockup: player, settings, library, search and
/// results.
class Rack extends StatelessWidget {
  const Rack({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: context.ez.panel,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _BrandRow(),
          SizedBox(height: 8),
          PlayerStrip(),
          SizedBox(height: 6),
          SeekBar(),
          _VolumeRow(),
          SizedBox(height: 6),
          _TogglesRow(),
          SizedBox(height: 8),
          LibraryTabs(),
          SizedBox(height: 8),
          SearchBox(),
          SizedBox(height: 6),
          Expanded(child: ResultsTable()),
          _StatusLine(),
        ],
      ),
    );
  }
}

class _BrandRow extends StatelessWidget {
  const _BrandRow();
  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    return Row(
      children: [
        const EzLogo(size: 30),
        const SizedBox(width: 8),
        const Text(
          'EZTIGER',
          style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18, color: EzColors.brass, letterSpacing: 2),
        ),
        const SizedBox(width: 6),
        Text('BY DEANO', style: TextStyle(fontSize: 10, color: context.ez.textDim, letterSpacing: 1.5)),
        const Spacer(),
        Segmented<bool>(
          options: const {true: 'Dark', false: 'Light'},
          value: s.dark,
          onChanged: (v) => v != s.dark ? s.toggleDark() : null,
          accent: EzColors.brass,
        ),
      ],
    );
  }
}

/// The green-screen "VFD" display plus the transport buttons.
class PlayerStrip extends StatelessWidget {
  const PlayerStrip({super.key});

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final e = s.engine;
    final t = e.current;
    final sub = [if (t?.artist != null) t!.artist!, if (e.singer != null) 'Singer: ${e.singer}'].join(' — ');
    return Row(
      children: [
        Expanded(
          child: DragTarget<SongDrag>(
            onAcceptWithDetails: (d) => s.dropOnPlayer(d.data),
            builder: (context, cand, _) => Container(
              constraints: const BoxConstraints(minHeight: 64),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: EzColors.vfdBg,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: cand.isNotEmpty ? EzColors.cyan : const Color(0xFF0E2A2A),
                  width: cand.isNotEmpty ? 2 : 1,
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        cand.isNotEmpty
                            ? 'DROP TO PLAY NOW'
                            : (t == null ? 'READY' : (e.playing ? 'NOW PLAYING' : 'CUED')),
                        style: const TextStyle(
                          fontFamily: vfdFont,
                          fontSize: 9,
                          color: EzColors.vfdSub,
                          letterSpacing: 2,
                        ),
                      ),
                      const Spacer(),
                      if (t != null)
                        Text(
                          '${fmt(e.position)} / ${fmt(e.duration)}',
                          style: const TextStyle(fontFamily: vfdFont, fontSize: 10, color: EzColors.vfdSub),
                        ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    e.error ?? t?.title ?? 'Pick a song to begin',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: vfdFont,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: e.error != null ? EzColors.red : EzColors.brass,
                    ),
                  ),
                  Text(
                    sub,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontFamily: vfdFont, fontSize: 11, color: EzColors.cyan),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        _Transport(icon: Icons.skip_previous, tooltip: 'Back to the start', onTap: s.previous),
        _Transport(
          icon: e.playing ? Icons.pause : Icons.play_arrow,
          tooltip: e.playing ? 'Pause' : 'Play',
          big: true,
          onTap: s.playPause,
        ),
        _Transport(icon: Icons.skip_next, tooltip: 'Next singer', onTap: s.next),
      ],
    );
  }
}

class _Transport extends StatelessWidget {
  const _Transport({required this.icon, required this.onTap, required this.tooltip, this.big = false});
  final IconData icon;
  final VoidCallback onTap;
  final String tooltip;
  final bool big;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(left: 4),
    child: Tooltip(
      message: tooltip,
      child: Material(
        color: big ? EzColors.brass : context.ez.raised,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox(
            width: big ? 44 : 34,
            height: big ? 44 : 34,
            child: Icon(icon, size: big ? 26 : 18, color: big ? EzColors.onBrass : context.ez.text),
          ),
        ),
      ),
    ),
  );
}

/// The song's progress under the player: click or drag it to skip to any
/// point in the song.
class SeekBar extends StatefulWidget {
  const SeekBar({super.key});
  @override
  State<SeekBar> createState() => _SeekBarState();
}

class _SeekBarState extends State<SeekBar> {
  double? _dragMs; // while the thumb is being dragged

  @override
  Widget build(BuildContext context) {
    final e = AppScope.of(context).engine;
    final total = e.duration.inMilliseconds.toDouble();
    final ready = e.current != null && total > 0;
    final at = (_dragMs ?? e.position.inMilliseconds.toDouble()).clamp(0.0, ready ? total : 1.0);
    final style = TextStyle(fontSize: 10, fontFamily: vfdFont, color: context.ez.textDim);
    return Row(
      children: [
        SizedBox(
          width: 40,
          child: Text(fmt(Duration(milliseconds: at.round())), style: style),
        ),
        Expanded(
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 4,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
              activeTrackColor: EzColors.cyan,
              thumbColor: EzColors.cyan,
              inactiveTrackColor: context.ez.border,
            ),
            child: Slider(
              key: const Key('seek'),
              value: ready ? at : 0,
              max: ready ? total : 1,
              onChangeStart: ready ? (v) => setState(() => _dragMs = v) : null,
              onChanged: ready ? (v) => setState(() => _dragMs = v) : null,
              onChangeEnd: ready
                  ? (v) async {
                      await e.seek(Duration(milliseconds: v.round()));
                      if (mounted) setState(() => _dragMs = null);
                    }
                  : null,
            ),
          ),
        ),
        SizedBox(
          width: 44,
          child: Text(
            ready ? '-${fmt(Duration(milliseconds: (total - at).round()))}' : '--:--',
            textAlign: TextAlign.right,
            style: style,
          ),
        ),
      ],
    );
  }
}

class _VolumeRow extends StatelessWidget {
  const _VolumeRow();
  @override
  Widget build(BuildContext context) {
    final e = AppScope.of(context).engine;
    return Row(
      children: [
        InkWell(
          onTap: e.toggleMute,
          child: Icon(e.muted ? Icons.volume_off : Icons.volume_up, size: 18, color: context.ez.textDim),
        ),
        Expanded(
          child: SliderTheme(
            data: SliderTheme.of(context)
                .copyWith(trackHeight: 3, thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6)),
            child: Slider(value: e.muted ? 0 : e.volume, max: 100, activeColor: EzColors.brass, onChanged: e.setVolume),
          ),
        ),
        SizedBox(
          width: 36,
          child: Text(
            '${(e.muted ? 0 : e.volume).round()}%',
            textAlign: TextAlign.right,
            style: TextStyle(fontSize: 11, color: context.ez.textDim),
          ),
        ),
      ],
    );
  }
}

class _TogglesRow extends StatelessWidget {
  const _TogglesRow();
  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    return Wrap(
      spacing: 14,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Mode', style: TextStyle(fontSize: 11)),
            const SizedBox(width: 6),
            Segmented<PlayMode>(
              options: const {PlayMode.single: 'Single', PlayMode.autoplay: 'Autoplay'},
              value: s.mode,
              onChanged: s.setMode,
            ),
          ],
        ),
        EzSwitch(label: 'Crossfade', value: s.crossfade, onChanged: s.toggleCrossfade),
        EzSwitch(label: 'Autocue', value: s.autocue, onChanged: s.toggleAutocue),
      ],
    );
  }
}

/// "📁 Library" and "★ Playlists" tabs.
class LibraryTabs extends StatefulWidget {
  const LibraryTabs({super.key});
  @override
  State<LibraryTabs> createState() => _LibraryTabsState();
}

class _LibraryTabsState extends State<LibraryTabs> {
  int tab = 0;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            _TabButton(label: '📁 Library', selected: tab == 0, onTap: () => setState(() => tab = 0)),
            const SizedBox(width: 6),
            DragTarget<SongDrag>(
              onWillAcceptWithDetails: (_) {
                if (tab != 1) setState(() => tab = 1);
                return false;
              },
              builder: (context, _, _) =>
                  _TabButton(label: '★ Playlists', selected: tab == 1, onTap: () => setState(() => tab = 1)),
            ),
            const Spacer(),
            if (tab == 0) const _AddFolderButton(),
          ],
        ),
        const SizedBox(height: 4),
        ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 150, minHeight: 60),
          child: RaisedBox(
            padding: const EdgeInsets.all(4),
            child: tab == 0 ? const FolderTree() : const PlaylistsPanel(),
          ),
        ),
      ],
    );
  }
}

class _TabButton extends StatelessWidget {
  const _TabButton({required this.label, required this.selected, required this.onTap});
  final String label;
  final bool selected;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(6),
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: selected ? EzColors.brass : Colors.transparent, width: 2)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: selected ? FontWeight.w700 : FontWeight.normal,
          color: selected ? context.ez.text : context.ez.textDim,
        ),
      ),
    ),
  );
}

class _AddFolderButton extends StatelessWidget {
  const _AddFolderButton();
  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    return TextButton.icon(
      style: TextButton.styleFrom(visualDensity: VisualDensity.compact, foregroundColor: EzColors.brass),
      icon: const Icon(Icons.create_new_folder_outlined, size: 16),
      label: const Text('Add folder', style: TextStyle(fontSize: 11)),
      onPressed: s.scanning
          ? null
          : () async {
              final path = await FilePicker.getDirectoryPath(dialogTitle: 'Choose a karaoke folder');
              if (path != null) await s.addRootFolder(path);
            },
    );
  }
}

class FolderTree extends StatelessWidget {
  const FolderTree({super.key});

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    if (s.roots.isEmpty) {
      return Center(
        child: Text(
          'No folders yet. Press "Add folder" and pick your backing tracks folder.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 11, color: context.ez.textDim),
        ),
      );
    }
    final rows = <(Folder, int)>[];
    void add(Folder f, int depth) {
      rows.add((f, depth));
      if (s.expanded.contains(f.id)) {
        for (final c in s.children[f.id] ?? const <Folder>[]) {
          add(c, depth + 1);
        }
      }
    }

    for (final r in s.roots) {
      add(r, 0);
    }
    return ListView(
      shrinkWrap: true,
      children: [
        _FolderRow(
          label: 'All folders',
          depth: 0,
          selected: s.selectedFolderId == null,
          onTap: () => s.selectFolder(null),
        ),
        for (final (f, d) in rows) _FolderTile(folder: f, depth: d),
      ],
    );
  }
}

class _FolderTile extends StatelessWidget {
  const _FolderTile({required this.folder, required this.depth});
  final Folder folder;
  final int depth;

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final f = folder;
    return GestureDetector(
      onSecondaryTapDown: (d) async {
        final choice = await showMenuAt<String>(context, d.globalPosition, [
          if (f.included)
            const PopupMenuItem(value: 'exclude', child: Text('✓ In searchable library — remove'))
          else
            const PopupMenuItem(value: 'include', child: Text('➕ Add to searchable library')),
          if (f.isRoot) const PopupMenuItem(value: 'rescan', child: Text('🔄 Rescan')),
          if (f.isRoot) const PopupMenuItem(value: 'forget', child: Text('🗑 Forget this folder')),
        ]);
        switch (choice) {
          case 'include':
            await s.setFolderIncluded(f, true);
          case 'exclude':
            await s.setFolderIncluded(f, false);
          case 'rescan':
            await s.rescan();
          case 'forget':
            await s.removeRootFolder(f);
        }
      },
      child: _FolderRow(
        label: f.name,
        depth: depth,
        count: f.totalCount,
        included: f.included,
        expandable: f.hasChildren,
        expanded: s.expanded.contains(f.id),
        selected: s.selectedFolderId == f.id,
        onTap: () => s.selectFolder(f.id),
        onToggle: () => s.toggleExpanded(f),
      ),
    );
  }
}

class _FolderRow extends StatelessWidget {
  const _FolderRow({
    required this.label,
    required this.depth,
    required this.selected,
    required this.onTap,
    this.count,
    this.included = true,
    this.expandable = false,
    this.expanded = false,
    this.onToggle,
  });
  final String label;
  final int depth;
  final bool selected, included, expandable, expanded;
  final int? count;
  final VoidCallback onTap;
  final VoidCallback? onToggle;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    onDoubleTap: onToggle,
    child: Container(
      color: selected ? EzColors.brass.withValues(alpha: 0.18) : null,
      padding: EdgeInsets.only(left: 4.0 + depth * 14, right: 6, top: 2, bottom: 2),
      child: Row(
        children: [
          SizedBox(
            width: 16,
            child: expandable
                ? InkWell(onTap: onToggle, child: Icon(expanded ? Icons.expand_more : Icons.chevron_right, size: 14))
                : null,
          ),
          Icon(
            expanded ? Icons.folder_open : Icons.folder,
            size: 14,
            color: included ? EzColors.brass : context.ez.textDim,
          ),
          const SizedBox(width: 5),
          Expanded(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, color: included ? context.ez.text : context.ez.textDim),
            ),
          ),
          if (count != null) Text('$count', style: TextStyle(fontSize: 10, color: context.ez.textDim)),
          if (count != null && included)
            const Padding(
              padding: EdgeInsets.only(left: 4),
              child: Text('✓', style: TextStyle(fontSize: 10, color: EzColors.cyan)),
            ),
        ],
      ),
    ),
  );
}

class PlaylistsPanel extends StatelessWidget {
  const PlaylistsPanel({super.key});
  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    return ListView(
      shrinkWrap: true,
      children: [
        Row(
          children: [
            DragTarget<SongDrag>(
              onAcceptWithDetails: (d) async {
                final name = await askText(
                  context,
                  title: 'New playlist with ${d.data.tracks.length} songs',
                  label: 'Name',
                );
                if (name != null) await s.createPlaylist(name, tracks: d.data.tracks);
              },
              builder: (context, cand, _) => Container(
                decoration: BoxDecoration(
                  color: cand.isNotEmpty ? EzColors.cyan.withValues(alpha: 0.25) : null,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: TextButton(
                  style: TextButton.styleFrom(visualDensity: VisualDensity.compact, foregroundColor: EzColors.brass),
                  onPressed: () async {
                    final name = await askText(context, title: 'New playlist', label: 'Name');
                    if (name != null) await s.createPlaylist(name);
                  },
                  child: Text(
                    cand.isNotEmpty ? '+ Drop here for a new playlist' : '+ Create',
                    style: const TextStyle(fontSize: 11),
                  ),
                ),
              ),
            ),
            const Spacer(),
            TextButton(
              style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
              onPressed: s.openHistory,
              child: const Text('🕘 History', style: TextStyle(fontSize: 11)),
            ),
          ],
        ),
        if (s.playlists.isEmpty)
          Padding(
            padding: const EdgeInsets.all(6),
            child: Text(
              'Drag songs onto "+ Create" to make a playlist.',
              style: TextStyle(fontSize: 11, color: context.ez.textDim),
            ),
          ),
        for (final p in s.playlists)
          DragTarget<SongDrag>(
            onAcceptWithDetails: (d) => s.addToPlaylist(p.id, d.data.tracks),
            builder: (context, cand, _) => GestureDetector(
              onSecondaryTapDown: (d) async {
                final c = await showMenuAt<String>(context, d.globalPosition, [
                  const PopupMenuItem(value: 'open', child: Text('Open')),
                  PopupMenuItem(
                    value: 'paste',
                    child: Text(
                      s.copied.isEmpty ? '📋 Paste songs or a song list' : '📋 Paste ${s.copied.length} copied songs',
                    ),
                  ),
                  const PopupMenuItem(value: 'queue', child: Text('Save the queue into this playlist')),
                  const PopupMenuItem(value: 'toqueue', child: Text('➕ Add the whole playlist to the queue')),
                  const PopupMenuItem(value: 'delete', child: Text('Delete playlist')),
                ]);
                switch (c) {
                  case 'open':
                    await s.openPlaylist(p);
                  case 'paste':
                    await pasteInto(s, p.id);
                  case 'queue':
                    await s.saveQueueTo(p.id);
                  case 'toqueue':
                    await s.enqueueAll(await s.db.playlists.tracks(p.id));
                  case 'delete':
                    await s.deletePlaylist(p);
                }
              },
              child: InkWell(
                onTap: () => s.openPlaylist(p),
                child: Container(
                  color: cand.isNotEmpty
                      ? EzColors.cyan.withValues(alpha: 0.25)
                      : (s.view == ResultsView.playlist && s.selectedPlaylistId == p.id
                            ? EzColors.brass.withValues(alpha: 0.18)
                            : null),
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  child: Row(
                    children: [
                      const Text('★ ', style: TextStyle(color: EzColors.brass, fontSize: 12)),
                      Expanded(
                        child: Text(p.name, style: const TextStyle(fontSize: 12), overflow: TextOverflow.ellipsis),
                      ),
                      Text('${p.trackCount}', style: TextStyle(fontSize: 10, color: context.ez.textDim)),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Pastes into a playlist: songs copied with Ctrl+C, or a song list copied
/// from Notepad, Word or Excel (one song per line).
Future<void> pasteInto(AppState s, int playlistId) async {
  final data = await Clipboard.getData(Clipboard.kTextPlain);
  await s.paste(playlistId, data?.text);
}

class SearchBox extends StatefulWidget {
  const SearchBox({super.key});
  @override
  State<SearchBox> createState() => _SearchBoxState();
}

class _SearchBoxState extends State<SearchBox> {
  final _c = TextEditingController();
  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    return TextField(
      controller: _c,
      onChanged: s.setQuery,
      style: const TextStyle(fontSize: 13),
      decoration: InputDecoration(
        isDense: true,
        hintText: 'Search title, artist or lyrics…',
        prefixIcon: const Padding(
          padding: EdgeInsets.all(8),
          child: Text('🔍', style: TextStyle(fontSize: 14)),
        ),
        prefixIconConstraints: const BoxConstraints(minWidth: 32),
        suffixIcon: _c.text.isEmpty
            ? null
            : IconButton(
                icon: const Icon(Icons.close, size: 16),
                onPressed: () {
                  _c.clear();
                  s.setQuery('');
                },
              ),
        filled: true,
        fillColor: context.ez.raised,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: context.ez.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: context.ez.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: EzColors.brass),
        ),
      ),
    );
  }
}

class TypeChip extends StatelessWidget {
  const TypeChip(this.type, {super.key});
  final TrackType type;
  @override
  Widget build(BuildContext context) {
    final c = EzColors.forType(type.label);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        border: Border.all(color: c),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        type.label,
        style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: c),
      ),
    );
  }
}

class ResultsTable extends StatefulWidget {
  const ResultsTable({super.key});
  @override
  State<ResultsTable> createState() => _ResultsTableState();
}

class _ResultsTableState extends State<ResultsTable> {
  final focus = FocusNode(debugLabel: 'results');

  @override
  void dispose() {
    focus.dispose();
    super.dispose();
  }

  KeyEventResult _onKey(AppState s, KeyEvent e) {
    if (e is! KeyDownEvent) return KeyEventResult.ignored;
    final ctrl = HardwareKeyboard.instance.isControlPressed;
    final k = e.logicalKey;
    if (ctrl && k == LogicalKeyboardKey.keyA) {
      s.selectAll();
    } else if (ctrl && k == LogicalKeyboardKey.keyC) {
      final tracks = s.selectedTracks();
      if (tracks.isNotEmpty) Clipboard.setData(ClipboardData(text: s.copy(tracks)));
    } else if (ctrl && k == LogicalKeyboardKey.keyV && s.view == ResultsView.playlist && s.selectedPlaylistId != null) {
      pasteInto(s, s.selectedPlaylistId!);
    } else if ((k == LogicalKeyboardKey.delete || k == LogicalKeyboardKey.backspace) &&
        s.view == ResultsView.playlist) {
      s.removeSelectedFromPlaylist();
    } else if (k == LogicalKeyboardKey.enter) {
      s.enqueueAll(s.selectedTracks());
    } else if (k == LogicalKeyboardKey.escape && s.selection.isNotEmpty) {
      s.clearSelection();
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final groups = s.results;
    final label = switch (s.view) {
      ResultsView.search => s.query.isEmpty ? 'Browse' : 'Search results',
      ResultsView.playlist => 'Playlist (drag to reorder)',
      ResultsView.history => 'Sung',
    };
    final n = s.selection.length;
    return Focus(
      focusNode: focus,
      onKeyEvent: (_, e) => _onKey(s, e),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '$label · ${s.resultsTitle} · ${groups.length} ${groups.length == 1 ? 'match' : 'matches'}'
            '${n > 1 ? ' · $n selected (drag them, or Ctrl+C)' : ''}',
            style: TextStyle(fontSize: 11, color: context.ez.textDim),
          ),
          const SizedBox(height: 4),
          const _ResultsHeader(),
          Expanded(
            child: groups.isEmpty
                ? DragTarget<SongDrag>(
                    onWillAcceptWithDetails: (_) => s.view == ResultsView.playlist && s.selectedPlaylistId != null,
                    onAcceptWithDetails: (d) => s.dropIntoPlaylist(s.selectedPlaylistId!, d.data, 0),
                    builder: (context, _, _) => Center(
                      child: Text(
                        s.view == ResultsView.playlist
                            ? 'Empty playlist. Drag songs here, or right-click it and paste.'
                            : s.roots.isEmpty
                            ? 'Add a folder to start.'
                            : (s.scanning ? 'Scanning…' : 'Nothing found.'),
                        textAlign: TextAlign.center,
                        style: TextStyle(color: context.ez.textDim),
                      ),
                    ),
                  )
                : DragTarget<SongDrag>(
                    onWillAcceptWithDetails: (_) => s.view == ResultsView.playlist && s.selectedPlaylistId != null,
                    onAcceptWithDetails: (d) => s.dropIntoPlaylist(s.selectedPlaylistId!, d.data, groups.length),
                    builder: (context, _, _) => ListView.builder(
                      itemCount: groups.length,
                      itemExtent: 28,
                      itemBuilder: (context, i) => ResultRow(group: groups[i], index: i, focus: focus),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _ResultsHeader extends StatelessWidget {
  const _ResultsHeader();
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
    decoration: BoxDecoration(
      border: Border(bottom: BorderSide(color: context.ez.border)),
    ),
    child: const Row(
      children: [
        Expanded(flex: 5, child: HeadText('Title')),
        Expanded(flex: 4, child: HeadText('Artist')),
        SizedBox(width: 44, child: HeadText('Type')),
        Expanded(flex: 3, child: HeadText('Location')),
      ],
    ),
  );
}

class ResultRow extends StatefulWidget {
  const ResultRow({super.key, required this.group, required this.index, this.focus});
  final SearchGroup group;
  final int index;
  final FocusNode? focus;
  @override
  State<ResultRow> createState() => _ResultRowState();
}

class _ResultRowState extends State<ResultRow> {
  bool _dragged = false;

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final group = widget.group, index = widget.index;
    final t = group.primary;
    final selected = s.selection.contains(index);
    final row = InkWell(
      onDoubleTap: () => s.enqueue(t),
      child: Container(
        color: selected
            ? EzColors.brass.withValues(alpha: 0.28)
            : (index.isOdd ? context.ez.raised.withValues(alpha: 0.4) : null),
        padding: const EdgeInsets.symmetric(horizontal: 6),
        child: Row(
          children: [
            Expanded(
              flex: 5,
              child: Text.rich(
                TextSpan(
                  children: [
                    TextSpan(text: t.title),
                    if (t.version != null)
                      TextSpan(
                        text: '  ${t.version}',
                        style: TextStyle(color: context.ez.textDim, fontSize: 10),
                      ),
                    if (group.versions.length > 1)
                      TextSpan(
                        text: '  ×${group.versions.length}',
                        style: const TextStyle(color: EzColors.cyan, fontSize: 10),
                      ),
                  ],
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12),
              ),
            ),
            Expanded(
              flex: 4,
              child: Text(
                t.artist ?? '—',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12, color: context.ez.textDim),
              ),
            ),
            SizedBox(
              width: 44,
              child: Align(alignment: Alignment.centerLeft, child: TypeChip(t.type)),
            ),
            Expanded(
              flex: 3,
              child: Text(
                locationOf(t),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 10, fontFamily: vfdFont, color: context.ez.textDim),
              ),
            ),
          ],
        ),
      ),
    );
    final rows = s.selectedRows(orRow: index);
    final inPlaylist = s.view == ResultsView.playlist ? s.selectedPlaylistId : null;
    final dragging = SongDrag([for (final r in rows) s.results[r].primary], playlistId: inPlaylist, positions: rows);
    return Listener(
      onPointerDown: (e) {
        widget.focus?.requestFocus();
        _dragged = false;
        final keys = HardwareKeyboard.instance;
        final shift = keys.isShiftPressed, ctrl = keys.isControlPressed;
        if (e.buttons == kSecondaryMouseButton) {
          if (!selected) s.selectRow(index);
        } else if (shift || ctrl) {
          s.selectRow(index, shift: shift, ctrl: ctrl);
        } else if (!selected) {
          s.selectRow(index);
        }
      },
      onPointerUp: (e) {
        final keys = HardwareKeyboard.instance;
        // A plain click inside a block (without dragging) narrows it to one row.
        if (!_dragged &&
            selected &&
            s.selection.length > 1 &&
            !keys.isShiftPressed &&
            !keys.isControlPressed &&
            e.kind == PointerDeviceKind.mouse &&
            e.buttons == 0 &&
            e.down == false) {
          s.selectRow(index);
        }
      },
      child: GestureDetector(
        onSecondaryTapDown: (d) => trackMenu(context, d.globalPosition, group, tracks: s.selectedTracks(orRow: index)),
        child: Draggable<SongDrag>(
          data: dragging,
          dragAnchorStrategy: pointerDragAnchorStrategy,
          onDragStarted: () => _dragged = true,
          feedback: dragChip(dragging),
          child: inPlaylist == null
              ? row
              : InsertTarget(index: index, onDrop: (d, at) => s.dropIntoPlaylist(inPlaylist, d, at), child: row),
        ),
      ),
    );
  }
}

/// Right-click menu for one song or a block of selected songs.
Future<void> trackMenu(BuildContext context, Offset at, SearchGroup group, {required List<Track> tracks}) async {
  final s = AppScope.of(context);
  final t = group.primary;
  final many = tracks.length > 1;
  final n = '${tracks.length} songs';
  final inPlaylist = s.view == ResultsView.playlist;
  final choice = await showMenuAt<String>(context, at, [
    PopupMenuItem(value: 'queue', child: Text(many ? '➕ Add $n to the queue' : '➕ Add to queue')),
    if (!many) const PopupMenuItem(value: 'singer', child: Text('🎤 Add to queue with singer…')),
    if (!many) const PopupMenuItem(value: 'play', child: Text('▶ Play now')),
    if (!many && group.versions.length > 1) const PopupMenuItem(value: 'versions', child: Text('🎚 Other versions…')),
    const PopupMenuDivider(),
    PopupMenuItem(value: 'new', child: Text(many ? '★ New playlist from these $n…' : '★ New playlist with this song…')),
    for (final p in s.playlists) PopupMenuItem(value: 'pl:${p.id}', child: Text('★ Add to ${p.name}')),
    PopupMenuItem(value: 'copy', child: Text(many ? '📋 Copy $n   Ctrl+C' : '📋 Copy   Ctrl+C')),
    if (inPlaylist)
      PopupMenuItem(
        value: 'unlist',
        child: Text(many ? 'Remove $n from this playlist   Del' : 'Remove from this playlist   Del'),
      ),
    if (!many) const PopupMenuItem(value: 'edit', child: Text('✏️ Edit tags…')),
  ]);
  if (!context.mounted || choice == null) return;
  switch (choice) {
    case 'queue':
      await s.enqueueAll(tracks);
    case 'singer':
      final name = await askText(context, title: 'Who is singing?', label: 'Singer');
      if (name != null) await s.enqueue(t, singer: name);
    case 'play':
      await s.playNow(t);
    case 'versions':
      final v = await pickVersion(context, group);
      if (v != null) await s.enqueue(v);
    case 'new':
      final name = await askText(context, title: 'New playlist', label: 'Name');
      if (name != null) await s.createPlaylist(name, tracks: tracks);
    case 'copy':
      await Clipboard.setData(ClipboardData(text: s.copy(tracks)));
    case 'unlist':
      await s.removeSelectedFromPlaylist();
    case 'edit':
      await showEditTags(context, t);
    default:
      if (choice.startsWith('pl:')) await s.addToPlaylist(int.parse(choice.substring(3)), tracks);
  }
}

class _StatusLine extends StatelessWidget {
  const _StatusLine();
  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        children: [
          if (s.scanning) const SizedBox(width: 10, height: 10, child: CircularProgressIndicator(strokeWidth: 1.5)),
          if (s.scanning) const SizedBox(width: 6),
          Expanded(
            child: Text(
              s.status,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 10, color: context.ez.textDim),
            ),
          ),
        ],
      ),
    );
  }
}
