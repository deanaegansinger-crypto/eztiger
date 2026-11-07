import 'dart:async';
import 'dart:convert';

import 'package:eztiger_core/eztiger_core.dart';
import 'package:flutter/foundation.dart';

import 'edition.dart';
import 'platform.dart';
import 'player.dart';
import 'sync.dart';
import 'ui/common.dart' show SongDrag;

enum PlayMode { single, autoplay }

enum ResultsView { search, playlist, history }

/// Everything the screens show, and every action they can take.
class AppState extends ChangeNotifier {
  /// [deckB] is the second player for the 2-deck mode (Windows only).
  AppState(this.db, KaraokeEngine deckA, {KaraokeEngine? deckB}) : decks = [deckA, ?deckB] {
    for (final d in decks) {
      d.onFinished = () {
        if (identical(d, engine)) _onTrackFinished();
      };
      void onChange() {
        if (!identical(d, engine)) return;
        _watchForCrossfade();
        _rememberLoaded();
      }

      _deckListeners.add(onChange);
      d.keyShiftFor = (t) => isPro ? keyShifts[t.path] ?? 0 : 0;
      d.onKeyShift = _rememberKey;
      d.addListener(onChange);
    }
  }

  final EztigerDatabase db;

  /// The players: one, or two for the 2-deck mode.
  final List<KaraokeEngine> decks;
  final List<VoidCallback> _deckListeners = [];
  int _live = 0;

  /// The player on the screen and in the speakers.
  KaraokeEngine get engine => decks[_live];

  /// 0 for deck A, 1 for deck B.
  int get liveDeck => _live;

  /// 2-deck mode: the queue feeds the two players in turn. While one plays,
  /// the next song waits cued on the other, and a crossfade overlaps them.
  bool twoDecks = false;
  bool get canTwoDecks => decks.length > 1 && isPro;

  /// In 2-deck mode, the deck that isn't playing, where the next song waits.
  KaraokeEngine? get standby => twoDecks && canTwoDecks ? decks[1 - _live] : null;

  /// The queue entry cued on [standby].
  int? standbyQueueId;

  /// Set while the last song fades out on the other deck.
  bool _oldFading = false;
  Future<void> _standbyChain = Future.value();
  late final LibraryScanner scanner = LibraryScanner(db);

  // Settings (top of the rack).
  bool dark = true;

  /// The look of the app (an EzSkin id), picked in ☰ Menu → Skin.
  String skin = 'classic';
  PlayMode mode = PlayMode.single;
  bool crossfade = false;

  /// Text size for the song lists (queue, search results, library and
  /// playlists): 1 is normal. The player and karaoke screen don't change.
  double textScale = 1.0;

  /// The stage view, for performing: big lyrics, big buttons, what's next.
  /// It comes back on at start-up if it was on, ready for the gig.
  bool stageView = false;

  /// In the stage view: the lyrics on the right and the buttons on the
  /// left, instead of the other way round.
  bool stageLyricsRight = false;

  /// The Library / Playlists box is folded away, for more room for the songs.
  bool libraryCollapsed = false;

  /// Pro: the 🔒 screen lock is offered (☰ Menu → Screen lock button).
  bool lockEnabled = true;

  /// Pro: the screen is locked, so a bump on the mic stand can't stop or
  /// skip a song. Press and hold the lock to unlock. Not saved: EZTiger
  /// always starts unlocked.
  bool locked = false;

  void setLockEnabled(bool v) {
    lockEnabled = v;
    if (!v) locked = false;
    notifyListeners();
  }

  void setLocked(bool v) {
    locked = v && lockEnabled && isPro;
    notifyListeners();
  }

  static final textScaleChoices = {1.0: 'Normal', 1.25: 'Large', 1.5: 'Extra large'};
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

  /// Pro: the crossfade slider goes from 0 (a cut) to 6 seconds.
  static const maxFade = Duration(seconds: 6);

  /// Pro, 2 decks: the next song comes in while this one fades (overlap),
  /// or after it has faded out (back to back).
  bool fadeOverlap = true;

  /// Pro: equal-power fades (smooth) or straight-line ones.
  bool smoothFades = true;

