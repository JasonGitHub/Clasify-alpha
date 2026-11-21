-- CLA-172: the beta page's limits. One row per try, with only a SHA-256 of the email, never the
-- email itself. Rows older than 2 days are deleted at the next try.
CREATE TABLE page_tries (
  kind TEXT NOT NULL CHECK (kind IN ('wait', 'link')),
  key_hash TEXT NOT NULL,
  at INTEGER NOT NULL
);
CREATE INDEX page_tries_key ON page_tries(kind, key_hash, at);
CREATE INDEX page_tries_at ON page_tries(kind, at);
