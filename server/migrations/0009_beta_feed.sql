-- CLA-172: the newest beta from the feed (dl.getmypod.app/beta/latest.json), kept here so the beta
-- page needs one D1 read and no outside fetch. One row. The hourly cron and a page visit that finds
-- it older than 2 minutes refresh it in the background.
CREATE TABLE beta_feed (
  id INTEGER PRIMARY KEY CHECK (id = 1),
  build INTEGER,
  url TEXT,
  checked_at INTEGER NOT NULL
);
