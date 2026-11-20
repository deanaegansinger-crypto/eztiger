-- The online request list (worker.js makes these itself the first time; this
-- is for reference). Same columns as request-list.csv, plus T: whose list
-- ('' for the owner's, else the DJ's id from tenants).
CREATE TABLE IF NOT EXISTS requests (
  Id TEXT PRIMARY KEY, At TEXT, Time TEXT, Singer TEXT, Title TEXT, Artist TEXT, Version TEXT, Disc TEXT,
  Others TEXT, Note TEXT, Status TEXT, Pos INTEGER, Closed TEXT, Brand TEXT, Code TEXT, File TEXT, Path TEXT, Sent TEXT,
  T TEXT NOT NULL DEFAULT ''
);
-- "Clear whole list" keeps a copy here, with when it was cleared.
CREATE TABLE IF NOT EXISTS cleared (
  ClearedAt TEXT, Id TEXT, At TEXT, Time TEXT, Singer TEXT, Title TEXT, Artist TEXT, Version TEXT, Disc TEXT,
  Others TEXT, Note TEXT, Status TEXT, Pos INTEGER, Closed TEXT, Brand TEXT, Code TEXT, File TEXT, Path TEXT, Sent TEXT,
  T TEXT NOT NULL DEFAULT ''
);
-- Per DJ: closed, name, tz (minutes from UTC), app (when EZTiger last asked), phone.
CREATE TABLE IF NOT EXISTS meta2 (T TEXT NOT NULL, k TEXT NOT NULL, v TEXT, PRIMARY KEY (T, k));
-- The DJs who signed up from EZTiger (POST /register): their id and DJ code.
CREATE TABLE IF NOT EXISTS tenants (id TEXT PRIMARY KEY, key TEXT NOT NULL, name TEXT, created INTEGER, ip TEXT);
CREATE INDEX IF NOT EXISTS requests_t ON requests (T, Status);
