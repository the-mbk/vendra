-- ══════════════════════════════════════════════════════════════
-- VENDRA: Migration V2 — Shop Location, Order Delivery Type, Pending Status
-- ══════════════════════════════════════════════════════════════

-- 1. Add location columns to vendors
ALTER TABLE vendors ADD COLUMN IF NOT EXISTS latitude DOUBLE PRECISION;
ALTER TABLE vendors ADD COLUMN IF NOT EXISTS longitude DOUBLE PRECISION;

-- 2. Add 'pending' to order_status enum (must use ALTER TYPE)
DO $$ BEGIN
    ALTER TYPE order_status ADD VALUE IF NOT EXISTS 'pending' BEFORE 'confirmed';
EXCEPTION
    WHEN duplicate_object THEN null;
END $$;

-- 3. Add delivery-related columns to orders
ALTER TABLE orders ADD COLUMN IF NOT EXISTS delivery_type VARCHAR(20) DEFAULT 'delivery';
ALTER TABLE orders ADD COLUMN IF NOT EXISTS delivery_address TEXT;
ALTER TABLE orders ADD COLUMN IF NOT EXISTS customer_lat DOUBLE PRECISION;
ALTER TABLE orders ADD COLUMN IF NOT EXISTS customer_lng DOUBLE PRECISION;
ALTER TABLE orders ADD COLUMN IF NOT EXISTS estimated_minutes INTEGER;

-- 4. Update default status for new orders from 'confirmed' to 'pending'
ALTER TABLE orders ALTER COLUMN status SET DEFAULT 'pending';

-- ══════════════════════════════════════
-- Migration V2 applied successfully!
-- ══════════════════════════════════════
