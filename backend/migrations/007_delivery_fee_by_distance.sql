-- ══════════════════════════════════════════════════════════════
-- VENDRA: Migration 007 — delivery fee grows with distance
-- fee = delivery_fee (base) + delivery_fee_per_km × straight-line km
--       from the store to the customer pin, rounded to the nearest Rs 10
-- ══════════════════════════════════════════════════════════════

UPDATE policies
SET label = 'Delivery base fee',
    description = 'Fixed part of the delivery fee on every delivery order'
WHERE key = 'delivery_fee';

INSERT INTO policies (key, value, label, unit, description) VALUES
    ('delivery_fee_per_km', 30, 'Delivery fee per km', 'Rs/km',
     'Added for each km between the store and the customer pin (straight line). The fee is rounded to the nearest Rs 10')
ON CONFLICT (key) DO NOTHING;
