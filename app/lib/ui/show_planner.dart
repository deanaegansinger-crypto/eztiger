import 'dart:async';

import 'package:eztiger_core/eztiger_core.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../app_state.dart';
import '../preview.dart';
import '../show_plan.dart';
import '../theme.dart';
import 'common.dart';
import 'dialogs.dart';
import 'transfer_dialogs.dart';

/// The app's state without listening to it: allowed in initState.
AppState _stateOf(BuildContext context) => context.getInheritedWidgetOfExactType<AppScope>()!.notifier!;

/// The show planner (EZTiger Pro on the PC): a singer's evening built from
/// the whole library, with sets and intervals (and their break music), a
/// note on any song, its key, and a start time, so each song shows when it
/// starts and the show when it finishes. Songs can be heard first through
/// the preview output (headphones). Every change is saved as it's made,
/// into the playlist, ready to send to the tablet.
Future<void> showShowPlanner(BuildContext context, Playlist pl) => showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => Dialog.fullscreen(child: _Planner(pl)),
    );

/// A show's running order with its times, sets, intervals and notes, to
/// read (on the tablet, or on the PC).
Future<void> showRunningOrder(BuildContext context, Playlist pl) => showDialog<void>(
      context: context,
      builder: (_) => _RunningOrder(pl),
    );

class _Planner extends StatefulWidget {
  const _Planner(this.pl);
  final Playlist pl;
  @override
  State<_Planner> createState() => _PlannerState();
}

class _PlannerState extends State<_Planner> {
  ShowPlan? plan;

  /// The library's song for each path in the show.
  final Map<String, Track> tracks = {};
  List<SearchGroup> results = [];
  final find = TextEditingController(), start = TextEditingController();
  final listFocus = FocusNode();
  int? selected;
  List<PreviewDevice> devices = [];
  Timer? _searchSoon, _saveSoon;
  late final AppState s;

  @override
  void initState() {
    super.initState();
    s = _stateOf(context);
    _load();
  }

  Future<void> _load() async {
    final x = await s.planFor(widget.pl.id);
    for (final t in await s.db.playlists.tracks(widget.pl.id)) {
      tracks[t.path] = t;
    }
    final d = await s.previewDevices();
    await _search();
    if (!mounted) return;
    setState(() {
      plan = x;
      start.text = x.start ?? '';
      devices = d;
    });
  }

  @override
  void dispose() {
    _searchSoon?.cancel();
    if (_saveSoon?.isActive ?? false) {
      _saveSoon!.cancel();
      unawaited(_save());
    }
    // (Once the tree is unlocked: stopping tells the screens.)
    if (s.previewing != null) scheduleMicrotask(s.stopPreview);
    find.dispose();
    start.dispose();
    listFocus.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final r = await s.db.search.search(find.text, limit: 200);
    if (mounted) setState(() => results = r);
  }

  /// Saves soon after the last change (so typing isn't slowed down).
  void _changed() {
    setState(() {});
    _saveSoon?.cancel();
    _saveSoon = Timer(const Duration(milliseconds: 400), _save);
  }

  Future<void> _save() async {
    final x = plan;
    if (x == null) return;
    x.start = start.text.trim().isEmpty ? null : start.text.trim();
    await s.savePlan(widget.pl.id, x, [for (final path in x.songPaths) tracks[path]!]);
  }

  int get _insertAt => selected == null ? plan!.items.length : selected! + 1;

  void _addSong(Track t, {int? at}) {
    tracks[t.path] = t;
    final i = (at ?? _insertAt).clamp(0, plan!.items.length);
    plan!.items.insert(i, ShowItem.song(t.path));
    selected = i;
    _changed();
  }

  void _addInterval() {
    final i = _insertAt;
    plan!.items.insert(i, ShowItem.interval());
    selected = i;
    _changed();
  }

  void _remove(int i) {
    plan!.items.removeAt(i);
    if (plan!.items.isEmpty) {
      selected = null;
    } else if (selected != null) {
      selected = selected!.clamp(0, plan!.items.length - 1);
    }
    _changed();
  }

