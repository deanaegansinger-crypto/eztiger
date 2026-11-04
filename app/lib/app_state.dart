import 'dart:async';
import 'dart:convert';

import 'package:eztiger_core/eztiger_core.dart';
import 'package:flutter/foundation.dart';

import 'player.dart';
import 'ui/common.dart' show SongDrag;

enum PlayMode { single, autoplay }

enum ResultsView { search, playlist, history }

/// Everything the screens show, and every action they can take.
class AppState extends ChangeNotifier {
  AppState(this.db, this.engine) {
    engine.onFinished = _onTrackFinished;
    engine.addListener(_watchForCrossfade);
    engine.addListener(_rememberLoaded);
  }

  final EztigerDatabase db;
  final KaraokeEngine engine;
  late final LibraryScanner scanner = LibraryScanner(db);

  // Settings (top of the rack).
  bool dark = true;
  PlayMode mode = PlayMode.single;
  bool crossfade = false;
  bool autocue = true;

  // Library tree.
  List<Folder> roots = [];
  final Map<int, List<Folder>> children = {};
  final Set<int> expanded = {};
  int? selectedFolderId;
  Folder? get selectedFolder => _findFolder(selectedFolderId);

  // Results.
  ResultsView view = ResultsView.search;
  String query = '';

  /// Browser filter (null shows every type) and sort order.
  TrackType? typeFilter;
  SearchSort sort = SearchSort.relevance;
  List<SearchGroup> results = [];
  int? selectedPlaylistId;
  List<HistoryEntry> history = [];

  // Queue and playlists.
  List<QueueEntry> queue = [];
  int? nowPlayingQueueId;
  List<Playlist> playlists = [];

  // Selection in the results list (indexes into [results]), and songs
  // copied with Ctrl+C.
  final Set<int> selection = {};
  int? _anchor;
  List<Track> copied = [];
  String _copiedText = '';

  bool scanning = false;
  String status = '';
  Timer? _debounce;

  /// Set while the current song fades out into the next one.
  bool _fading = false;
  int _fadeToken = 0;

  /// A song whose crossfade was stopped by hand, so it is not tried again.
  Track? _noFadeFor;

  /// The crossfade fade-out lengths to choose from, and the one in use: the
  /// end of the music fades down to [fadeLevel], then the next song comes in.
  static const fadeOutChoices = [Duration(seconds: 4), Duration(seconds: 2), Duration(milliseconds: 200)];
  Duration fadeOutTime = fadeOutChoices.first;
  static const fadeLevel = 1 / 3;
  static const fadeInTime = Duration(seconds: 2);

  Future<void> init() async {
    await _loadSettings();
    await _reloadFolders();
    await _reloadQueue();
    await _reloadPlaylists();
    await refreshResults();
    if (roots.isNotEmpty) unawaited(rescan());
  }

  // ------------------------------------------------------------ settings

  /// Settings, the volume and the browser filter come back as they were.
  Future<void> _loadSettings() async {
    try {
      final m = jsonDecode(await db.getMeta('settings') ?? '{}') as Map<String, dynamic>;
      dark = m['dark'] as bool? ?? dark;
      mode = PlayMode.values.asNameMap()[m['mode']] ?? mode;
      crossfade = m['crossfade'] as bool? ?? crossfade;
      autocue = m['autocue'] as bool? ?? autocue;
      final fadeMs = m['fadeMs'] as int?;
      fadeOutTime = fadeOutChoices.where((d) => d.inMilliseconds == fadeMs).firstOrNull ?? fadeOutTime;
      typeFilter = TrackType.values.asNameMap()[m['type']];
      sort = SearchSort.values.asNameMap()[m['sort']] ?? sort;
      engine.volume = (m['volume'] as num?)?.toDouble() ?? engine.volume;
      engine.muted = m['muted'] as bool? ?? engine.muted;
    } catch (_) {
      // Unreadable settings: keep the defaults.
    }
    _settingsLoaded = true;
  }

