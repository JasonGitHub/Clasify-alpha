-- CLA-166: one row per problem report, only for the limit of 5 reports a day per account.
-- No text, no device, no email: the report itself goes out by mail and is not kept.
CREATE TABLE reports (
  id TEXT PRIMARY KEY,
  account_id TEXT NOT NULL REFERENCES accounts(id),
  at INTEGER NOT NULL
);
CREATE INDEX reports_account ON reports(account_id, at);
