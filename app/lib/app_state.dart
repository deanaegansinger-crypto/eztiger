import 'dart:async';

import 'package:eztiger_core/eztiger_core.dart';
import 'package:flutter/foundation.dart';

import 'player.dart';

enum PlayMode { single, autoplay }

enum ResultsView { search, playlist, history }

/// Everything the screens show, and every action they can take.
class AppState extends ChangeNotifier {
  AppState(this.db, this.engine) {
    engine.onFinished = _onTrackFinished;
    engine.addListener(_watchForCrossfade);
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
  List<SearchGroup> results = [];
  int? selectedPlaylistId;
  List<HistoryEntry> history = [];

  // Queue and playlists.
  List<QueueEntry> queue = [];
  int? nowPlayingQueueId;
  List<Playlist> playlists = [];

  bool scanning = false;
  String status = '';
  Timer? _debounce;
  bool _fading = false;

  Future<void> init() async {
    await _reloadFolders();
    await _reloadQueue();
    await _reloadPlaylists();
    await refreshResults();
    if (roots.isNotEmpty) unawaited(rescan());
  }

  // ------------------------------------------------------------ settings

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

  void toggleAutocue() {
    autocue = !autocue;
    notifyListeners();
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
      final report = await scanner.scanAll(onProgress: (n, dir) {
        if (n % 20 == 0) {
          status = 'Scanning… $n folders';
          notifyListeners();
        }
      });
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

  Future<void> refreshResults() async {
    switch (view) {
      case ResultsView.search:
        results = await db.search.search(query, folderId: selectedFolderId, limit: 500);
      case ResultsView.playlist:
        final id = selectedPlaylistId;
        results = id == null
            ? []
            : (await db.playlists.tracks(id)).map((t) => SearchGroup([t])).toList();
      case ResultsView.history:
        history = await db.history.recent(limit: 500);
        results = history.map((h) => SearchGroup([h.track])).toList();
    }
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
    if (engine.current == null && autocue && queue.length == 1) {
      await _cue(queue.first, autostart: false);
    }
  }

  Future<void> removeFromQueue(QueueEntry e) async {
    await db.queue.remove(e.id);
    if (e.id == nowPlayingQueueId) {
      nowPlayingQueueId = null;
      await engine.stop();
    }
    await _reloadQueue();
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
  Future<void> playNow(Track t) async {
    nowPlayingQueueId = null;
    await engine.load(t);
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
  Future<void> next() async {
    await _finishCurrent();
    if (queue.isNotEmpty) {
      await _cue(queue.first, autostart: true);
    } else {
      await engine.stop();
    }
  }

  /// ⏮: back to the start of the song.
  Future<void> previous() => engine.restart();

  Future<void> _cue(QueueEntry e, {required bool autostart}) async {
    nowPlayingQueueId = e.id;
    _fading = false;
    await engine.load(e.track, singer: e.singer, autostart: autostart);
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
    await _finishCurrent();
    if (queue.isEmpty) {
      await engine.stop();
      return;
    }
    if (mode == PlayMode.autoplay) {
      await _cue(queue.first, autostart: true);
    } else if (autocue) {
      await _cue(queue.first, autostart: false); // ready to go, paused
    } else {
      await engine.stop();
    }
  }

  void _watchForCrossfade() {
    if (!crossfade || mode != PlayMode.autoplay || _fading || queue.length < 2) return;
    final left = engine.duration - engine.position;
    if (engine.playing && engine.duration > const Duration(seconds: 10) && left < const Duration(seconds: 3)) {
      _fading = true;
      engine.fadeOut(over: left).then((_) => next());
    }
  }

  // ----------------------------------------------------------- playlists

  Future<void> _reloadPlaylists() async {
    playlists = await db.playlists.all();
    notifyListeners();
  }

  Future<void> createPlaylist(String name) async {
    if (name.trim().isEmpty) return;
    try {
      await db.playlists.create(name);
    } catch (_) {
      status = 'There is already a playlist called "$name"';
    }
    await _reloadPlaylists();
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

  Future<void> addToPlaylist(int playlistId, int trackId) async {
    await db.playlists.add(playlistId, trackId);
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
    super.dispose();
  }
}
