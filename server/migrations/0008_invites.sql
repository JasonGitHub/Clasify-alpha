-- CLA-172: when the open-spot mail went to a waitlist account. An invite is open for 7 days.
ALTER TABLE accounts ADD COLUMN invited_at INTEGER;