  void _move(int from, int to) {
    final items = plan!.items;
    if (to < 0 || to >= items.length) return;
    items.insert(to, items.removeAt(from));
    selected = to;
    _changed();
  }

  Future<void> _editNote(ShowItem item) async {
    final text = await askText(context, title: 'Note', label: 'Shown under the song (and on the tablet)', initial: item.note);
    if (text == null) return;
    item.note = text.trim();
    _changed();
  }

  Future<void> _renameInterval(ShowItem item) async {
    final text = await askText(context, title: 'Interval', label: 'What it says (e.g. Interval, Bingo, Food break)', initial: item.label);
    if (text == null || text.trim().isEmpty) return;
    item.label = text.trim();
    _changed();
  }

  Future<void> _pickMusic(ShowItem item) async {
    final picked = await FilePicker.pickFiles(
      dialogTitle: 'Break music: MP3s or videos to play in the interval',
      type: FileType.custom,
      allowedExtensions: ['mp3', 'mp4', 'm4a', 'wav', 'wma', 'avi', 'mpg', 'mkv', 'mov'],
    );
    final paths = <String>[for (final f in picked) ?f.path];
    if (paths.isEmpty) return;
    item.music.addAll(paths);
    _changed();
  }

  KeyEventResult _keys(FocusNode _, KeyEvent e) {
    final i = selected;
    if (e is! KeyDownEvent || i == null || plan == null) return KeyEventResult.ignored;
    final alt = HardwareKeyboard.instance.isAltPressed;
    if (e.logicalKey == LogicalKeyboardKey.delete) {
      _remove(i);
    } else if (alt && e.logicalKey == LogicalKeyboardKey.arrowUp) {
      _move(i, i - 1);
    } else if (alt && e.logicalKey == LogicalKeyboardKey.arrowDown) {
      _move(i, i + 1);
    } else if (e.logicalKey == LogicalKeyboardKey.arrowUp) {
      setState(() => selected = (i - 1).clamp(0, plan!.items.length - 1));
    } else if (e.logicalKey == LogicalKeyboardKey.arrowDown) {
      setState(() => selected = (i + 1).clamp(0, plan!.items.length - 1));
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  Future<void> _send() async {
    _saveSoon?.cancel();
    await _save();
    if (mounted) await showSendPlaylist(context, widget.pl);
  }

  Future<void> _toQueue() async {
    _saveSoon?.cancel();
    await _save();
    await s.loadPlaylistIntoQueue(widget.pl.id);
    if (mounted) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(s.status)));
    }
  }

  @override
  Widget build(BuildContext context) {
    AppScope.of(context); // rebuild on the preview starting and stopping
    final x = plan;
    return Scaffold(
      key: const Key('show-planner'),
      appBar: AppBar(
        title: Text('🗓 Plan the show: ★ ${widget.pl.name}'),
        actions: [
          if (s.previewing != null)
            TextButton.icon(
              key: const Key('planner-stop-preview'),
              onPressed: s.stopPreview,
              icon: const Icon(Icons.stop),
              label: Text('Stop ${p.basenameWithoutExtension(s.previewing!)}', overflow: TextOverflow.ellipsis),
            ),
          if (devices.isNotEmpty) _deviceMenu(),
          const SizedBox(width: 8),
          TextButton.icon(
            key: const Key('planner-to-queue'),
            onPressed: x == null || x.songCount == 0 ? null : _toQueue,
            icon: const Icon(Icons.playlist_add),
            label: const Text('Load into Tonight’s playlist'),
          ),
          FilledButton.icon(
            key: const Key('planner-send'),
            onPressed: x == null || x.songCount == 0 ? null : _send,
            icon: const Icon(Icons.wifi),
            label: const Text('Send to the tablet'),
          ),
          const SizedBox(width: 8),
          TextButton(key: const Key('planner-done'), onPressed: () => Navigator.pop(context), child: const Text('Done')),
          const SizedBox(width: 8),
        ],
      ),
      body: x == null
          ? const Center(child: CircularProgressIndicator())
          : Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(width: 420, child: _library()),
                VerticalDivider(width: 1, color: context.ez.border),
                Expanded(child: _show(x)),
              ],
            ),
    );
  }

  Widget _deviceMenu() => Tooltip(
        message: 'Where previews play: pick headphones to hear songs while the room hears the live deck',
        child: Row(children: [
          const Icon(Icons.headphones, size: 18),
          const SizedBox(width: 6),
          DropdownButton<String>(
            key: const Key('planner-device'),
            value: devices.any((d) => d.id == s.previewDevice) ? s.previewDevice : null,
            hint: const Text('Preview output'),
            underline: const SizedBox(),
            items: [
              for (final d in devices)
                DropdownMenuItem(value: d.id, child: SizedBox(width: 220, child: Text(d.name, overflow: TextOverflow.ellipsis))),
            ],
            onChanged: (id) {
              if (id != null) s.setPreviewDevice(id);
            },
          ),
        ]),
      );

  // ------------------------------------------------------- the library

  Widget _library() => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
            child: TextField(
              key: const Key('planner-find'),
              controller: find,
              autofocus: true,
              decoration: const InputDecoration(
                isDense: true,
                prefixIcon: Icon(Icons.search),
                hintText: 'Find a song or artist in the library…',
              ),
              onChanged: (_) {
                _searchSoon?.cancel();
                _searchSoon = Timer(const Duration(milliseconds: 250), _search);
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(
              'Double-click or ➕ to add after the picked line · drag onto the show · ▶ to hear it first',
              style: TextStyle(fontSize: 11, color: context.ez.textDim),
            ),
          ),
          const SizedBox(height: 4),
          Expanded(
            child: ListView.builder(
              itemCount: results.length,
              itemExtent: 46,
              itemBuilder: (context, i) {
                final t = results[i].primary;
                final len = s.lengthOfPath(t.path);
                final row = InkWell(
                  key: Key('planner-result-${t.id}'),
                  onDoubleTap: () => _addSong(t),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Row(children: [
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(t.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13)),
                            Text(t.artist ?? '', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, color: context.ez.textDim)),
                          ],
                        ),
                      ),
                      if (len != null) Text(showLength(len), style: TextStyle(fontSize: 11, color: context.ez.textDim)),
                      _previewButton(t.path),
                      IconButton(
                        key: Key('planner-add-${t.id}'),
                        tooltip: 'Add to the show',
                        icon: Icon(Icons.add_circle_outline, color: EzColors.brass),
                        onPressed: () => _addSong(t),
                      ),
                    ]),
                  ),
                );
                return Draggable<Track>(
                  data: t,
                  feedback: Material(
                    color: Colors.transparent,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(color: EzColors.brass, borderRadius: BorderRadius.circular(6)),
                      child: Text(t.title, style: TextStyle(color: EzColors.onBrass, fontWeight: FontWeight.w700)),
                    ),
                  ),
                  child: row,
                );
              },
            ),
          ),
        ],
      );

  Widget _previewButton(String path) {
    final on = s.previewing == path;
    if (s.preview == null) return const SizedBox(width: 8);
    return IconButton(
      tooltip: on ? 'Stop' : 'Hear it (through the preview output)',
      icon: Icon(on ? Icons.stop_circle : Icons.play_circle_outline, color: on ? EzColors.red : EzColors.cyan),
      onPressed: () => s.togglePreview(path),
    );
  }

  // ---------------------------------------------------------- the show

  Widget _show(ShowPlan x) {
    final times = x.times(s.lengthOfPath);
    final sets = x.sets;
    final finish = times.finish;
    final summary = [
      '${x.songCount} song${x.songCount == 1 ? '' : 's'}',
      '${x.setCount} set${x.setCount == 1 ? '' : 's'}',
      showLengthWords(times.total),
      if (finish != null) 'finishes $finish',
      if (times.guesses > 0) '(${times.guesses} length${times.guesses == 1 ? '' : 's'} guessed)',
    ].join(' · ');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          color: context.ez.raised,
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
          child: Row(children: [
            const Text('Starts at '),
            SizedBox(
              width: 110,
              child: TextField(
                key: const Key('planner-start'),
                controller: start,
                decoration: InputDecoration(
                  isDense: true,
                  hintText: '9:00 pm',
                  errorText: start.text.trim().isNotEmpty && parseStartTime(start.text) == null ? 'e.g. 9:00 pm' : null,
                ),
                onChanged: (_) {
                  x.start = start.text.trim().isEmpty ? null : start.text.trim();
                  _changed();
                },
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Text(summary,
                  key: const Key('planner-summary'),
                  style: TextStyle(color: EzColors.brass, fontWeight: FontWeight.w700),
                  overflow: TextOverflow.ellipsis),
            ),
            OutlinedButton.icon(
              key: const Key('planner-add-interval'),
              onPressed: _addInterval,
              icon: const Text('☕'),
              label: const Text('Add an interval'),
            ),
          ]),
        ),
        Expanded(
          child: DragTarget<Track>(
            onAcceptWithDetails: (d) => _addSong(d.data, at: x.items.length),
            builder: (context, cand, _) => Focus(
              focusNode: listFocus,
              onKeyEvent: _keys,
              child: x.items.isEmpty
                  ? Center(
                      child: Text(
                        cand.isNotEmpty ? 'Drop it here' : 'Add songs from the library on the left.',
                        style: TextStyle(color: context.ez.textDim),
                      ),
                    )
                  : ReorderableListView.builder(
                      key: const Key('planner-show'),
                      buildDefaultDragHandles: false,
                      padding: const EdgeInsets.only(bottom: 80),
                      itemCount: x.items.length,
                      // (The new place is already counted without the moved line.)
                      onReorderItem: _move,
                      header: Padding(
                        padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
                        child: Text('Set 1', style: TextStyle(fontWeight: FontWeight.w800, color: EzColors.cyan)),
                      ),
                      itemBuilder: (context, i) => _row(x, i, times, sets),
                    ),
            ),
          ),
        ),
        Container(
          color: context.ez.raised,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Text(
            'Drag ☰ to reorder (or Alt+↑/↓) · Delete takes the picked line out · every change is saved straight away',
            style: TextStyle(fontSize: 11, color: context.ez.textDim),
          ),
        ),
      ],
    );
  }

  Widget _row(ShowPlan x, int i, ShowTimes times, List<int> sets) {
    final item = x.items[i];
    final picked = selected == i;
    final dim = context.ez.textDim;
    final key = ObjectKey(item);
    void pick() {
      setState(() => selected = i);
      listFocus.requestFocus();
    }

    final handle = ReorderableDragStartListener(
      index: i,
      child: const MouseRegion(cursor: SystemMouseCursors.grab, child: Padding(padding: EdgeInsets.all(8), child: Icon(Icons.drag_handle, size: 18))),
    );
    final remove = IconButton(
      key: Key('planner-remove-$i'),
      tooltip: 'Take it out',
      icon: Icon(Icons.close, size: 18, color: EzColors.red),
      onPressed: () => _remove(i),
    );

    if (item.isBreak) {
      final songsAfter = [for (var j = i + 1; j < x.items.length && !x.items[j].isBreak; j++) j].length;
      return DragTarget<Track>(
        key: key,
        // A song dropped on an interval is its break music.
        onAcceptWithDetails: (d) {
          tracks[d.data.path] = d.data;
          item.music.add(d.data.path);
          _changed();
        },
        builder: (context, cand, _) => Material(
          color: cand.isNotEmpty
              ? EzColors.cyan.withValues(alpha: 0.25)
              : EzColors.brassDim.withValues(alpha: picked ? 0.55 : 0.3),
          child: InkWell(
            key: Key('planner-row-$i'),
            onTap: pick,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                handle,
                SizedBox(width: 74, child: Padding(padding: const EdgeInsets.only(top: 8), child: Text(times.clockAt(i), style: TextStyle(color: dim)))),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      InkWell(
                        onTap: () => _renameInterval(item),
                        child: Text('☕ ${item.label}', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: EzColors.brass)),
                      ),
                      const SizedBox(width: 12),
                      IconButton(
                        key: Key('planner-break-less-$i'),
                        tooltip: '5 minutes less',
                        icon: const Icon(Icons.remove, size: 16),
                        onPressed: item.minutes <= 5
                            ? null
                            : () {
                                item.minutes -= 5;
                                _changed();
                              },
                      ),
                      Text('${item.minutes} min', key: Key('planner-break-minutes-$i')),
                      IconButton(
                        key: Key('planner-break-more-$i'),
                        tooltip: '5 minutes more',
                        icon: const Icon(Icons.add, size: 16),
                        onPressed: () {
                          item.minutes += 5;
                          _changed();
                        },
                      ),
                      const SizedBox(width: 12),
                      Text('then Set ${sets[i]} · $songsAfter song${songsAfter == 1 ? '' : 's'}',
                          style: TextStyle(fontWeight: FontWeight.w700, color: EzColors.cyan)),
                    ]),
                    Wrap(spacing: 6, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
                      Text('🎵 Break music:', style: TextStyle(fontSize: 12, color: dim)),
                      if (item.music.isEmpty) Text('none yet (drop songs here, or pick files)', style: TextStyle(fontSize: 12, color: dim)),
                      for (final (n, m) in item.music.indexed)
                        InputChip(
                          key: Key('planner-music-$i-$n'),
                          label: Text(p.basenameWithoutExtension(m), style: const TextStyle(fontSize: 12)),
                          avatar: Icon(s.previewing == m ? Icons.stop : Icons.play_arrow, size: 16),
                          onPressed: s.preview == null ? null : () => s.togglePreview(m),
                          onDeleted: () {
                            item.music.removeAt(n);
                            _changed();
                          },
                        ),
                      ActionChip(
                        key: Key('planner-music-pick-$i'),
                        avatar: const Icon(Icons.library_music, size: 16),
                        label: const Text('Pick MP3s or videos…', style: TextStyle(fontSize: 12)),
                        onPressed: () => _pickMusic(item),
                      ),
                    ]),
                    if (item.note.isNotEmpty) Text('📝 ${item.note}', style: TextStyle(fontSize: 12, color: EzColors.cyan)),
                  ]),
                ),
                IconButton(tooltip: 'Note', icon: const Icon(Icons.edit_note, size: 20), onPressed: () => _editNote(item)),
                remove,
              ]),
            ),
          ),
        ),
      );
    }

    final t = tracks[item.path!];
    final number = x.items.take(i + 1).where((it) => !it.isBreak).length;
    final keyNow = s.keyShifts[item.path!] ?? 0;
    return DragTarget<Track>(
      key: key,
      // A song dropped on a song goes in after it.
      onAcceptWithDetails: (d) => _addSong(d.data, at: i + 1),
      builder: (context, cand, _) => Material(
        color: cand.isNotEmpty
            ? EzColors.cyan.withValues(alpha: 0.2)
            : (picked ? EzColors.brass.withValues(alpha: 0.18) : Colors.transparent),
        child: InkWell(
          key: Key('planner-row-$i'),
          // (No double-click here: it would hold up every button in the
          // row while it waited to see. The 📝 button opens the note.)
          onTap: pick,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(children: [
              handle,
              SizedBox(width: 28, child: Text('$number', style: TextStyle(color: dim))),
              SizedBox(width: 74, child: Text(times.clockAt(i), key: Key('planner-time-$i'))),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                  Text(t?.title ?? p.basenameWithoutExtension(item.path!),
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                  Text(t?.artist ?? '', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, color: dim)),
                  if (item.note.isNotEmpty)
                    Text('📝 ${item.note}', key: Key('planner-note-$i'), maxLines: 2, overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12, color: EzColors.cyan)),
                ]),
              ),
              SizedBox(
                width: 56,
                child: Text(
                  '${times.guessed[i] ? '~' : ''}${showLength(times.lengths[i])}',
                  style: TextStyle(fontSize: 12, color: times.guessed[i] ? dim : null),
                ),
              ),
              // The key it's sung in, as on the decks.
              IconButton(
                key: Key('planner-key-down-$i'),
                tooltip: 'Key down',
                icon: const Icon(Icons.remove, size: 16),
                onPressed: keyNow <= -3 ? null : () => s.setKeyForPath(item.path!, keyNow - 1),
              ),
              SizedBox(
                width: 30,
                child: Text(keyNow == 0 ? 'key' : (keyNow > 0 ? '+$keyNow' : '$keyNow'),
                    key: Key('planner-key-$i'),
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12, color: keyNow == 0 ? dim : EzColors.brass, fontWeight: FontWeight.w700)),
              ),
              IconButton(
                key: Key('planner-key-up-$i'),
                tooltip: 'Key up',
                icon: const Icon(Icons.add, size: 16),
                onPressed: keyNow >= 3 ? null : () => s.setKeyForPath(item.path!, keyNow + 1),
              ),
              _previewButton(item.path!),
              IconButton(
                key: Key('planner-note-button-$i'),
                tooltip: 'Note',
                icon: Icon(Icons.edit_note, size: 20, color: item.note.isEmpty ? dim : EzColors.cyan),
                onPressed: () => _editNote(item),
              ),
              remove,
            ]),
          ),
        ),
      ),
    );
  }
}

