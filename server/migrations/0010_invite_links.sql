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
-- "Email me the link" with an invite id (Jason picked B, 20:50 JST 11-23): a keyed hash of the email
-- (HMAC-SHA256 with the TURNSTILE_SECRET Worker secret) and the id, for 30 days. When that email's
-- account activates, the id goes to the account (set once) and the row is deleted. The hourly cron
-- deletes rows older than 30 days. Nothing else is kept.
CREATE TABLE invite_mails (
  email_hash TEXT PRIMARY KEY,
  id TEXT NOT NULL,
  at INTEGER NOT NULL
);
