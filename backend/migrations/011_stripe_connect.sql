-- ══════════════════════════════════════════════════════════════
-- VENDRA: Migration 011 — Stripe as a payment provider
-- With PAYMENT_PROVIDER=stripe, card payments go through Stripe and
-- withdrawals become Stripe Connect transfers: each wallet owner sets up a
-- Stripe Express account once, and a withdrawal moves money from the
-- platform's Stripe balance to it. Transfers are in the platform's own
-- currency, so the converted amount is kept next to the rupee amount.
-- ══════════════════════════════════════════════════════════════

ALTER TABLE users ADD COLUMN IF NOT EXISTS stripe_account_id VARCHAR(64) UNIQUE;
ALTER TABLE users ADD COLUMN IF NOT EXISTS stripe_payouts_enabled BOOLEAN NOT NULL DEFAULT false;
ALTER TABLE users ADD COLUMN IF NOT EXISTS stripe_details_submitted BOOLEAN NOT NULL DEFAULT false;

-- Which gateway handled a payment / withdrawal (rows from before are Vendra Pay)
ALTER TABLE payments ADD COLUMN IF NOT EXISTS provider VARCHAR(12) NOT NULL DEFAULT 'vendrapay';
ALTER TABLE withdrawals ADD COLUMN IF NOT EXISTS provider VARCHAR(12) NOT NULL DEFAULT 'vendrapay';

-- Stripe transfers: the connected account, and the amount in the platform's currency (minor units)
ALTER TABLE withdrawals ADD COLUMN IF NOT EXISTS destination_account VARCHAR(64);
ALTER TABLE withdrawals ADD COLUMN IF NOT EXISTS gateway_amount BIGINT;
ALTER TABLE withdrawals ADD COLUMN IF NOT EXISTS gateway_currency VARCHAR(3);