  String _savedSettings = '';
  String _savedLoaded = '';

  void _saveSettings() {
    if (!_settingsLoaded) return;
    final json = jsonEncode({
      'dark': dark,
      'mode': mode.name,
      'crossfade': crossfade,
      'autocue': autocue,
      'fadeMs': fadeOutTime.inMilliseconds,
      'type': typeFilter?.name,
      'sort': sort.name,
      'volume': engine.volume,
      'muted': engine.muted,
    });
    if (json == _savedSettings) return;
    _savedSettings = json;
    unawaited(db.setMeta('settings', json).catchError((_) {}));
  }

  /// Keeps a note of the loaded song and the volume, for next time.
  void _rememberLoaded() {
    if (!_settingsLoaded) return;
    final json = jsonEncode({'track': engine.current?.id, 'queue': nowPlayingQueueId});
    if (json != _savedLoaded) {
      _savedLoaded = json;
      unawaited(db.setMeta('last_loaded', json).catchError((_) {}));
    }
    _saveSettings();
  }

  /// Saving starts only once the saved settings have been read.
  bool _settingsLoaded = false;

  @override
  void notifyListeners() {
    super.notifyListeners();
    _saveSettings();
  }

  void toggleDark() {
    dark = !dark;
    notifyListeners();
  }

  void setMode(PlayMode m) {
    mode = m;
    notifyListeners();
  }

  void toggleCrossfade() {
    crossfade = !crossfade;
    notifyListeners();
  }

  void setFadeOut(Duration d) {
    fadeOutTime = d;
    notifyListeners();
  }

  void toggleAutocue() {
    autocue = !autocue;
    notifyListeners();
    unawaited(_autocue());
  }

  // ------------------------------------------------------------- library

  Future<void> addRootFolder(String path) async {
    await db.folders.addRoot(path);
    await rescan();
  }

  Future<void> removeRootFolder(Folder f) async {
    await db.folders.removeRoot(f.id);
    if (selectedFolderId == f.id) selectedFolderId = null;
    await _reloadFolders();
    await _reloadQueue();
    await refreshResults();
  }

  Future<void> rescan() async {
    if (scanning) return;
    scanning = true;
    status = 'Scanning library…';
    notifyListeners();
    try {
      final report = await scanner.scanAll(
        onProgress: (n, dir) {
          if (n % 20 == 0) {
            status = 'Scanning… $n folders';
            notifyListeners();
          }
        },
      );
      status = report.missingRoots.isNotEmpty
          ? 'Not found: ${report.missingRoots.join(', ')} (nothing changed)'
          : '${report.tracks} tracks'
                '${report.changed ? ' · ${report.added} new, ${report.updated} updated, ${report.removed} removed' : ''}';
    } catch (e) {
      status = 'Scan failed: $e';
    }
    scanning = false;
    await _reloadFolders();
    await refreshResults();
  }

  Future<void> toggleExpanded(Folder f) async {
    if (expanded.remove(f.id)) {
      notifyListeners();
      return;
    }
    expanded.add(f.id);
    children[f.id] = await db.folders.children(f.id);
    notifyListeners();
  }

  Future<void> selectFolder(int? id) async {
    selectedFolderId = id;
    view = ResultsView.search;
    await refreshResults();
  }

  Future<void> setFolderIncluded(Folder f, bool included) async {
    await db.folders.setIncluded(f.id, included);
    await _reloadFolders();
    await refreshResults();
  }

  Future<void> _reloadFolders() async {
    roots = await db.folders.roots();
    for (final id in expanded.toList()) {
      children[id] = await db.folders.children(id);
    }
    notifyListeners();
  }

  Folder? _findFolder(int? id) {
    if (id == null) return null;
    for (final f in [...roots, ...children.values.expand((c) => c)]) {
      if (f.id == id) return f;
    }
    return null;
  }

