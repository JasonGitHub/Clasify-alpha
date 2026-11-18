-- Link mails sent and refused per day (UTC, the Resend day), for the day limit and the one alert.
CREATE TABLE mail_days (
  day TEXT PRIMARY KEY,
  sent INTEGER NOT NULL DEFAULT 0,
  refused INTEGER NOT NULL DEFAULT 0
);
