/// SQLite schema for the EZtiger library database.
///
/// Rules that matter (see README, "Decisions"):
///
/// * `playlist_tracks`, `queue` and `singer_history` reference `tracks(id)`
///   with `ON DELETE CASCADE`. Never write to `tracks` with
///   `INSERT OR REPLACE`: REPLACE deletes the old row first, which silently
///   wipes playlists and history. The scanner INSERTs new rows and UPDATEs
///   existing rows by id, so a track's id is stable for the life of its file.
/// * Columns starting `user_` hold Dean's own tag edits. The scanner never
///   writes them, so edits survive every rescan.
library;

const int schemaVersion = 1;

/// Bump when the filename parser or classification rules change. A scan that
/// sees a different value re-parses every track (as UPDATEs, ids unchanged).
const int parserVersion = 1;

const List<String> schemaStatements = [
  '''
CREATE TABLE meta (
  key   TEXT PRIMARY KEY,
  value TEXT NOT NULL
)''',
  '''
CREATE TABLE folders (
  id          INTEGER PRIMARY KEY,
  path        TEXT NOT NULL UNIQUE,
  parent_id   INTEGER REFERENCES folders(id) ON DELETE CASCADE,
  name        TEXT NOT NULL,
  -- 1 for folders Dean added to the library; rescans walk roots only.
  is_root     INTEGER NOT NULL DEFAULT 0,
  -- 0 when Dean has removed this folder from the searchable library.
  -- The scanner skips it and everything below it.
  included    INTEGER NOT NULL DEFAULT 1,
  -- Tracks directly in this folder, and in it plus all its subfolders.
  track_count INTEGER NOT NULL DEFAULT 0,
  total_count INTEGER NOT NULL DEFAULT 0
)''',
  'CREATE INDEX idx_folders_parent ON folders(parent_id)',
  '''
CREATE TABLE tracks (
  id             INTEGER PRIMARY KEY,
  folder_id      INTEGER NOT NULL REFERENCES folders(id) ON DELETE CASCADE,
  -- The playable file: .mp3 of a CDG pair, a video, an audio file or a .zip.
  path           TEXT NOT NULL UNIQUE,
  file_name      TEXT NOT NULL,
  -- cdg | cdg_zip | video | audio
  kind           TEXT NOT NULL,
  cdg_path       TEXT,
  lyrics_path    TEXT,
  lyrics_text    TEXT,
  has_stems      INTEGER NOT NULL DEFAULT 0,
  -- song | mix (long mix albums, slideshow videos and so on)
  category       TEXT NOT NULL DEFAULT 'song',
  size           INTEGER NOT NULL,
  mtime          INTEGER NOT NULL,
  -- Fingerprint of the companion files (cdg, lyrics, stems). Freshness is
  -- mtime AND pair_sig: dropping a .cdg beside an untouched .mp3 changes
  -- the track without changing the mp3's timestamp.
  pair_sig       TEXT NOT NULL,
  title          TEXT NOT NULL,
  artist         TEXT,
  version        TEXT,
  catalogue_code TEXT,
  -- Normalised artist|title, used to group copies of the same song.
  group_key      TEXT NOT NULL,
  user_title     TEXT,
  user_artist    TEXT,
  user_kind      TEXT,
  added_at       INTEGER NOT NULL
)''',
  'CREATE INDEX idx_tracks_folder ON tracks(folder_id)',
  'CREATE INDEX idx_tracks_type ON tracks(kind)',
  'CREATE INDEX idx_tracks_group ON tracks(group_key)',
  '''
CREATE TABLE playlists (
  id         INTEGER PRIMARY KEY,
  name       TEXT NOT NULL UNIQUE,
  created_at INTEGER NOT NULL
)''',
  '''
CREATE TABLE playlist_tracks (
  playlist_id INTEGER NOT NULL REFERENCES playlists(id) ON DELETE CASCADE,
  track_id    INTEGER NOT NULL REFERENCES tracks(id) ON DELETE CASCADE,
  position    INTEGER NOT NULL,
  PRIMARY KEY (playlist_id, position)
)''',
  'CREATE INDEX idx_playlist_tracks_track ON playlist_tracks(track_id)',
  '''
CREATE TABLE queue (
  id        INTEGER PRIMARY KEY,
  track_id  INTEGER NOT NULL REFERENCES tracks(id) ON DELETE CASCADE,
  singer    TEXT,
  position  INTEGER NOT NULL
)''',
  '''
CREATE TABLE singer_history (
  id        INTEGER PRIMARY KEY,
  track_id  INTEGER NOT NULL REFERENCES tracks(id) ON DELETE CASCADE,
  singer    TEXT,
  sung_at   INTEGER NOT NULL
)''',
  'CREATE INDEX idx_history_sung_at ON singer_history(sung_at)',
];

/// Full-text index. A standalone FTS5 table keyed by track id, holding
/// normalised text. It is rebuilt once at the end of a scan that changed
/// something (not maintained by triggers), and patched row by row when Dean
/// edits a track's tags.
const String ftsStatement = '''
CREATE VIRTUAL TABLE tracks_fts USING fts5(
  title, artist, version, folder, file, lyrics,
  tokenize = 'unicode61 remove_diacritics 2'
)''';
