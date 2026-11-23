-- CLA-172: invite links, getmypod.app/beta?invite=<id> (Jason OK 20:29 JST 11-23).
-- How many networks opened the beta page with each invite id. At most 500 ids (src/invitelinks.ts).
CREATE TABLE invite_opens (
  id TEXT PRIMARY KEY,
  count INTEGER NOT NULL DEFAULT 0
);
-- One open per id a day per network: only a SHA-256 of the network with that day's random salt
-- (the votes' salt, vote_salts). Rows older than 2 days are deleted at the next open.
CREATE TABLE invite_tries (
  net_hash TEXT NOT NULL,
  id TEXT NOT NULL,
  day TEXT NOT NULL,
  PRIMARY KEY (net_hash, id, day)
);
-- The invite id a waitlist account joined with. Set when the account is made, never changed.
ALTER TABLE accounts ADD COLUMN invite_id TEXT;
