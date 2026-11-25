-- CLA-193: short links (Jason OK 22:25 and 22:27 JST 11-25): getmypod.app/r/<name> for any Reddit
-- name (key "r/<name>") and getmypod.app/<word> for a fixed list of words (key "<word>"). At most
-- 500 different keys (src/links.ts); past that, new keys are not counted.
-- How many networks opened each short link (once a day per network, as invite_opens).
CREATE TABLE link_opens (
  link TEXT PRIMARY KEY,
  count INTEGER NOT NULL DEFAULT 0
);
-- How many networks that came by a short link pressed Download, per key and UTC day. Only for a
-- key that has an open counted.
CREATE TABLE link_downloads (
  link TEXT NOT NULL,
  day TEXT NOT NULL,
  count INTEGER NOT NULL DEFAULT 0,
  PRIMARY KEY (link, day)
);
-- One open and one Download a day per key per network: only a SHA-256 of the network with that
-- day's random salt (vote_salts), as invite_tries. Rows older than 2 days are deleted at the next count.
CREATE TABLE link_tries (
  net_hash TEXT NOT NULL,
  link TEXT NOT NULL,
  kind TEXT NOT NULL,
  day TEXT NOT NULL,
  -- 1 when this open made a new key. One network makes at most 3 new keys a day (src/links.ts).
  new INTEGER NOT NULL DEFAULT 0,
  PRIMARY KEY (net_hash, link, kind, day)
);
