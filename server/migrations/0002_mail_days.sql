-- Link mails per day (UTC, the Resend day): sent, refused at the day limit, and failed at Resend.
-- The first refusal and the first failure of a day each send one alert.
CREATE TABLE mail_days (
  day TEXT PRIMARY KEY,
  sent INTEGER NOT NULL DEFAULT 0,
  refused INTEGER NOT NULL DEFAULT 0,
  failed INTEGER NOT NULL DEFAULT 0
);
