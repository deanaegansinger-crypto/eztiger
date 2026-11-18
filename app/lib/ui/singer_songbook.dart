import 'package:eztiger_core/eztiger_core.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../app_state.dart';
import '../edition.dart';
import '../theme.dart';
import 'common.dart';
import 'rack.dart' show TypeChip;

/// How the songbook groups the songs.
enum SongbookBy { artist, folder, title }

/// The singer's songbook (the Android app): every song on the tablet, once
/// each, grouped by artist, by folder (genres, sets) or A–Z by title, with a
/// look-up box and an A–Z strip down the side. Tap a song to add it to the
/// bottom of Tonight's playlist; press and hold to make it the next song.
/// It takes the lyrics' place, and closes itself when a song starts playing.
class SingerSongbook extends StatefulWidget {
  const SingerSongbook({super.key});

  @override
  State<SingerSongbook> createState() => _SingerSongbookState();
}

typedef _Row = ({String? head, int count, SearchGroup? song});

class _SingerSongbookState extends State<SingerSongbook> {
  static const _headH = 36.0, _songH = 52.0;
  final _scroll = ScrollController();
  final _find = TextEditingController();
  List<SearchGroup> _songs = [];
  bool _loading = true;
  SongbookBy _by = SongbookBy.artist;
  AppState? _s;
  bool _wasPlaying = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final s = AppScope.of(context);
    if (_s != s) {
      _s?.engine.removeListener(_onEngine);
      _s = s;
      _wasPlaying = s.engine.playing;
      s.engine.addListener(_onEngine);
      _load();
    }
  }

  @override
  void dispose() {
    _s?.engine.removeListener(_onEngine);
    _scroll.dispose();
    _find.dispose();
    super.dispose();
  }

  // A song starting: the songbook steps aside for the lyrics.
  void _onEngine() {
    final playing = _s!.engine.playing;
    if (playing && !_wasPlaying) _s!.setSingerSongbook(false);
    _wasPlaying = playing;
  }

  Future<void> _load() async {
    final groups = await _s!.db.search.search('', limit: 100000, sort: SearchSort.artist);
    if (!mounted) return;
    setState(() {
      _songs = groups;
      _loading = false;
    });
  }

  static String _fold(String s) => s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9 ]+'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();

  /// The name a song is filed under: the artist without a leading "The",
  /// its folder, or its title.
  String _groupOf(SearchGroup g) {
    final t = g.primary;
    return switch (_by) {
      SongbookBy.artist => (t.artist ?? '').trim().isEmpty ? 'Unknown artist' : t.artist!.trim(),
      SongbookBy.folder => t.folderPath == null ? 'Songs' : p.basename(t.folderPath!),
      SongbookBy.title => t.title,
    };
  }

  String _sortKey(String s) => _fold(s).replaceFirst(RegExp(r'^the (?=.)'), '');

  String _letter(String s) {
    final k = _sortKey(s);
    if (k.isEmpty) return '#';
    final c = k[0].toUpperCase();
    return RegExp('[A-Z]').hasMatch(c) ? c : '#';
  }

  List<_Row> _rows() {
    final q = _fold(_find.text);
    final words = q.isEmpty ? const <String>[] : q.split(' ');
    final shown = [
      for (final g in _songs)
        if (words.isEmpty || words.every('${_fold(g.primary.title)} ${_fold(g.primary.artist ?? '')} ${_fold(p.basename(g.primary.folderPath ?? ''))}'.contains))
          g,
    ];
    int byTitle(SearchGroup a, SearchGroup b) => _sortKey(a.primary.title).compareTo(_sortKey(b.primary.title));
    if (_by == SongbookBy.title) {
      shown.sort(byTitle);
      // A–Z by title: a heading for each letter.
      final rows = <_Row>[];
      String? last;
      for (final g in shown) {
        final l = _letter(g.primary.title);
        if (l != last) {
          rows.add((head: l, count: shown.where((x) => _letter(x.primary.title) == l).length, song: null));
          last = l;
        }
        rows.add((head: null, count: 0, song: g));
      }
      return rows;
    }
    final groups = <String, List<SearchGroup>>{};
    for (final g in shown) {
      groups.putIfAbsent(_groupOf(g), () => []).add(g);
    }
    final names = groups.keys.toList()..sort((a, b) => _sortKey(a).compareTo(_sortKey(b)));
    return [
      for (final n in names) ...[
        (head: n, count: groups[n]!.length, song: null),
        for (final g in groups[n]!..sort(byTitle)) (head: null, count: 0, song: g),
      ],
    ];
  }

  void _jumpTo(List<_Row> rows, String letter) {
    var y = 0.0;
    for (final r in rows) {
      if (r.head != null && _letter(r.head!) == letter) break;
      if (r.song != null && _by == SongbookBy.title && _letter(r.song!.primary.title) == letter) break;
      y += r.head != null ? _headH : _songH;
    }
    if (_scroll.hasClients) _scroll.jumpTo(y.clamp(0, _scroll.position.maxScrollExtent));
  }

  Future<void> _add(SearchGroup g, {bool next = false}) async {
    final s = _s!;
    final t = g.primary;
    next ? await s.enqueueNext([t]) : await s.enqueue(t);
    if (!mounted) return;
    ScaffoldMessenger.maybeOf(context)
      ?..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        key: const Key('songbook-added'),
        duration: const Duration(seconds: 2),
        content: Text(next ? '${t.title}: next in $theQueue' : '${t.title}: added to $theQueue'),
      ));
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final rows = _loading ? const <_Row>[] : _rows();
    final waiting = {for (final e in s.queue) if (e.playedAt == null) e.track.id};
    final letters = {for (final r in rows) if (r.head != null) _letter(r.head!)}.toList()..sort((a, b) => a == '#' ? 1 : b == '#' ? -1 : a.compareTo(b));
    final songCount = rows.where((r) => r.song != null).length;
    return Material(
      key: const Key('singer-songbook'),
      elevation: 12,
      color: context.ez.panel,
      borderRadius: BorderRadius.circular(10),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            color: context.ez.raised,
            padding: const EdgeInsets.fromLTRB(12, 6, 4, 6),
            child: Row(
              children: [
                HeadText('📖 Songbook', color: EzColors.brass),
                const SizedBox(width: 8),
                Text('$songCount ${songCount == 1 ? 'song' : 'songs'}', style: TextStyle(fontSize: 12, color: context.ez.textDim)),
                const Spacer(),
                Segmented<SongbookBy>(
                  key: const Key('songbook-by'),
                  options: const {SongbookBy.artist: 'Artist', SongbookBy.folder: 'Folder', SongbookBy.title: 'A–Z'},
                  value: _by,
                  onChanged: (v) => setState(() {
                    _by = v;
                    if (_scroll.hasClients) _scroll.jumpTo(0);
                  }),
                ),
                IconButton(
                  key: const Key('songbook-close'),
                  tooltip: 'Close the songbook (back to the lyrics)',
                  icon: const Icon(Icons.close),
                  onPressed: () => s.setSingerSongbook(false),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 4),
            child: TextField(
              key: const Key('songbook-find'),
              controller: _find,
              onChanged: (_) => setState(() {}),
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                isDense: true,
                prefixIcon: const Icon(Icons.search),
                hintText: 'Look up a song, artist or folder…',
                suffixIcon: _find.text.isEmpty
                    ? null
                    : IconButton(icon: const Icon(Icons.clear), onPressed: () => setState(_find.clear)),
              ),
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : rows.isEmpty
                ? Center(child: Text(_songs.isEmpty ? 'Add a folder of songs first (Library tab).' : 'Nothing matches.', style: TextStyle(color: context.ez.textDim)))
                : Row(
                    children: [
                      Expanded(
                        child: ListView.builder(
                          controller: _scroll,
                          itemCount: rows.length,
                          itemExtentBuilder: (i, _) => i >= rows.length ? null : (rows[i].head != null ? _headH : _songH),
                          itemBuilder: (context, i) {
                            final r = rows[i];
                            if (r.head != null) {
                              return Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12),
                                alignment: Alignment.centerLeft,
                                color: context.ez.raised.withValues(alpha: 0.6),
                                child: Text(
                                  '${r.head}  ·  ${r.count}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: EzColors.brass),
                                ),
                              );
                            }
                            final g = r.song!, t = g.primary, inList = waiting.contains(t.id);
                            final sub = _by == SongbookBy.artist ? p.basename(t.folderPath ?? '') : (t.artist ?? '');
                            return InkWell(
                              key: Key('songbook-song-${t.id}'),
                              onTap: () => _add(g),
                              onLongPress: () => _add(g, next: true),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 12),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Column(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(t.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                                          if (sub.isNotEmpty)
                                            Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: context.ez.textDim)),
                                        ],
                                      ),
                                    ),
                                    if (g.versions.length > 1)
                                      Padding(
                                        padding: const EdgeInsets.only(right: 8),
                                        child: Text('×${g.versions.length}', style: TextStyle(fontSize: 12, color: EzColors.cyan)),
                                      ),
                                    TypeChip(t.type),
                                    const SizedBox(width: 8),
                                    Icon(inList ? Icons.check_circle : Icons.add_circle_outline,
                                        size: 26, color: inList ? EzColors.green : EzColors.brass),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                      // A–Z strip: tap (or slide a finger down) to jump.
                      if (letters.length > 1)
                        LayoutBuilder(
                          builder: (context, c) {
                            void at(double y) {
                              final i = (y / c.maxHeight * letters.length).floor().clamp(0, letters.length - 1);
                              _jumpTo(rows, letters[i]);
                            }

                            return GestureDetector(
                              key: const Key('songbook-letters'),
                              onTapDown: (d) => at(d.localPosition.dy),
                              onVerticalDragUpdate: (d) => at(d.localPosition.dy),
                              child: Container(
                                width: 30,
                                color: Colors.transparent,
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                                  children: [
                                    for (final l in letters)
                                      Flexible(
                                        child: Text(l, key: Key('songbook-letter-$l'), style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: EzColors.cyan)),
                                      ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}
