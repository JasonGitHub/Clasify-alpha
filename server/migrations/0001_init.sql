-- Activation (CLA-128). Device IDs, page codes and mail tokens are stored only as SHA-256 hashes.
CREATE TABLE accounts (
  id TEXT PRIMARY KEY,
  email TEXT NOT NULL UNIQUE,
  state TEXT NOT NULL CHECK (state IN ('pending', 'active', 'waitlist')),
  off INTEGER NOT NULL DEFAULT 0,
  created_at INTEGER NOT NULL,
  confirmed_at INTEGER
);

CREATE TABLE macs (
  device_hash TEXT PRIMARY KEY,
  account_id TEXT REFERENCES accounts(id),
  state TEXT NOT NULL CHECK (state IN ('waiting', 'active')),
  mails INTEGER NOT NULL DEFAULT 0,
  code_hash TEXT UNIQUE,
  code_expires_at INTEGER,
  created_at INTEGER NOT NULL
);
CREATE INDEX macs_account ON macs(account_id);

CREATE TABLE mails (
  token_hash TEXT PRIMARY KEY,
  device_hash TEXT NOT NULL REFERENCES macs(device_hash),
  account_id TEXT NOT NULL REFERENCES accounts(id),
  sent_at INTEGER NOT NULL,
  expires_at INTEGER NOT NULL,
  used_at INTEGER
);
