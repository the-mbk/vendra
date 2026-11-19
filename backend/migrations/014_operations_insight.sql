-- ══════════════════════════════════════════════════════════════
-- VENDRA: Migration 014 — operations insight
-- 1. Product weight (optional): riders see a parcel weight class before
--    they accept a delivery (Standard / Medium / Heavy).
-- 2. packed_at: when the packing checklist was completed (FR07), shown
--    to the admin as evidence in a dispute.
-- 3. Disputes record where the reporter was (riders reporting an
--    unavailable customer are GPS-tagged), and a third outcome: "split"
--    refunds part of the item subtotal and releases the rest to the store.
-- ══════════════════════════════════════════════════════════════

ALTER TABLE products ADD COLUMN IF NOT EXISTS weight_grams INTEGER;
DO $$ BEGIN
    ALTER TABLE products ADD CONSTRAINT chk_products_weight_grams CHECK (weight_grams IS NULL OR weight_grams > 0);
EXCEPTION
    WHEN duplicate_object THEN null;
END $$;

ALTER TABLE orders ADD COLUMN IF NOT EXISTS packed_at TIMESTAMPTZ;

ALTER TABLE disputes ADD COLUMN IF NOT EXISTS reporter_lat DOUBLE PRECISION;
ALTER TABLE disputes ADD COLUMN IF NOT EXISTS reporter_lng DOUBLE PRECISION;
ALTER TABLE disputes ADD COLUMN IF NOT EXISTS refund_pct NUMERIC(5,2);

ALTER TABLE disputes DROP CONSTRAINT IF EXISTS disputes_resolution_check;
ALTER TABLE disputes ADD CONSTRAINT disputes_resolution_check CHECK (resolution IN ('refund', 'release', 'split'));
