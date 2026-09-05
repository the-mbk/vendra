-- ══════════════════════════════════════════════════════════════
-- VENDRA: Multi-Vendor Digital Marketplace
-- Database Initialization Script (PostgreSQL 16+)
-- ══════════════════════════════════════════════════════════════

-- Create the database (run separately if needed):
-- CREATE DATABASE vendra_db;

-- ──────────────────────────────────────
-- ENUM Types
-- ──────────────────────────────────────
DO $$ BEGIN
    CREATE TYPE user_role AS ENUM ('customer', 'vendor', 'rider', 'admin');
EXCEPTION
    WHEN duplicate_object THEN null;
END $$;

DO $$ BEGIN
    CREATE TYPE order_status AS ENUM (
        'pending', 'confirmed', 'packed', 'ready_for_pickup',
        'picked', 'on_the_way', 'delivered', 'cancelled'
    );
EXCEPTION
    WHEN duplicate_object THEN null;
END $$;

-- ──────────────────────────────────────
-- Core Tables
-- ──────────────────────────────────────

-- Vendors table (created first for circular FK with users)
CREATE TABLE IF NOT EXISTS vendors (
    id SERIAL PRIMARY KEY,
    user_id INTEGER UNIQUE NOT NULL,
    store_name VARCHAR(150) NOT NULL,
    store_address TEXT,
    cnic VARCHAR(15),
    latitude DOUBLE PRECISION,
    longitude DOUBLE PRECISION,
    is_approved BOOLEAN DEFAULT false,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Users table
CREATE TABLE IF NOT EXISTS users (
    id SERIAL PRIMARY KEY,
    full_name VARCHAR(100) NOT NULL,
    email VARCHAR(100) UNIQUE NOT NULL,
    phone VARCHAR(20),
    password_hash VARCHAR(255) NOT NULL,
    role user_role NOT NULL,
    vendor_id INTEGER REFERENCES vendors(id) ON DELETE SET NULL,
    wallet_balance DECIMAL(10,2) NOT NULL DEFAULT 0.00,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Deferred FK from vendors → users (handles circular dependency)
DO $$ BEGIN
    ALTER TABLE vendors ADD CONSTRAINT fk_vendor_user
        FOREIGN KEY (user_id) REFERENCES users(id)
        DEFERRABLE INITIALLY DEFERRED;
EXCEPTION
    WHEN duplicate_object THEN null;
END $$;

-- ──────────────────────────────────────
-- Products (Dual Inventory Model)
-- ──────────────────────────────────────
CREATE TABLE IF NOT EXISTS products (
    id SERIAL PRIMARY KEY,
    vendor_id INTEGER REFERENCES vendors(id) NOT NULL,
    name VARCHAR(200) NOT NULL,
    description TEXT,
    price DECIMAL(10,2) NOT NULL CHECK (price >= 0),
    private_stock INTEGER NOT NULL DEFAULT 0 CHECK (private_stock >= 0),
    buffer INTEGER NOT NULL DEFAULT 5 CHECK (buffer >= 0),
    reserved_quantity INTEGER NOT NULL DEFAULT 0 CHECK (reserved_quantity >= 0),
    public_stock INTEGER NOT NULL DEFAULT 0 CHECK (public_stock >= 0),
    barcode VARCHAR(100),
    image_url TEXT,
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- ──────────────────────────────────────
-- Orders & Order Items
-- ──────────────────────────────────────
CREATE TABLE IF NOT EXISTS orders (
    id SERIAL PRIMARY KEY,
    customer_id INTEGER REFERENCES users(id) NOT NULL,
    vendor_id INTEGER REFERENCES vendors(id) NOT NULL,
    status order_status NOT NULL DEFAULT 'pending',
    total_amount DECIMAL(10,2) NOT NULL,
    delivery_type VARCHAR(20) DEFAULT 'delivery',
    delivery_address TEXT,
    customer_lat DOUBLE PRECISION,
    customer_lng DOUBLE PRECISION,
    estimated_minutes INTEGER,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS order_items (
    id SERIAL PRIMARY KEY,
    order_id INTEGER REFERENCES orders(id) ON DELETE CASCADE,
    product_id INTEGER REFERENCES products(id),
    quantity INTEGER NOT NULL CHECK (quantity > 0),
    unit_price DECIMAL(10,2) NOT NULL,
    subtotal DECIMAL(10,2)
);

-- ──────────────────────────────────────
-- Inventory Management
-- ──────────────────────────────────────
CREATE TABLE IF NOT EXISTS inventory_locks (
    id SERIAL PRIMARY KEY,
    product_id INTEGER REFERENCES products(id),
    order_id INTEGER REFERENCES orders(id),
    quantity INTEGER NOT NULL,
    status VARCHAR(30) DEFAULT 'active',
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS inventory_ledger (
    id SERIAL PRIMARY KEY,
    product_id INTEGER REFERENCES products(id),
    vendor_id INTEGER REFERENCES vendors(id),
    change_type VARCHAR(20) NOT NULL, -- 'stock_in', 'reserve', 'release', 'sale'
    quantity_change INTEGER NOT NULL,
    private_stock_after INTEGER,
    public_stock_after INTEGER,
    reference_id INTEGER, -- order_id or null
    notes TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- ──────────────────────────────────────
-- Riders (Placeholder for future)
-- ──────────────────────────────────────
CREATE TABLE IF NOT EXISTS riders (
    id SERIAL PRIMARY KEY,
    user_id INTEGER UNIQUE REFERENCES users(id) NOT NULL,
    vehicle_type VARCHAR(50),
    is_available BOOLEAN DEFAULT true,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- ──────────────────────────────────────
-- Wallet & Escrow Ledger
-- ──────────────────────────────────────
CREATE TABLE IF NOT EXISTS wallet_ledger (
    id SERIAL PRIMARY KEY,
    user_id INTEGER REFERENCES users(id) NOT NULL,
    order_id INTEGER REFERENCES orders(id),
    transaction_type VARCHAR(50) NOT NULL, -- 'deposit', 'escrow_hold', 'escrow_refund', 'escrow_release', 'withdrawal'
    amount DECIMAL(10,2) NOT NULL,
    balance_after DECIMAL(10,2) NOT NULL,
    description TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Platform-wide escrow pool (mirrors funds deducted from customer wallets until release/refund)
CREATE TABLE IF NOT EXISTS platform_escrow_wallet (
    id SMALLINT PRIMARY KEY DEFAULT 1 CHECK (id = 1),
    balance DECIMAL(14,2) NOT NULL DEFAULT 0.00
);

INSERT INTO platform_escrow_wallet (id, balance) VALUES (1, 0.00)
ON CONFLICT (id) DO NOTHING;

-- ──────────────────────────────────────
-- Indexes for Performance
-- ──────────────────────────────────────
CREATE INDEX IF NOT EXISTS idx_products_vendor ON products(vendor_id);
CREATE INDEX IF NOT EXISTS idx_products_public_stock ON products(public_stock) WHERE public_stock > 0;
CREATE INDEX IF NOT EXISTS idx_orders_customer ON orders(customer_id);
CREATE INDEX IF NOT EXISTS idx_orders_vendor ON orders(vendor_id);
CREATE INDEX IF NOT EXISTS idx_order_items_order ON order_items(order_id);
CREATE INDEX IF NOT EXISTS idx_inventory_ledger_product ON inventory_ledger(product_id);
CREATE INDEX IF NOT EXISTS idx_users_email ON users(email);
CREATE INDEX IF NOT EXISTS idx_vendors_approved ON vendors(is_approved);

-- ══════════════════════════════════════
-- Schema initialized successfully!
-- ══════════════════════════════════════
