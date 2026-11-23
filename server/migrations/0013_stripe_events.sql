-- CLA-175 stage 1: Stripe's signed messages (release design doc, "Taking a payment message").
-- Each message ID is used once. Rows older than 30 days are deleted by the hourly run.
CREATE TABLE stripe_events (
  id TEXT PRIMARY KEY,
  at INTEGER NOT NULL
);
CREATE INDEX stripe_events_at ON stripe_events(at);
-- When the "myPod is yours" mail went out for this payment. NULL: not yet (or the send failed).
ALTER TABLE payments ADD COLUMN mailed_at INTEGER;
