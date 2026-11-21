-- CLA-172: the beta page's "What next?" votes. A count per item, nothing about who.
CREATE TABLE votes (
  item TEXT PRIMARY KEY,
  count INTEGER NOT NULL DEFAULT 0
);
-- One vote per item a day per network: only a SHA-256 of the IP with that day's random salt.
-- Rows and salts older than 2 days are deleted at the next vote, so old hashes cannot be checked.
CREATE TABLE vote_tries (
  net_hash TEXT NOT NULL,
  item TEXT NOT NULL,
  day TEXT NOT NULL,
  PRIMARY KEY (net_hash, item, day)
);
CREATE TABLE vote_salts (
  day TEXT PRIMARY KEY,
  salt TEXT NOT NULL
);
