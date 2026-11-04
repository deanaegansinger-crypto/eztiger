# eztiger_core

The library scanner and song database behind **EZtiger by Deano**, the karaoke and
backing-track search app. Pure Dart with no Flutter dependency. The Flutter app
(Phase 3) depends on this package and doesn't need to change anything in it.

It codes against the `sqflite_common` interfaces and takes an injected
`DatabaseFactory`, so the same code runs on Windows (`databaseFactoryFfi`),
Android (the sqflite plugin's `databaseFactory`) and from the command line.

> Rebuilt on 2026-11-04 from the Phase 1 design notes after the original
> `eztiger-phase1.zip` went missing. Unlike the original, this version was
> compiled and tested with a real Dart SDK (3.13.7): `dart analyze` is clean
> and all 61 tests pass.

## Quick start

You need the Dart SDK (https://dart.dev/get-dart). Then, in this folder:

```
dart pub get
dart test
```

Index Dean's library and search it from the command line:

```
dart run eztiger_core:scan --db eztiger.db --add "C:\Users\deane\Desktop\backing 2024 april"
dart run eztiger_core:scan --db eztiger.db --search "sweet caroline" --search "trinity night"
dart run eztiger_core:scan --db eztiger.db --report tracks.tsv
```

Running it again without `--add` rescans every library folder. `--report` writes
every track with what the parser made of its name, so you can check it by eye.

## Using it from the app

```dart
final db = await EztigerDatabase.open(databaseFactoryFfi, 'eztiger.db');
await LibraryScanner(db).addAndScan(r'C:\Users\deane\Desktop\backing 2024 april');

final results = await db.search.search('cant help faling');   // spelling is corrected
for (final song in results) {
  final t = song.primary;               // best copy; song.versions has the rest
  print('${t.type.label}  ${t.title} — ${t.artist}  ${t.path}');
}

await db.queue.add(t.id, singer: 'Dave M.');
await db.tracks.editTags(t.id, title: 'Sweet Caroline', artist: 'Neil Diamond', type: TrackType.cdg);
```

What the mockup needs, and where it lives:

| Mockup | API |
|---|---|
| Folder tree with counts | `db.folders.roots()`, `children(id)`, `Folder.totalCount` |
| "Add to / remove from searchable library" | `db.folders.addRoot(path)`, `setIncluded(id, bool)` |
| Search box, Title / Artist / Type / Location | `db.search.search(text, folderId:, type:)` → `SearchGroup`s |
| Type column (CDG / MP4 / MP3) | `Track.type` (CDG pairs and zipped MP3+G show as CDG) |
| Edit tags | `db.tracks.editTags(id, title:, artist:, type:)` |
| Queue with singer names | `db.queue.add / all / move / remove / markSung` |
| Playlists, "drag the queue onto a folder" | `db.playlists.create / add / move / removeAt / addQueue` |
| History | `db.history.recent(singer:)`, filled by `queue.markSung` |
| Lyric sheet beside a track | `Track.lyricsPath`, `db.tracks.lyrics(id)` |

## Layout

```
lib/eztiger_core.dart          public API
lib/src/data/schema.dart       tables and the FTS5 index
lib/src/data/database.dart     open/create, injected DatabaseFactory
lib/src/data/daos.dart         folders, tracks, playlists, queue, history
lib/src/data/search.dart       search, grouping, spelling correction, index rebuild
lib/src/data/models.dart       Track, Folder, SearchGroup, ...
lib/src/scanner/folder_walker.dart     lazy directory walk, no DB dependency
lib/src/scanner/filename_parser.dart   file name -> title, artist, version
lib/src/scanner/library_scanner.dart   pairing, sidecars, incremental writes
lib/src/text.dart              normalising text for matching
bin/scan.dart                  command-line harness
test/                          61 tests
```

## What gets indexed

- **Karaoke:** `.mp3` + `.cdg` pairs, paired case-insensitively (`Reason To Believe.CDG`
  + `.MP3`). Also `.zip` files holding MP3+G; the player unzips them when played. A zip
  sitting next to an extracted copy of itself is skipped.
- **Video:** `.mp4 .avi .mpg .mpeg .mkv .mov .wmv .m4v .webm`.
- **Backing only:** `.mp3 .wav .wma .m4a .flac .ogg .aac`.
- **Attached, not indexed as tracks:** `.txt` lyric sheets (same name, `lyrics <name>`,
  `<name> lyrics`, or in a `... lyrics` folder next to the track; their text is
  searchable), and VirtualDJ `.vdjstems` (shown as "stems available").
- **Ignored:** images, `Thumbs.db`, `desktop.ini`, `.pk .svp .scn .dat .dmsm .tmp .lnk .nfo .rtf .pdf .xlr`.
- Orphaned `.cdg` files are listed in the scan report.
- Very large audio and video files (mix albums, the 3.3 GB slideshow) are tagged
  `category = 'mix'`, not hidden.

## Search

Searches title, artist, Dean's version notes, catalogue code, folder names (they are
his set lists and shows), file names and lyric sheets. It ignores case, accents,
apostrophes and `&` vs `and`; every word matches as a prefix while typing (numbers
match exactly, so `down 2` doesn't match `2000`); a word that matches nothing is
corrected to the closest word in the library (`faling`, `Trintry`); and if no song
has every word, it falls back to any word, best match first. Copies of the same song
in different folders come back as one result with the copies under it.

If the SQLite build has no FTS5, search falls back to plain `LIKE` matching
(without accent folding or spelling correction).

## Decisions that should not be quietly reverted

**Never `INSERT OR REPLACE` into `tracks`.** `playlist_tracks`, `queue` and
`singer_history` reference `tracks(id)` with `ON DELETE CASCADE`. REPLACE deletes the
old row first, so the obvious implementation silently wipes playlists and history on
every rescan of a changed file. New rows are INSERTed, existing rows UPDATEd by id;
track ids are stable for the life of the file. Guarded by a test.

**Freshness = mtime AND pairing.** Dropping a `.cdg` beside an untouched `.mp3`
changes the track type without changing the mp3's timestamp. `pair_sig` fingerprints
the CDG, lyric sheet, stems and parser version, and a track is fresh only if size,
mtime and `pair_sig` all match. Tested in both directions.

**A missing root changes nothing.** If a library folder isn't there (an unplugged
drive), the scan stops for that folder without deleting anything, because deleting
its tracks would empty every playlist that uses them. Folders that can't be read,
and folders Dean has taken out of the library, are protected the same way.

**Dean's tag edits live in `user_*` columns.** The scanner never writes them, so
edits survive every rescan, including rescans of a changed file.

**Filename parser is conservative on purpose.** A stripping rule only applies if a
separator survives it, which is what stops `Blink 182 - All The Small Things` losing
its artist to the catalogue-code rule. `AC-DC`, `Jay-Z`, `UB40`, `10cc`, `9 to 5`
are covered. Dean's performance notes (`down 2`, `Two Semitones Down`, `in G`,
`extended`, `with bv`, `clean ending`...) are kept as a searchable version, never
thrown away.

