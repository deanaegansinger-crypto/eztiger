-- Once, on a database made before many DJs could share the Worker (20 Nov 2026):
-- every row so far is the owner's list (T = '').
ALTER TABLE requests ADD COLUMN T TEXT NOT NULL DEFAULT '';
ALTER TABLE cleared ADD COLUMN T TEXT NOT NULL DEFAULT '';
CREATE TABLE IF NOT EXISTS meta2 (T TEXT NOT NULL, k TEXT NOT NULL, v TEXT, PRIMARY KEY (T, k));
INSERT OR IGNORE INTO meta2 (T, k, v) SELECT '', k, v FROM meta;
CREATE TABLE IF NOT EXISTS tenants (id TEXT PRIMARY KEY, key TEXT NOT NULL, name TEXT, created INTEGER, ip TEXT);
CREATE INDEX IF NOT EXISTS requests_t ON requests (T, Status);
