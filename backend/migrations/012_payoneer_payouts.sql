-- ══════════════════════════════════════════════════════════════
-- VENDRA: Migration 012 — withdrawals to Payoneer
-- With PAYOUT_PROVIDER=payoneer (the default with Stripe card payments),
-- each wallet owner links a Payoneer account once through Payoneer's
-- registration page; withdrawals are Payoneer payouts to it, in USD.
-- The payee id Vendra gives Payoneer is "vendra-<user id>".
-- ══════════════════════════════════════════════════════════════

ALTER TABLE users ADD COLUMN IF NOT EXISTS payoneer_payee_id VARCHAR(64) UNIQUE;
-- not_registered | pending | active | inactive, as Payoneer last reported it
ALTER TABLE users ADD COLUMN IF NOT EXISTS payoneer_status VARCHAR(20);
ALTER TABLE users ADD COLUMN IF NOT EXISTS payoneer_status_at TIMESTAMPTZ;