**`A - B` names are settled by the whole library.** Both `Artist - Title` and
`Title - Artist` are common, often within one disc series. Clues are used first
(`Surname, First`, a Zoom Karaoke prefix, the folder name, a matching lyric sheet);
otherwise a part that appears with clearly more different partners across the library
(at least two more) is taken as the artist. With no evidence it stays `Artist - Title`.
Anything still wrong can be fixed with Edit tags.

**Walk is a lazy sync generator with no DB dependency**, so moving it into an Isolate
in Phase 3 is a small change.

**The FTS index is rebuilt once per scan, not maintained by triggers,** and skipped
entirely when a scan changed nothing. Tag edits patch their one row straight away.

## Schema notes

Compared with the original `schema.sql`: `folders.is_root` (rescans walk roots only),
`folders.included` (the "searchable library" toggle), `folders.total_count`,
`tracks.user_title / user_artist / user_kind`, `tracks.pair_sig`, `tracks.group_key`,
`tracks.lyrics_path / lyrics_text`, `tracks.has_stems`, `tracks.category`; indexes
`idx_folders_parent`, `idx_tracks_type`, `idx_tracks_group`.

## Checked against the real library

The scanner was run on a mirror of the real folder built from a listing of Dean's PC
on 2026-11-04 (4,605 of roughly 5,500 files, with the real names, sizes and dates;
the listing tool stops at 2,000 entries per folder, so parts of `motown show` and
`backings 2` were missing). Result: 3,326 tracks in 182 folders, 642 CDG pairs,
261 videos, 28 with stems, 35 with lyric sheets, 5 orphaned CDGs. Cold scan 1.9 s,
rescan with nothing changed 0.7 s with zero writes. Linux, warm cache, so expect the
Windows walk to be slower; the real number comes from the first run on Dean's PC.

Known rough edges, all fixable with Edit tags: about 1,200 files have no artist in
their name at all (`sweet caroline.mp3`), names with no separator stay whole
(`BROTHERS_IN_ARMS_DIRE_STRAITS`), and a few YouTube-style `Title - Artist` names
with no other evidence come out the wrong way round.

## Next

Phase 2, playback. The CDG decoder is the one genuinely unknown piece: prototype it on
its own (a window rendering a `.cdg` against a playing `.mp3`, nothing else) before
wiring it into the app. Video tracks need a video player path too, not just CDG.
