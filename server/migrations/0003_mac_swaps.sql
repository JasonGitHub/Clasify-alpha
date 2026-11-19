-- CLA-133: a 3rd Mac that confirms turns off the account's least used active Mac.
-- last_seen_at: the Mac's last /v1/status, /v1/open or confirm. NULL: not seen since this migration.
ALTER TABLE macs ADD COLUMN last_seen_at INTEGER;
-- One row per swap, for the limit of SWAPS swaps in SWAP_DAYS days per account. No device or email.
CREATE TABLE swaps (
  id TEXT PRIMARY KEY,
  account_id TEXT NOT NULL REFERENCES accounts(id),
  at INTEGER NOT NULL
);
CREATE INDEX swaps_account ON swaps(account_id, at);
