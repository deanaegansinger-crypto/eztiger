-- The online request list (worker.js). Same columns as request-list.csv.
CREATE TABLE IF NOT EXISTS requests (
  Id TEXT PRIMARY KEY, At TEXT, Time TEXT, Singer TEXT, Title TEXT, Artist TEXT, Version TEXT, Disc TEXT,
  Others TEXT, Note TEXT, Status TEXT, Pos INTEGER, Closed TEXT, Brand TEXT, Code TEXT, File TEXT, Path TEXT, Sent TEXT
);
-- "Clear whole list" keeps a copy here, with when it was cleared.
CREATE TABLE IF NOT EXISTS cleared (
  ClearedAt TEXT, Id TEXT, At TEXT, Time TEXT, Singer TEXT, Title TEXT, Artist TEXT, Version TEXT, Disc TEXT,
  Others TEXT, Note TEXT, Status TEXT, Pos INTEGER, Closed TEXT, Brand TEXT, Code TEXT, File TEXT, Path TEXT, Sent TEXT
);
-- closed, name, tz (minutes from UTC), app (when EZTiger last asked), phone.
CREATE TABLE IF NOT EXISTS meta (k TEXT PRIMARY KEY, v TEXT);