  /// How long the next song takes to come in. Pro mixes over the slider's
  /// time (overlapping), or up to 2 s after a fade out; Basic always 2 s.
  Duration? get fadeInLength {
    if (!isPro) return fadeInTime;
    if (fadeOutTime < const Duration(milliseconds: 300)) return null;
    if (standby != null && fadeOverlap) return fadeOutTime;
    return fadeOutTime < fadeInTime ? fadeOutTime : fadeInTime;
  }

  /// Loads everything saved. [rescanLibrary] is false on Android until the
  /// app is allowed to read the SD card (it rescans once it is).
  Future<void> init({bool rescanLibrary = true}) async {
    await _loadSettings();
    await _loadKeys();
    _applyFadeShape();
    await _reloadFolders();
    await _reloadQueue();
    await _reloadPlaylists();
    await refreshResults();
    if (rescanLibrary && roots.isNotEmpty) unawaited(rescan());
  }

  /// Pro was switched on by a licence key: bring back the Pro settings
  /// (skin, 2 decks, fades, Level and Vocal cut) and the song keys.
  Future<void> editionChanged() async {
    if (isPro) {
      await _loadSettings();
      await _loadKeys();
    }
    _applyFadeShape();
    notifyListeners();
  }

  // ------------------------------------------------------------ settings