// ------------------------------------------------------- running order

class _RunningOrder extends StatefulWidget {
  const _RunningOrder(this.pl);
  final Playlist pl;
  @override
  State<_RunningOrder> createState() => _RunningOrderState();
}

class _RunningOrderState extends State<_RunningOrder> {
  ShowPlan? plan;
  final Map<String, Track> tracks = {};

  @override
  void initState() {
    super.initState();
    final s = _stateOf(context);
    () async {
      final x = await s.planFor(widget.pl.id);
      for (final t in await s.db.playlists.tracks(widget.pl.id)) {
        tracks[t.path] = t;
      }
      if (mounted) setState(() => plan = x);
    }();
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final x = plan;
    final times = x?.times(s.lengthOfPath);
    final dim = context.ez.textDim;
    return AlertDialog(
      key: const Key('running-order'),
      title: Text('🗓 ${widget.pl.name}'),
      content: SizedBox(
        width: 560,
        height: 520,
        child: x == null || times == null
            ? const Center(child: CircularProgressIndicator())
            : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Text(
                  [
                    if (times.startsAt != null) 'Starts ${clockTime(times.startsAt!)}',
                    '${x.songCount} songs',
                    showLengthWords(times.total),
                    if (times.finish != null) 'finishes ${times.finish}',
                  ].join(' · '),
                  style: TextStyle(color: EzColors.brass, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: ListView(children: [
                    Text('Set 1', style: TextStyle(fontWeight: FontWeight.w800, color: EzColors.cyan)),
                    for (final (i, item) in x.items.indexed)
                      if (item.isBreak)
                        Container(
                          margin: const EdgeInsets.symmetric(vertical: 6),
                          padding: const EdgeInsets.all(8),
                          color: EzColors.brassDim.withValues(alpha: 0.3),
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text('${times.clockAt(i)}  ☕ ${item.label} · ${item.minutes} min',
                                style: TextStyle(fontWeight: FontWeight.w800, color: EzColors.brass)),
                            if (item.music.isNotEmpty)
                              Text('🎵 ${item.music.map(p.basenameWithoutExtension).join(', ')}', style: TextStyle(fontSize: 12, color: dim)),
                            if (item.note.isNotEmpty) Text('📝 ${item.note}', style: TextStyle(fontSize: 12, color: EzColors.cyan)),
                            const SizedBox(height: 4),
                            Text('Set ${x.sets[i]}', style: TextStyle(fontWeight: FontWeight.w800, color: EzColors.cyan)),
                          ]),
                        )
                      else
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 3),
                          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            SizedBox(width: 74, child: Text(times.clockAt(i), style: TextStyle(color: dim))),
                            Expanded(
                              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Text(
                                  [tracks[item.path!]?.title ?? p.basenameWithoutExtension(item.path!), tracks[item.path!]?.artist]
                                      .whereType<String>()
                                      .join(' – '),
                                  style: const TextStyle(fontWeight: FontWeight.w600),
                                ),
                                if (item.note.isNotEmpty) Text('📝 ${item.note}', style: TextStyle(fontSize: 12, color: EzColors.cyan)),
                              ]),
                            ),
                            Text('${times.guessed[i] ? '~' : ''}${showLength(times.lengths[i])}', style: TextStyle(fontSize: 12, color: dim)),
                          ]),
                        ),
                  ]),
                ),
              ]),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close'))],
    );
  }
}
