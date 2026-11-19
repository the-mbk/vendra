-- ══════════════════════════════════════════════════════════════
-- VENDRA: Migration 015 — anti-abuse gates
-- 1. Task hoarding: a rider who accepts a delivery but doesn't reach the
--    store within `rider_pickup_timeout_min` loses it; it goes back to the
--    other riders. rider_released_at restarts the "no rider" clock so the
--    order isn't cancelled straight after being put back.
-- 2. trust_events: an audit trail of abuse signals the admin sees on the
--    store, the rider and in a dispute dossier:
--      walk_in_override    a cashier cancelled an online order to sell its
--                          reserved units at the counter
--      rider_task_timeout  a rider let an accepted delivery lapse
--      handover_lockout    wrong handover codes locked an order's handover
-- ══════════════════════════════════════════════════════════════

INSERT INTO policies (key, value, label, unit, description) VALUES
    ('rider_pickup_timeout_min', 20, 'Rider pickup deadline', 'min',
     'A rider who accepts a delivery must reach the store within this time, or it goes back to other riders')
ON CONFLICT (key) DO NOTHING;

ALTER TABLE orders ADD COLUMN IF NOT EXISTS rider_released_at TIMESTAMPTZ;

CREATE TABLE IF NOT EXISTS trust_events (
    id SERIAL PRIMARY KEY,
    kind VARCHAR(30) NOT NULL CHECK (kind IN ('walk_in_override', 'rider_task_timeout', 'handover_lockout')),
    order_id INTEGER NOT NULL REFERENCES orders(id),
    vendor_id INTEGER NOT NULL REFERENCES vendors(id),
    -- Who it counts against: the rider, or the cashier's account (null for a store-side lockout)
    user_id INTEGER REFERENCES users(id),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_trust_events_vendor ON trust_events (vendor_id, kind, created_at);
CREATE INDEX IF NOT EXISTS idx_trust_events_user ON trust_events (user_id, kind, created_at);
CREATE INDEX IF NOT EXISTS idx_trust_events_order ON trust_events (order_id);
