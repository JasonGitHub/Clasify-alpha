-- CLA-175 stage 1: payments through Stripe Checkout (release design doc, "What we store").
-- One row per paid Checkout session. Stripe's IDs, the amount, the currency, the state and the time.
-- No card data and no address: Stripe keeps those.
CREATE TABLE payments (
  session_id TEXT PRIMARY KEY,
  payment_intent TEXT UNIQUE,
  account_id TEXT NOT NULL REFERENCES accounts(id),
  amount INTEGER NOT NULL,
  currency TEXT NOT NULL,
  state TEXT NOT NULL CHECK (state IN ('paid', 'refunded', 'disputed')),
  at INTEGER NOT NULL
);
CREATE INDEX payments_account ON payments(account_id);

-- The "thank you" page's checks: one row per try, with a SHA-256 of the network, never the address.
-- Rows older than 1 day are deleted at the next try.
CREATE TABLE bought_tries (
  net_hash TEXT NOT NULL,
  at INTEGER NOT NULL
);
CREATE INDEX bought_tries_net ON bought_tries(net_hash, at);
