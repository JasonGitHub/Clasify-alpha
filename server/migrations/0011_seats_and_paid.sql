-- CLA-175 stage 1: split the beta seat from "paid" (release design doc, "Accounts: two facts").
-- seat: the account holds one of the CAP beta seats. Every account that is active today holds one.
-- paid_at: when Stripe said the account paid (set by the webhook and the Bought check, later PRs).
-- A paid account signs in with no seat. One account can hold both.
ALTER TABLE accounts ADD COLUMN seat INTEGER NOT NULL DEFAULT 0;
ALTER TABLE accounts ADD COLUMN paid_at INTEGER;
UPDATE accounts SET seat = 1 WHERE state = 'active';
