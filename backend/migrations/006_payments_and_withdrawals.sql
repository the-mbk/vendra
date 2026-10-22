-- ══════════════════════════════════════════════════════════════
-- VENDRA: Migration 006 — card payments, withdrawals, order timeouts
--
-- Money now enters only through the payment gateway (Vendra Pay) and
-- leaves through card payouts. Each wallet movement can carry the
-- gateway reference (pi_… / po_…) for receipts and reconciliation.
-- ══════════════════════════════════════════════════════════════

-- Gateway reference on wallet movements (payment intent or payout id)
ALTER TABLE wallet_ledger ADD COLUMN IF NOT EXISTS reference VARCHAR(64);

-- Money that existed before the gateway (seed data, old simulated top-ups) is an
-- opening balance, so reconciliation can show it separately from real card payments.
UPDATE wallet_ledger SET transaction_type = 'opening_balance'
WHERE transaction_type = 'deposit' AND reference IS NULL;

-- ──────────────────────────────────────
-- Card payments (top-ups and card checkouts)
-- ──────────────────────────────────────
CREATE TABLE IF NOT EXISTS payments (
    id SERIAL PRIMARY KEY,
    user_id INTEGER NOT NULL REFERENCES users(id),
    purpose VARCHAR(20) NOT NULL CHECK (purpose IN ('topup', 'checkout')),
    amount DECIMAL(12,2) NOT NULL CHECK (amount > 0),
    gateway_intent_id VARCHAR(64) UNIQUE,
    status VARCHAR(20) NOT NULL DEFAULT 'processing'
        CHECK (status IN ('processing', 'requires_action', 'succeeded', 'failed', 'canceled')),
    card_brand VARCHAR(20),
    card_last4 VARCHAR(4),
    failure_message TEXT,
    checkout JSONB,                          -- the cart, for card checkouts
    order_id INTEGER REFERENCES orders(id),  -- the order a card checkout created
    order_error TEXT,                        -- why the order couldn't be placed after payment
    credited_at TIMESTAMPTZ,                 -- when the money reached the wallet (exactly once)
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_payments_user ON payments(user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_payments_open ON payments(status) WHERE status IN ('processing', 'requires_action');

-- ──────────────────────────────────────
-- Withdrawals (wallet → card payout)
-- ──────────────────────────────────────
CREATE TABLE IF NOT EXISTS withdrawals (
    id SERIAL PRIMARY KEY,
    user_id INTEGER NOT NULL REFERENCES users(id),
    amount DECIMAL(12,2) NOT NULL CHECK (amount > 0),
    gateway_payout_id VARCHAR(64) UNIQUE,
    status VARCHAR(20) NOT NULL DEFAULT 'pending'
        CHECK (status IN ('pending', 'in_transit', 'paid', 'failed')),
    card_brand VARCHAR(20),
    card_last4 VARCHAR(4),
    failure_message TEXT,
    payout_token VARCHAR(64),                       -- card token, kept so a lost request can be retried safely
    ledger_id INTEGER REFERENCES wallet_ledger(id), -- the wallet debit, tagged with the payout id once known
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    settled_at TIMESTAMPTZ
);
CREATE INDEX IF NOT EXISTS idx_withdrawals_user ON withdrawals(user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_withdrawals_open ON withdrawals(status) WHERE status IN ('pending', 'in_transit');

-- Funds the platform added to its gateway balance to back opening balances
CREATE TABLE IF NOT EXISTS gateway_fundings (
    id SERIAL PRIMARY KEY,
    amount DECIMAL(14,2) NOT NULL CHECK (amount > 0),
    gateway_topup_id VARCHAR(64) UNIQUE NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Webhook events already processed (the gateway may deliver one more than once)
CREATE TABLE IF NOT EXISTS gateway_events (
    id VARCHAR(64) PRIMARY KEY,
    type VARCHAR(60) NOT NULL,
    received_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- How each order was paid
ALTER TABLE orders ADD COLUMN IF NOT EXISTS payment_method VARCHAR(10) NOT NULL DEFAULT 'wallet'
    CHECK (payment_method IN ('wallet', 'card'));

-- ──────────────────────────────────────
-- Policies: order timeouts and withdrawals
-- ──────────────────────────────────────
INSERT INTO policies (key, value, label, unit, description) VALUES
    ('vendor_accept_timeout_min', 30, 'Store response time',   'min', 'A pending order the store has not accepted in this time is cancelled and refunded'),
    ('rider_assign_timeout_min',  60, 'Rider search time',     'min', 'A ready delivery order no rider has accepted in this time is cancelled and refunded'),
    ('min_withdrawal',            500, 'Minimum withdrawal',   'Rs',  'Smallest amount a user can withdraw to a card')
ON CONFLICT (key) DO NOTHING;