  /// Settings, the volume and the browser filter come back as they were.
  Future<void> _loadSettings() async {
    try {
      final m = jsonDecode(await db.getMeta('settings') ?? '{}') as Map<String, dynamic>;
      dark = m['dark'] as bool? ?? dark;
      if (isPro) skin = m['skin'] as String? ?? skin;
      mode = PlayMode.values.asNameMap()[m['mode']] ?? mode;
      crossfade = m['crossfade'] as bool? ?? crossfade;
      stageView = m['stage'] as bool? ?? stageView;
      stageLyricsRight = m['stageLyricsRight'] as bool? ?? stageLyricsRight;
      libraryCollapsed = m['libraryCollapsed'] as bool? ?? libraryCollapsed;
      lockEnabled = m['lockEnabled'] as bool? ?? lockEnabled;
      twoDecks = canTwoDecks && (m['twoDecks'] as bool? ?? twoDecks);
      final scale = (m['textScale'] as num?)?.toDouble();
      if (textScaleChoices.containsKey(scale)) textScale = scale!;
      autocue = m['autocue'] as bool? ?? autocue;
      final fadeMs = m['fadeMs'] as int?;
      fadeOutTime = fadeOutChoices.where((d) => d.inMilliseconds == fadeMs).firstOrNull ?? fadeOutTime;
      if (isPro && fadeMs != null && fadeMs >= 0 && fadeMs <= maxFade.inMilliseconds) {
        fadeOutTime = Duration(milliseconds: fadeMs);
      }
      if (isPro) {
        fadeOverlap = m['fadeOverlap'] as bool? ?? fadeOverlap;
        smoothFades = m['smoothFades'] as bool? ?? smoothFades;
      }
      typeFilter = TrackType.values.asNameMap()[m['type']];
      sort = SearchSort.values.asNameMap()[m['sort']] ?? sort;
      engine.volume = (m['volume'] as num?)?.toDouble() ?? engine.volume;
      engine.muted = m['muted'] as bool? ?? engine.muted;
      if (isPro && audioFilters) {
        final level = m['levelLoudness'] as bool? ?? false, cut = m['vocalCut'] as bool? ?? false;
        for (final d in decks) {
          d.levelLoudness = level;
          d.vocalCut = cut;
        }
      }
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
      'skin': skin,
      'mode': mode.name,
      'crossfade': crossfade,
      'textScale': textScale,
      'stage': stageView,
      'stageLyricsRight': stageLyricsRight,
      'libraryCollapsed': libraryCollapsed,
      'lockEnabled': lockEnabled,
      'twoDecks': twoDecks,
      'autocue': autocue,
      'fadeMs': fadeOutTime.inMilliseconds,
      'fadeOverlap': fadeOverlap,
      'smoothFades': smoothFades,
      'type': typeFilter?.name,
      'sort': sort.name,
      'volume': engine.volume,
      'muted': engine.muted,
      'levelLoudness': engine.levelLoudness,
      'vocalCut': engine.vocalCut,
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

  void setSkin(String id) {
    skin = id;
    notifyListeners();
  }

  void setMode(PlayMode m) {
    mode = m;
    notifyListeners();
  }

  void setStageView(bool v) {
    stageView = v;
    notifyListeners();
  }

  // ------------------------------------------------- Pro sound options

  /// The key each song was last sung in, by file path (EZTiger Pro).
  Map<String, int> keyShifts = {};

  Future<void> _loadKeys() async {
    try {
      final m = jsonDecode(await db.getMeta('key_shifts') ?? '{}') as Map<String, dynamic>;
      keyShifts = {for (final e in m.entries) e.key: (e.value as num).toInt()};
    } catch (_) {
      keyShifts = {};
    }
  }

  void _rememberKey(Track t, int semitones) {
    if (semitones == 0) {
      keyShifts.remove(t.path);
    } else {
      keyShifts[t.path] = semitones;
    }
    unawaited(db.setMeta('key_shifts', jsonEncode(keyShifts)).catchError((_) {}));
  }

  /// Sync with the tablet (or the PC): playlists and keys, as one file.
  /// On in Pro, and on the tablet so it can swap with the PC.
  bool get canSync => isPro || touchUi;

  Future<String> exportSync() => LibrarySync(db).export(keyShifts: keyShifts);

  Future<SyncResult> importSync(String json) async {
    final r = await LibrarySync(db).import(json, keyShifts: keyShifts);
    await db.setMeta('key_shifts', jsonEncode(keyShifts));
    await _reloadPlaylists();
    return r;
  }

  /// Key up or down a semitone for the song on the player (−3 to +3).
  Future<void> keyUp() => keyUpOn(engine);
  Future<void> keyDown() => keyDownOn(engine);
  Future<void> keyReset() => engine.setKeyShift(0);

  /// Pro, 2 decks: the key of the song on either deck, so the song waiting
  /// on the other deck can be set before it plays. It is remembered too.
  Future<void> keyUpOn(KaraokeEngine deck) => deck.setKeyShift(deck.keyShift + 1);
  Future<void> keyDownOn(KaraokeEngine deck) => deck.setKeyShift(deck.keyShift - 1);

  Future<void> setLevelLoudness(bool on) async {
    for (final d in decks) {
      await d.setLevelLoudness(on);
    }
    notifyListeners();
  }

  Future<void> setVocalCut(bool on) async {
    for (final d in decks) {
      await d.setVocalCut(on);
    }
    notifyListeners();
  }

  void setStageLyricsRight(bool v) {
    stageLyricsRight = v;
    notifyListeners();
  }

  Future<void> setTwoDecks(bool v) async {
    if (!canTwoDecks || v == twoDecks) return;
    final other = decks[1 - _live];
    twoDecks = v;
    _applyFadeShape();
    notifyListeners();
    if (v) {
      await _cueStandby();
    } else {
      standbyQueueId = null;
      _oldFading = false;
      await other.stop();
    }
  }

  /// 2-deck mode: keeps the next song in the queue cued on the other deck.
  Future<void> _cueStandby() {
    if (standby == null) return Future.value();
    _standbyChain = _standbyChain.then((_) => _doCueStandby()).catchError((_) {});
    return _standbyChain;
  }

  Future<void> _doCueStandby() async {
    final sb = standby;
    if (sb == null || _oldFading) return;
    final up = upNext;
    if (up == null) {
      standbyQueueId = null;
      if (sb.current != null) await sb.stop();
      notifyListeners();
      return;
    }
    if (standbyQueueId == up.id && identical(sb.current, up.track)) return;
    if (standbyQueueId == up.id && sb.current?.id == up.track.id) return;
    standbyQueueId = up.id;
    await sb.load(up.track, singer: up.singer, autostart: false, skipSilence: autocue || crossfade);
    notifyListeners();
  }

  void setLibraryCollapsed(bool v) {
    libraryCollapsed = v;
    notifyListeners();
  }

  void setTextScale(double v) {
    textScale = v;
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

  void setFadeOverlap(bool v) {
    fadeOverlap = v;
    _applyFadeShape();
    notifyListeners();
  }

  void setSmoothFades(bool v) {
    smoothFades = v;
    _applyFadeShape();
    notifyListeners();
  }

  /// Pro: an overlapping mix brings the next song up from silence; a fade
  /// that leaves a gap brings it up from a third, as Basic does.
  void _applyFadeShape() {
    for (final d in decks) {
      d.smoothFades = isPro && smoothFades;
      d.fadeInFrom = isPro && twoDecks && fadeOverlap ? 0 : 1 / 3;
    }
  }

  /// Pro: mixes into the next song now, over the crossfade time.
  Future<void> mixNow() async {
    if (_fading || engine.current == null || upNext == null) return;
    if (!engine.playing) return next(fadeIn: null);
    _startCrossfade(fadeOutTime < const Duration(milliseconds: 200) ? const Duration(milliseconds: 200) : fadeOutTime);
  }

  /// Pro, 2 decks: double-click a song (or drop it on the deck that isn't
  /// playing) to put it on that deck. It goes into the queue as the next
  /// song, so whatever was waiting there moves back to second, where it can
  /// stay or be taken off. With no song playing it loads on the live deck.
  Future<void> loadNext(List<Track> tracks, {List<int> queueIds = const []}) async {
    if (standby == null || !engine.playing) {
      return dropOnPlayer(SongDrag(tracks, queueIds: queueIds));
    }
    final up = upNext;
    final at = up == null ? queue.length : queue.indexOf(up);
    if (queueIds.isNotEmpty) {
      await db.queue.moveBlock(queueIds, at);
    } else {
      await db.queue.insertAll(tracks.map((t) => t.id), at: at);
    }
    await _reloadQueue();
    await _cueStandby();
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
    final next = upNext;
    if (autocue && engine.current == null && !_fading && next != null) {
      await _cue(next, autostart: false);
    }
    await _cueStandby();
  }

  /// The song that plays after the current one: the first in the queue not
  /// yet played. Played songs stay in the queue, marked played.
  QueueEntry? get upNext => queue.where((e) => !e.played && e.id != nowPlayingQueueId).firstOrNull;

  int get playedCount => queue.where((e) => e.played).length;

  /// Takes the played songs off the queue.
  Future<void> clearPlayed() async {
    await db.queue.clearPlayed();
    await _reloadQueue();
  }

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
    await _cueStandby();
  }

  /// Moves a waiting song one place up (or down) among the songs still to
  /// sing, for the stage view's arrows.
  Future<void> nudgeInQueue(QueueEntry e, {required bool up}) async {
    final waiting = [
      for (final q in queue)
        if (!q.played && q.id != nowPlayingQueueId) q,
    ];
    final i = waiting.indexWhere((q) => q.id == e.id);
    final j = up ? i - 1 : i + 1;
    if (i < 0 || j < 0 || j >= waiting.length) return;
    await moveInQueue(e, queue.indexWhere((q) => q.id == waiting[j].id));
  }

  Future<void> setSinger(QueueEntry e, String singer) async {
    await db.queue.setSinger(e.id, singer.trim().isEmpty ? null : singer.trim());
    await _reloadQueue();
  }

  Future<void> clearQueue() async {
    await db.queue.clear();
    queuePlaylistId = null;
    nowPlayingQueueId = null;
    await engine.stop();
    await _reloadQueue();
    await _cueStandby();
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
      final next = upNext;
      if (next != null) await playEntry(next);
      return;
    }
    await engine.playPause();
  }

  /// ⏭: the current song counts as sung, and the next one starts.
  Future<void> next({Duration? fadeIn}) async {
    await _finishCurrent();
    final up = upNext;
    if (up != null) {
      await _cue(up, autostart: true, fadeIn: fadeIn);
    } else {
      await engine.stop();
    }
  }

  /// ⏮: back to the start of the song.
  Future<void> previous() => engine.restart();

  Future<void> _cue(QueueEntry e, {required bool autostart, Duration? fadeIn, Duration? fadeOutOld}) async {
    if (standby != null) return _cueOnOtherDeck(e, autostart: autostart, fadeIn: fadeIn, fadeOutOld: fadeOutOld);
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

  /// 2-deck mode: the song (usually already waiting there) starts on the
  /// other deck, which becomes the live one. The old deck stops, or fades
  /// out over [fadeOutOld] while the new song comes in, and then takes the
  /// next song in the queue.
  Future<void> _cueOnOtherDeck(QueueEntry e, {required bool autostart, Duration? fadeIn, Duration? fadeOutOld}) async {
    await _standbyChain;
    final sb = standby!, old = engine;
    if (standbyQueueId != e.id || sb.current == null || _oldFading) {
      _oldFading = false;
      standbyQueueId = e.id;
      await sb.load(e.track, singer: e.singer, autostart: false, skipSilence: autocue || fadeIn != null);
    }
    _live = 1 - _live;
    standbyQueueId = null;
    nowPlayingQueueId = e.id;
    _endFade();
    await sb.matchLevel(old);
    notifyListeners();
    if (autostart) await sb.play(fadeIn: fadeIn);
    final song = old.current;
    if (song != null && fadeOutOld != null && old.playing) {
      _oldFading = true;
      unawaited(
        old.fadeOut(over: fadeOutOld).then((_) async {
          if (!_oldFading || identical(old, engine) || !identical(old.current, song)) return;
          _oldFading = false;
          await old.stop();
          await _cueStandby();
        }),
      );
      return;
    }
    if (song != null) await old.stop();
    await _cueStandby();
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
    final next = upNext;
    if (next == null) {
      await engine.stop();
      return;
    }
    if (mode == PlayMode.autoplay || crossfade) {
      await _cue(next, autostart: true, fadeIn: crossfade ? fadeInLength : null);
    } else if (autocue) {
      await _cue(next, autostart: false); // ready to go, paused
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
    _startCrossfade(left);
  }

  void _startCrossfade(Duration over) {
    if (standby != null && fadeOverlap) {
      // Two decks: the next song comes in on the other deck while this one
      // fades out, overlapping.
      _fading = true;
      () async {
        await _finishCurrent();
        final up = upNext;
        if (up == null) {
          _fading = false;
          return;
        }
        await _cue(up, autostart: true, fadeIn: fadeInLength, fadeOutOld: over);
      }();
      return;
    }
    _fading = true;
    final token = ++_fadeToken;
    final song = engine.current;
    // Pro fades all the way out; Basic dips to a third.
    engine.fadeOut(over: over, to: isPro ? 0 : fadeLevel).then((done) async {
      if (token != _fadeToken) return; // something else already moved on
      _fading = false;
      if (!identical(engine.current, song)) return;
      if (done) {
        await next(fadeIn: fadeInLength);
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
      await _cueStandby();
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

  /// The playlist last loaded into the queue, so the changes made to the
  /// set while singing can be saved back to it (EZTiger Pro).
  int? queuePlaylistId;
  Playlist? get queuePlaylist => playlists.where((p) => p.id == queuePlaylistId).firstOrNull;

  /// Adds a saved playlist's songs to the queue, and remembers it.
  Future<void> loadPlaylistIntoQueue(int playlistId) async {
    final p = playlists.where((p) => p.id == playlistId).firstOrNull;
    if (p == null) return;
    status = 'Added "${p.name}" to $theQueue';
    await enqueueAll(await db.playlists.tracks(playlistId));
    queuePlaylistId = playlistId;
    notifyListeners();
  }

  /// Pro: the playlist becomes the queue as it is now, sung songs and all,
  /// in the order on screen.
  Future<void> replacePlaylistWithQueue(int playlistId) async {
    final old = await db.playlists.tracks(playlistId);
    if (old.isNotEmpty) await db.playlists.removePositions(playlistId, List.generate(old.length, (i) => i));
    await db.playlists.addAll(playlistId, queue.map((e) => e.track.id));
    final p = playlists.where((p) => p.id == playlistId).firstOrNull;
    status = 'Saved $theQueue to "${p?.name ?? 'the playlist'}"';
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
    for (final (i, d) in decks.indexed) {
      d.removeListener(_deckListeners[i]);
    }
    super.dispose();
  }
}