  // -------------------------------------------------------------- search

  void setQuery(String q) {
    query = q;
    view = ResultsView.search;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 150), refreshResults);
    notifyListeners();
  }

  Future<void> setTypeFilter(TrackType? t) async {
    typeFilter = t;
    view = ResultsView.search;
    await refreshResults();
  }

  Future<void> setSort(SearchSort s) async {
    sort = s;
    view = ResultsView.search;
    await refreshResults();
  }

  Future<void> refreshResults() async {
    switch (view) {
      case ResultsView.search:
        results = await db.search.search(query, folderId: selectedFolderId, type: typeFilter, sort: sort, limit: 500);
      case ResultsView.playlist:
        final id = selectedPlaylistId;
        results = id == null ? [] : (await db.playlists.tracks(id)).map((t) => SearchGroup([t])).toList();
      case ResultsView.history:
        history = await db.history.recent(limit: 500);
        results = history.map((h) => SearchGroup([h.track])).toList();
    }
    selection.clear();
    _anchor = null;
    notifyListeners();
  }

  String get resultsTitle => switch (view) {
    ResultsView.search => selectedFolder?.name ?? 'All folders',
    ResultsView.playlist =>
      playlists.where((p) => p.id == selectedPlaylistId).map((p) => p.name).firstOrNull ?? 'Playlist',
    ResultsView.history => 'History',
  };

  Future<void> editTags(Track t, {required String title, required String artist, required TrackType type}) async {
    await db.tracks.editTags(t.id, title: title, artist: artist, type: type);
    await _reloadQueue();
    await refreshResults();
  }

  // --------------------------------------------------------------- queue

  Future<void> enqueue(Track t, {String? singer}) async {
    await db.queue.add(t.id, singer: singer);
    await _reloadQueue();
    await _autocue();
  }

  /// Called once the window is on screen: cues the queue left from last
  /// time. Not part of [init], because loading a song waits for the video
  /// player, which only starts once the window has drawn.
  /// Brings back the song that was loaded last time (paused), or else
  /// cues the top of the queue.
  Future<void> startUp() async {
    try {
      final last = jsonDecode(await db.getMeta('last_loaded') ?? '{}') as Map<String, dynamic>;
      final entry = queue.where((e) => e.id == last['queue']).firstOrNull;
      final track = last['track'] is int ? await db.tracks.byId(last['track'] as int) : null;
      if (entry != null) {
        await _cue(entry, autostart: false);
      } else if (track != null) {
        await playNow(track, autostart: false);
      }
    } catch (_) {
      // Nothing usable saved: start empty.
    }
    await _autocue();
  }

  /// Autocue: whenever the player is empty, the top of the queue is loaded
  /// paused, ready to go.
  Future<void> _autocue() async {
    if (autocue && engine.current == null && !_fading && queue.isNotEmpty) {
      await _cue(queue.first, autostart: false);
    }
  }

  /// The song that plays after the current one.
  QueueEntry? get upNext => queue.where((e) => e.id != nowPlayingQueueId).firstOrNull;

  Future<void> removeFromQueue(QueueEntry e) async {
    await db.queue.remove(e.id);
    if (e.id == nowPlayingQueueId) {
      nowPlayingQueueId = null;
      await engine.stop();
    }
    await _reloadQueue();
    await _autocue();
  }

  Future<void> moveInQueue(QueueEntry e, int newIndex) async {
    await db.queue.move(e.id, newIndex);
    await _reloadQueue();
  }

  Future<void> setSinger(QueueEntry e, String singer) async {
    await db.queue.setSinger(e.id, singer.trim().isEmpty ? null : singer.trim());
    await _reloadQueue();
  }

  Future<void> clearQueue() async {
    await db.queue.clear();
    nowPlayingQueueId = null;
    await engine.stop();
    await _reloadQueue();
  }

  Future<void> _reloadQueue() async {
    queue = await db.queue.all();
    if (!queue.any((e) => e.id == nowPlayingQueueId)) nowPlayingQueueId = null;
    notifyListeners();
  }

  // ------------------------------------------------------------- playing

  /// Plays a queue entry now.
  Future<void> playEntry(QueueEntry e) => _cue(e, autostart: true);

  /// Plays a track straight away, without queueing it.
  Future<void> playNow(Track t, {bool autostart = true}) async {
    nowPlayingQueueId = null;
    _endFade();
    await engine.load(t, autostart: autostart, skipSilence: autocue);
    notifyListeners();
  }

  Future<void> playPause() async {
    if (engine.current == null) {
      if (queue.isNotEmpty) await playEntry(queue.first);
      return;
    }
    await engine.playPause();
  }

  /// ⏭: the current song counts as sung, and the next one starts.
  Future<void> next({Duration? fadeIn}) async {
    await _finishCurrent();
    if (queue.isNotEmpty) {
      await _cue(queue.first, autostart: true, fadeIn: fadeIn);
    } else {
      await engine.stop();
    }
  }

  /// ⏮: back to the start of the song.
  Future<void> previous() => engine.restart();

  Future<void> _cue(QueueEntry e, {required bool autostart, Duration? fadeIn}) async {
    nowPlayingQueueId = e.id;
    _endFade();
    // Autocue (and a crossfade) start the song at its first note.
    await engine.load(
      e.track,
      singer: e.singer,
      autostart: autostart,
      fadeIn: fadeIn,
      skipSilence: autocue || fadeIn != null,
    );
    notifyListeners();
  }

  Future<void> _finishCurrent() async {
    final id = nowPlayingQueueId;
    nowPlayingQueueId = null;
    if (id != null) {
      await db.queue.markSung(id);
    } else if (engine.current != null && engine.position > const Duration(seconds: 30)) {
      await db.history.log(engine.current!.id, singer: engine.singer);
    }
    await _reloadQueue();
    if (view == ResultsView.history) await refreshResults();
  }

  Future<void> _onTrackFinished() async {
    if (_fading) return; // the crossfade moves on to the next song itself
    await _finishCurrent();
    if (queue.isEmpty) {
      await engine.stop();
      return;
    }
    if (mode == PlayMode.autoplay || crossfade) {
      await _cue(queue.first, autostart: true, fadeIn: crossfade ? fadeInTime : null);
    } else if (autocue) {
      await _cue(queue.first, autostart: false); // ready to go, paused
    } else {
      await engine.stop();
    }
  }

  /// Crossfade: near the end of the music (before any silence at the end of
  /// the file), when another song is queued, fade it out and bring the next
  /// one in at its first note. Works in either play mode.
  void _watchForCrossfade() {
    if (!crossfade || _fading || !engine.playing || engine.current == null || upNext == null) return;
    final end = engine.audioEnd;
    if (end < const Duration(seconds: 8)) return;
    var left = end - engine.position;
    if (left > fadeOutTime) return;
    if (left < const Duration(milliseconds: 200)) left = const Duration(milliseconds: 200); // already in the silence
    if (identical(engine.current, _noFadeFor)) return;
    _fading = true;
    final token = ++_fadeToken;
    final song = engine.current;
    engine.fadeOut(over: left, to: fadeLevel).then((done) async {
      if (token != _fadeToken) return; // something else already moved on
      _fading = false;
      if (!identical(engine.current, song)) return;
      if (done) {
        await next(fadeIn: fadeInTime);
      } else {
        _noFadeFor = song; // paused or volume moved: let it play out
      }
    });
  }

  void _endFade() {
    _fadeToken++;
    _fading = false;
  }

  // ----------------------------------------------------------- selection

  /// A click on result [i]: plain click selects just it, Ctrl toggles it,
  /// Shift selects the block from the last click.
  void selectRow(int i, {bool shift = false, bool ctrl = false}) {
    if (shift && _anchor != null) {
      if (!ctrl) selection.clear();
      final a = _anchor!, lo = a < i ? a : i, hi = a < i ? i : a;
      for (var k = lo; k <= hi; k++) {
        selection.add(k);
      }
    } else if (ctrl) {
      selection.contains(i) ? selection.remove(i) : selection.add(i);
      _anchor = i;
    } else {
      selection
        ..clear()
        ..add(i);
      _anchor = i;
    }
    notifyListeners();
  }

  void selectAll() {
    selection
      ..clear()
      ..addAll(List.generate(results.length, (i) => i));
    notifyListeners();
  }

  void clearSelection() {
    selection.clear();
    notifyListeners();
  }

  /// The rows being acted on: the selection, or just [orRow] when it is not
  /// part of it.
  List<int> selectedRows({int? orRow}) {
    if (orRow != null && !selection.contains(orRow)) return [orRow];
    return selection.where((i) => i < results.length).toList()..sort();
  }

  /// The selected songs in list order, or just row [orRow] when it is not
  /// part of the selection.
  List<Track> selectedTracks({int? orRow}) {
    if (orRow != null && !selection.contains(orRow)) return [results[orRow].primary];
    final rows = selection.where((i) => i < results.length).toList()..sort();
    return [for (final i in rows) results[i].primary];
  }

  /// Ctrl+C: remembers the songs, and puts "Title - Artist" lines on the
  /// Windows clipboard so they can be pasted into Notepad or an email.
  String copy(List<Track> tracks) {
    copied = tracks;
    _copiedText = tracks.map((t) => t.artist == null ? t.title : '${t.title} - ${t.artist}').join('\r\n');
    status = 'Copied ${tracks.length} ${tracks.length == 1 ? 'song' : 'songs'}';
    notifyListeners();
    return _copiedText;
  }

  /// Turns pasted clipboard text into songs: the songs copied here if the
  /// text is ours, otherwise the best match for each line of a song list.
  Future<List<Track>> songsFromClipboard(String? text) async {
    String norm(String x) => x.replaceAll('\r\n', '\n').trim();
    if (text == null || norm(text).isEmpty || (copied.isNotEmpty && norm(text) == norm(_copiedText))) return copied;
    final matches = await db.search.matchList(text);
    final missing = [
      for (final m in matches)
        if (m.$2 == null) m.$1,
    ];
    status =
        'Matched ${matches.length - missing.length} of ${matches.length} lines'
        '${missing.isEmpty ? '' : ' · not found: ${missing.take(5).join(', ')}${missing.length > 5 ? '…' : ''}'}';
    notifyListeners();
    return [
      for (final m in matches)
        if (m.$2 != null) m.$2!,
    ];
  }

  /// Pastes clipboard [text] into a playlist (see [songsFromClipboard]).
  Future<void> paste(int playlistId, String? text) async {
    final tracks = await songsFromClipboard(text);
    final note = status.startsWith('Matched') ? status : null;
    await addToPlaylist(playlistId, tracks);
    if (note != null) {
      status = note.replaceFirst('Matched', 'Pasted');
      notifyListeners();
    }
  }

  /// Songs dropped at position [at] in a playlist. Songs dragged within the
  /// same playlist are moved, anything else is added.
  Future<void> dropIntoPlaylist(int playlistId, SongDrag d, int at) async {
    if (d.playlistId == playlistId) {
      await db.playlists.moveBlock(playlistId, d.positions, at);
    } else {
      await db.playlists.insertAll(playlistId, d.tracks.map((t) => t.id), at: at);
    }
    await _reloadPlaylists();
    if (view == ResultsView.playlist && selectedPlaylistId == playlistId) await refreshResults();
  }

  /// Songs dropped at position [at] in the queue (moved if they came from it).
  Future<void> dropIntoQueue(SongDrag d, int at) async {
    if (d.queueIds.isNotEmpty) {
      await db.queue.moveBlock(d.queueIds, at);
      await _reloadQueue();
      return;
    }
    await db.queue.insertAll(d.tracks.map((t) => t.id), at: at);
    await _reloadQueue();
    await _autocue();
  }

  /// Songs dropped on the player: the first is loaded paused, ready to
  /// play, and the rest go to the top of the queue so they come next.
  Future<void> dropOnPlayer(SongDrag d) async {
    if (d.tracks.isEmpty) return;
    if (d.queueIds.isNotEmpty) {
      final e = queue.where((q) => q.id == d.queueIds.first).firstOrNull;
      if (e != null) await playEntry(e);
      return;
    }
    if (d.tracks.length > 1) {
      await db.queue.insertAll(d.tracks.skip(1).map((t) => t.id), at: 0);
      await _reloadQueue();
    }
    await playNow(d.tracks.first, autostart: false); // loaded paused, ready to go
  }

  Future<void> enqueueAll(List<Track> tracks) async {
    for (final t in tracks) {
      await enqueue(t);
    }
  }

  /// Removes the selected rows from the open playlist.
  Future<void> removeSelectedFromPlaylist() async {
    final id = selectedPlaylistId;
    if (view != ResultsView.playlist || id == null || selection.isEmpty) return;
    await db.playlists.removePositions(id, selection.toList());
    await _reloadPlaylists();
    await refreshResults();
  }

  // ----------------------------------------------------------- playlists

  Future<void> _reloadPlaylists() async {
    playlists = await db.playlists.all();
    notifyListeners();
  }

  /// Makes a playlist, optionally filled with [tracks]. Returns its id, or
  /// null when the name is empty or taken.
  Future<int?> createPlaylist(String name, {List<Track> tracks = const []}) async {
    if (name.trim().isEmpty) return null;
    int? id;
    try {
      id = await db.playlists.create(name);
      if (tracks.isNotEmpty) await db.playlists.addAll(id, tracks.map((t) => t.id));
      status = 'Made "${name.trim()}"${tracks.isEmpty ? '' : ' with ${tracks.length} songs'}';
    } catch (_) {
      status = 'There is already a playlist called "$name"';
    }
    await _reloadPlaylists();
    return id;
  }

  Future<void> deletePlaylist(Playlist p) async {
    await db.playlists.delete(p.id);
    if (selectedPlaylistId == p.id) {
      selectedPlaylistId = null;
      view = ResultsView.search;
    }
    await _reloadPlaylists();
    await refreshResults();
  }

  Future<void> addToPlaylist(int playlistId, List<Track> tracks) async {
    if (tracks.isEmpty) return;
    await db.playlists.addAll(playlistId, tracks.map((t) => t.id));
    final name = playlists.where((p) => p.id == playlistId).map((p) => p.name).firstOrNull ?? 'playlist';
    status = 'Added ${tracks.length} ${tracks.length == 1 ? 'song' : 'songs'} to $name';
    await _reloadPlaylists();
    if (view == ResultsView.playlist && selectedPlaylistId == playlistId) await refreshResults();
  }

  Future<void> saveQueueTo(int playlistId) async {
    await db.playlists.addQueue(playlistId);
    await _reloadPlaylists();
  }

  Future<void> removeFromPlaylist(int position) async {
    final id = selectedPlaylistId;
    if (id == null) return;
    await db.playlists.removeAt(id, position);
    await _reloadPlaylists();
    await refreshResults();
  }

  Future<void> openPlaylist(Playlist p) async {
    view = ResultsView.playlist;
    selectedPlaylistId = p.id;
    await refreshResults();
  }

  Future<void> openHistory() async {
    view = ResultsView.history;
    await refreshResults();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    engine.removeListener(_watchForCrossfade);
    engine.removeListener(_rememberLoaded);
    super.dispose();
  }
}
