-- ══════════════════════════════════════════════════════════════
-- VENDRA: Migration 010 — trust & operations
--  1. Customer reviews and ratings (SRDS §2.3, Fig 2.3)
--  2. Delivery handover OTP: the rider needs the customer's 4-digit code
--     to mark an order delivered, so a spoofed GPS position alone is not enough
--  3. Rider documents (CNIC, licence, vehicle) and admin approval
--  4. Shop staff with PIN switching: cashier, packer, inventory manager (SRDS §1.3)
--  5. Packing checklist: each order line is ticked or scanned before "packed" (FR07)
--  6. Product photo gallery (FR06)
--  7. Itemised rider payout slip (FR04) and receipt settings for POS slips
-- ══════════════════════════════════════════════════════════════

-- ──────────────────────────────────────
-- 1. Reviews: one per product per delivered order
-- ──────────────────────────────────────
CREATE TABLE IF NOT EXISTS product_reviews (
    id SERIAL PRIMARY KEY,
    order_id INTEGER NOT NULL REFERENCES orders(id),
    product_id INTEGER NOT NULL REFERENCES products(id),
    vendor_id INTEGER NOT NULL REFERENCES vendors(id),
    customer_id INTEGER NOT NULL REFERENCES users(id),
    rating SMALLINT NOT NULL CHECK (rating BETWEEN 1 AND 5),
    comment TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (order_id, product_id)
);
CREATE INDEX IF NOT EXISTS idx_reviews_product ON product_reviews(product_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_reviews_vendor ON product_reviews(vendor_id);

-- Running totals so product lists can show stars without aggregating every review
ALTER TABLE products ADD COLUMN IF NOT EXISTS rating_count INTEGER NOT NULL DEFAULT 0;
ALTER TABLE products ADD COLUMN IF NOT EXISTS rating_sum INTEGER NOT NULL DEFAULT 0;

-- Rider and store ratings left with the same review
ALTER TABLE orders ADD COLUMN IF NOT EXISTS reviewed_at TIMESTAMPTZ;
ALTER TABLE orders ADD COLUMN IF NOT EXISTS rider_rating SMALLINT CHECK (rider_rating BETWEEN 1 AND 5);

-- ──────────────────────────────────────
-- 2. Delivery handover OTP
-- ──────────────────────────────────────
ALTER TABLE orders ADD COLUMN IF NOT EXISTS delivery_otp VARCHAR(6);
ALTER TABLE orders ADD COLUMN IF NOT EXISTS otp_failed_attempts SMALLINT NOT NULL DEFAULT 0;
ALTER TABLE orders ADD COLUMN IF NOT EXISTS otp_locked_until TIMESTAMPTZ;
ALTER TABLE orders ADD COLUMN IF NOT EXISTS otp_verified_at TIMESTAMPTZ;

-- Orders already on their way get a code so they can still be delivered
UPDATE orders SET delivery_otp = LPAD((FLOOR(RANDOM() * 10000))::int::text, 4, '0')
WHERE delivery_otp IS NULL AND status NOT IN ('delivered', 'cancelled');

-- ──────────────────────────────────────
-- 3. Rider documents + approval
-- ──────────────────────────────────────
ALTER TABLE riders ADD COLUMN IF NOT EXISTS cnic VARCHAR(15);
ALTER TABLE riders ADD COLUMN IF NOT EXISTS license_number VARCHAR(30);
ALTER TABLE riders ADD COLUMN IF NOT EXISTS vehicle_number VARCHAR(20);
-- Riders already delivering stay approved; new sign-ups wait for an admin
ALTER TABLE riders ADD COLUMN IF NOT EXISTS approval_status VARCHAR(10) NOT NULL DEFAULT 'approved';
ALTER TABLE riders ALTER COLUMN approval_status SET DEFAULT 'pending';
ALTER TABLE riders ADD COLUMN IF NOT EXISTS rejection_reason TEXT;
ALTER TABLE riders ADD COLUMN IF NOT EXISTS reviewed_at TIMESTAMPTZ;

DO $$ BEGIN
    ALTER TABLE riders ADD CONSTRAINT chk_riders_approval_status
        CHECK (approval_status IN ('pending', 'approved', 'rejected'));
EXCEPTION
    WHEN duplicate_object THEN null;
END $$;

CREATE INDEX IF NOT EXISTS idx_riders_pending ON riders(created_at) WHERE approval_status = 'pending';

-- ──────────────────────────────────────
-- 4. Shop staff (PIN switch on the shop's device)
-- ──────────────────────────────────────
CREATE TABLE IF NOT EXISTS vendor_staff (
    id SERIAL PRIMARY KEY,
    vendor_id INTEGER NOT NULL REFERENCES vendors(id),
    full_name VARCHAR(100) NOT NULL,
    role VARCHAR(20) NOT NULL CHECK (role IN ('cashier', 'packer', 'inventory_manager')),
    pin_hash VARCHAR(255) NOT NULL,
    is_active BOOLEAN NOT NULL DEFAULT true,
    pin_failed_attempts SMALLINT NOT NULL DEFAULT 0,
    pin_locked_until TIMESTAMPTZ,
    last_login_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_vendor_staff_vendor ON vendor_staff(vendor_id) WHERE is_active;

-- Who rang up a walk-in sale, and who packed an order
ALTER TABLE pos_sales ADD COLUMN IF NOT EXISTS staff_id INTEGER REFERENCES vendor_staff(id);
ALTER TABLE orders ADD COLUMN IF NOT EXISTS packed_by_staff_id INTEGER REFERENCES vendor_staff(id);

-- ──────────────────────────────────────
-- 5. Packing checklist
-- ──────────────────────────────────────
ALTER TABLE order_items ADD COLUMN IF NOT EXISTS packed_quantity INTEGER NOT NULL DEFAULT 0;
DO $$ BEGIN
    ALTER TABLE order_items ADD CONSTRAINT chk_order_items_packed
        CHECK (packed_quantity >= 0 AND packed_quantity <= quantity);
EXCEPTION
    WHEN duplicate_object THEN null;
END $$;

-- Orders packed before the checklist existed count as fully packed
UPDATE order_items oi SET packed_quantity = oi.quantity
FROM orders o
WHERE o.id = oi.order_id AND o.status NOT IN ('pending', 'confirmed') AND oi.packed_quantity = 0;

-- ──────────────────────────────────────
-- 6. Product photo gallery (image_url stays the cover photo)
-- ──────────────────────────────────────
CREATE TABLE IF NOT EXISTS product_images (
    id SERIAL PRIMARY KEY,
    product_id INTEGER NOT NULL REFERENCES products(id) ON DELETE CASCADE,
    url TEXT NOT NULL,
    position SMALLINT NOT NULL DEFAULT 0,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_product_images_product ON product_images(product_id, position, id);

-- ──────────────────────────────────────
-- 7. Rider payout slip + receipt settings
-- ──────────────────────────────────────
-- { baseFee, perKm, distanceKm, distancePay, perWaitMin, freeWaitMin, waitMinutes, paidWaitMinutes, waitPay, total }
ALTER TABLE orders ADD COLUMN IF NOT EXISTS payout_breakdown JSONB;

ALTER TABLE vendors ADD COLUMN IF NOT EXISTS receipt_header TEXT;
ALTER TABLE vendors ADD COLUMN IF NOT EXISTS receipt_footer TEXT;
-- Where walk-in customers can pay by QR (Raast ID, IBAN, JazzCash/Easypaisa number)
ALTER TABLE vendors ADD COLUMN IF NOT EXISTS payment_account VARCHAR(60);
ALTER TABLE vendors ADD COLUMN IF NOT EXISTS payment_account_title VARCHAR(100);
