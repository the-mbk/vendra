-- ══════════════════════════════════════════════════════════════
-- VENDRA: Migration 004 — Functional requirements FR01–FR09
-- Policy engine, categories, product approval, walk-in POS sales,
-- rider delivery + GPS, escrow states, disputes, notifications
-- ══════════════════════════════════════════════════════════════

-- ──────────────────────────────────────
-- Policy engine (admin-editable business rules)
-- ──────────────────────────────────────
CREATE TABLE IF NOT EXISTS policies (
    key VARCHAR(50) PRIMARY KEY,
    value NUMERIC(12,2) NOT NULL CHECK (value >= 0),
    label VARCHAR(100) NOT NULL,
    unit VARCHAR(20),
    description TEXT,
    updated_by INTEGER REFERENCES users(id),
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

INSERT INTO policies (key, value, label, unit, description) VALUES
    ('delivery_fee',          150,  'Delivery fee',               'Rs',     'Charged to the customer on delivery orders'),
    ('default_buffer',        5,    'Default stock buffer',       'units',  'Units kept back from online sale for walk-in customers when a vendor does not set one'),
    ('commission_pct',        10,   'Platform commission',        '%',      'Share of the item subtotal the platform keeps when escrow is released'),
    ('rider_base_fee',        60,   'Rider base fee',             'Rs',     'Fixed amount paid to the rider per delivery'),
    ('rider_per_km',          25,   'Rider rate per km',          'Rs/km',  'Paid per km of GPS-tracked distance from pickup to drop-off'),
    ('rider_per_wait_min',    3,    'Rider rate per waiting min', 'Rs/min', 'Paid per minute the rider waits at the store beyond the free allowance'),
    ('rider_free_wait_min',   5,    'Free waiting time',          'min',    'Waiting minutes at the store that are not paid'),
    ('geofence_m',            200,  'Delivery geofence',          'm',      'Rider must be within this distance of the customer pin to mark delivered'),
    ('task_radius_km',        5,    'Task broadcast radius',      'km',     'Riders see ready orders from stores within this distance'),
    ('dispute_window_min',    1440, 'Dispute window',             'min',    'Escrow is released to the vendor this long after delivery unless a dispute is open'),
    ('auto_approve_products', 0,    'Auto-approve products',      '0/1',    '1 = new products go live immediately, 0 = admin approval required')
ON CONFLICT (key) DO NOTHING;

-- ──────────────────────────────────────
-- Categories + product approval (FR06)
-- ──────────────────────────────────────
CREATE TABLE IF NOT EXISTS categories (
    id SERIAL PRIMARY KEY,
    name VARCHAR(60) UNIQUE NOT NULL,
    icon VARCHAR(40),
    sort_order INTEGER NOT NULL DEFAULT 0
);

INSERT INTO categories (name, icon, sort_order) VALUES
    ('Electronics', 'devices', 1),
    ('Mobile Accessories', 'phone_android', 2),
    ('Fashion', 'checkroom', 3),
    ('Grocery', 'local_grocery_store', 4),
    ('Home & Kitchen', 'kitchen', 5),
    ('Health & Beauty', 'spa', 6),
    ('Books & Stationery', 'menu_book', 7),
    ('Other', 'category', 99)
ON CONFLICT (name) DO NOTHING;

ALTER TABLE products ADD COLUMN IF NOT EXISTS category_id INTEGER REFERENCES categories(id);
-- Existing products stay visible; new ones default to needing approval
ALTER TABLE products ADD COLUMN IF NOT EXISTS is_approved BOOLEAN NOT NULL DEFAULT true;
ALTER TABLE products ALTER COLUMN is_approved SET DEFAULT false;
CREATE INDEX IF NOT EXISTS idx_products_category ON products(category_id);
CREATE INDEX IF NOT EXISTS idx_products_barcode ON products(vendor_id, barcode);

-- ──────────────────────────────────────
-- Walk-in POS sales (FR01/FR02)
-- ──────────────────────────────────────
CREATE TABLE IF NOT EXISTS pos_sales (
    id SERIAL PRIMARY KEY,
    vendor_id INTEGER NOT NULL REFERENCES vendors(id),
    cashier_user_id INTEGER REFERENCES users(id),
    total_amount DECIMAL(10,2) NOT NULL CHECK (total_amount >= 0),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS pos_sale_items (
    id SERIAL PRIMARY KEY,
    sale_id INTEGER NOT NULL REFERENCES pos_sales(id) ON DELETE CASCADE,
    product_id INTEGER NOT NULL REFERENCES products(id),
    quantity INTEGER NOT NULL CHECK (quantity > 0),
    unit_price DECIMAL(10,2) NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_pos_sales_vendor ON pos_sales(vendor_id, created_at);

-- ──────────────────────────────────────
-- Orders: money breakdown, rider, escrow state
-- ──────────────────────────────────────
ALTER TABLE orders ADD COLUMN IF NOT EXISTS cancellation_reason TEXT;
ALTER TABLE orders ADD COLUMN IF NOT EXISTS subtotal DECIMAL(10,2);
ALTER TABLE orders ADD COLUMN IF NOT EXISTS delivery_fee DECIMAL(10,2) NOT NULL DEFAULT 0;

UPDATE orders o SET
    subtotal = s.items_total,
    delivery_fee = GREATEST(o.total_amount - s.items_total, 0)
FROM (
    SELECT order_id, SUM(unit_price * quantity) AS items_total
    FROM order_items GROUP BY order_id
) s
WHERE s.order_id = o.id AND o.subtotal IS NULL;

UPDATE orders SET subtotal = total_amount WHERE subtotal IS NULL;

ALTER TABLE orders ADD COLUMN IF NOT EXISTS rider_user_id INTEGER REFERENCES users(id);
ALTER TABLE orders ADD COLUMN IF NOT EXISTS assigned_at TIMESTAMP;
ALTER TABLE orders ADD COLUMN IF NOT EXISTS ready_at TIMESTAMP;
ALTER TABLE orders ADD COLUMN IF NOT EXISTS rider_arrived_at TIMESTAMP;
ALTER TABLE orders ADD COLUMN IF NOT EXISTS picked_at TIMESTAMP;
ALTER TABLE orders ADD COLUMN IF NOT EXISTS delivered_at TIMESTAMP;
ALTER TABLE orders ADD COLUMN IF NOT EXISTS delivery_lat DOUBLE PRECISION;
ALTER TABLE orders ADD COLUMN IF NOT EXISTS delivery_lng DOUBLE PRECISION;
ALTER TABLE orders ADD COLUMN IF NOT EXISTS distance_km DECIMAL(8,3);
ALTER TABLE orders ADD COLUMN IF NOT EXISTS wait_minutes DECIMAL(8,2);
ALTER TABLE orders ADD COLUMN IF NOT EXISTS rider_payout DECIMAL(10,2) NOT NULL DEFAULT 0;

-- held → (disputed) → released | refunded
ALTER TABLE orders ADD COLUMN IF NOT EXISTS escrow_status VARCHAR(20) NOT NULL DEFAULT 'held';
ALTER TABLE orders ADD COLUMN IF NOT EXISTS escrow_release_due_at TIMESTAMP;
ALTER TABLE orders ADD COLUMN IF NOT EXISTS escrow_settled_at TIMESTAMP;

DO $$ BEGIN
    ALTER TABLE orders ADD CONSTRAINT chk_orders_escrow_status
        CHECK (escrow_status IN ('held', 'disputed', 'released', 'refunded'));
EXCEPTION
    WHEN duplicate_object THEN null;
END $$;

UPDATE orders SET escrow_status = 'refunded' WHERE status = 'cancelled' AND escrow_status = 'held';
UPDATE orders SET escrow_status = 'released', escrow_settled_at = updated_at
    WHERE status = 'delivered' AND escrow_status = 'held';

CREATE INDEX IF NOT EXISTS idx_orders_rider ON orders(rider_user_id);
CREATE INDEX IF NOT EXISTS idx_orders_escrow_due ON orders(escrow_release_due_at) WHERE escrow_status = 'held';
CREATE INDEX IF NOT EXISTS idx_orders_status ON orders(status);

-- ──────────────────────────────────────
-- Riders: availability + live location (FR04)
-- ──────────────────────────────────────
ALTER TABLE riders ADD COLUMN IF NOT EXISTS is_online BOOLEAN NOT NULL DEFAULT false;
ALTER TABLE riders ADD COLUMN IF NOT EXISTS current_lat DOUBLE PRECISION;
ALTER TABLE riders ADD COLUMN IF NOT EXISTS current_lng DOUBLE PRECISION;
ALTER TABLE riders ADD COLUMN IF NOT EXISTS last_location_at TIMESTAMP;

CREATE TABLE IF NOT EXISTS rider_locations (
    id BIGSERIAL PRIMARY KEY,
    rider_user_id INTEGER NOT NULL REFERENCES users(id),
    order_id INTEGER REFERENCES orders(id),
    latitude DOUBLE PRECISION NOT NULL,
    longitude DOUBLE PRECISION NOT NULL,
    recorded_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_rider_locations_order ON rider_locations(order_id, recorded_at);

-- ──────────────────────────────────────
-- Platform revenue (commission + delivery margin)
-- ──────────────────────────────────────
CREATE TABLE IF NOT EXISTS platform_ledger (
    id SERIAL PRIMARY KEY,
    order_id INTEGER REFERENCES orders(id),
    entry_type VARCHAR(30) NOT NULL, -- 'commission', 'delivery_margin'
    amount DECIMAL(10,2) NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- ──────────────────────────────────────
-- Disputes (FR08)
-- ──────────────────────────────────────
CREATE TABLE IF NOT EXISTS disputes (
    id SERIAL PRIMARY KEY,
    order_id INTEGER NOT NULL REFERENCES orders(id),
    raised_by INTEGER NOT NULL REFERENCES users(id),
    raised_by_role user_role NOT NULL,
    issue_type VARCHAR(40) NOT NULL,
    description TEXT NOT NULL,
    status VARCHAR(20) NOT NULL DEFAULT 'open' CHECK (status IN ('open', 'resolved')),
    resolution VARCHAR(20) CHECK (resolution IN ('refund', 'release')),
    admin_note TEXT,
    resolved_by INTEGER REFERENCES users(id),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    resolved_at TIMESTAMP
);

-- Only one open dispute per order
CREATE UNIQUE INDEX IF NOT EXISTS uniq_open_dispute_per_order ON disputes(order_id) WHERE status = 'open';

CREATE TABLE IF NOT EXISTS dispute_evidence (
    id SERIAL PRIMARY KEY,
    dispute_id INTEGER NOT NULL REFERENCES disputes(id) ON DELETE CASCADE,
    file_url TEXT NOT NULL,
    original_name TEXT,
    uploaded_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- ──────────────────────────────────────
-- Notifications (FR09)
-- ──────────────────────────────────────
CREATE TABLE IF NOT EXISTS notifications (
    id SERIAL PRIMARY KEY,
    user_id INTEGER NOT NULL REFERENCES users(id),
    type VARCHAR(40) NOT NULL,
    title VARCHAR(150) NOT NULL,
    body TEXT,
    order_id INTEGER REFERENCES orders(id),
    is_read BOOLEAN NOT NULL DEFAULT false,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_notifications_user ON notifications(user_id, created_at DESC);
