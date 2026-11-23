-- CLA-175 stage 1: Stripe's signed messages (release design doc, "Taking a payment message").
-- Each message ID is used once. Rows older than 30 days are deleted by the hourly run.
CREATE TABLE stripe_events (
  id TEXT PRIMARY KEY,
  at INTEGER NOT NULL
);
CREATE INDEX stripe_events_at ON stripe_events(at);
-- The "myPod is yours" mail: mailing_at while one message sends it, mailed_at once it went out.
ALTER TABLE payments ADD COLUMN mailing_at INTEGER;
ALTER TABLE payments ADD COLUMN mailed_at INTEGER;
-- A full refund or a dispute that arrives before its payment is stored. Stripe does not keep the
-- order of its messages, so the payment is stored with this state. Only Stripe's payment ID is
-- kept, also for other projects' payments, and rows older than 30 days are deleted.
CREATE TABLE reversals (
  payment_intent TEXT PRIMARY KEY,
  state TEXT NOT NULL CHECK (state IN ('paid', 'refunded', 'disputed')),
  at INTEGER NOT NULL
);
