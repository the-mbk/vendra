-- ══════════════════════════════════════════════════════════════
-- VENDRA: Migration 008 — delivery radius
-- Stores farther than max_delivery_km (straight line) from the customer's
-- pin don't deliver to it; self pickup is still allowed.
-- ══════════════════════════════════════════════════════════════

INSERT INTO policies (key, value, label, unit, description) VALUES
    ('max_delivery_km', 15, 'Maximum delivery distance', 'km',
     'Stores farther than this from the customer pin (straight line) offer self pickup only')
ON CONFLICT (key) DO NOTHING;
