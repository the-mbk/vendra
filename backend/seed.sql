-- ══════════════════════════════════════════════════════════════
-- VENDRA: Seed Data for Development & Testing
-- Realistic Pakistani Marketplace Data
-- ══════════════════════════════════════════════════════════════
-- Run AFTER init.sql: psql -U postgres -d vendra_db -f seed.sql
-- All passwords: "password123" (bcrypt hash below)
-- ══════════════════════════════════════════════════════════════

-- Password hash for "password123" (bcrypt, 10 rounds)
-- $2b$10$wxA3oAhNajZeHYp3m8a.YeMXgbOYx0QlSIDZlgWPJtW2le7OWS2se

BEGIN;
SET CONSTRAINTS ALL DEFERRED;

-- ──────────────────────────────────────
-- 1. ADMIN USER
-- ──────────────────────────────────────
INSERT INTO users (id, full_name, email, phone, password_hash, role) VALUES
(1, 'Vendra Admin', 'admin@vendra.pk', '0300-1234567', '$2b$10$wxA3oAhNajZeHYp3m8a.YeMXgbOYx0QlSIDZlgWPJtW2le7OWS2se', 'admin');

-- ──────────────────────────────────────
-- 2. VENDORS (2 approved, ready for demo)
-- ──────────────────────────────────────

-- Vendor User 1: Karachi Electronics Hub
INSERT INTO users (id, full_name, email, phone, password_hash, role) VALUES
(2, 'Usman Tariq', 'usman@vendor.pk', '0321-5551234', '$2b$10$wxA3oAhNajZeHYp3m8a.YeMXgbOYx0QlSIDZlgWPJtW2le7OWS2se', 'vendor');

INSERT INTO vendors (id, user_id, store_name, store_address, cnic, is_approved) VALUES
(1, 2, 'Karachi Electronics Hub', 'Shop #12, Saddar Market, Karachi', '42101-1234567-1', true);

UPDATE users SET vendor_id = 1 WHERE id = 2;

-- Vendor User 2: Lahore Fashion Store
INSERT INTO users (id, full_name, email, phone, password_hash, role) VALUES
(3, 'Ayesha Khan', 'ayesha@vendor.pk', '0333-7778899', '$2b$10$wxA3oAhNajZeHYp3m8a.YeMXgbOYx0QlSIDZlgWPJtW2le7OWS2se', 'vendor');

INSERT INTO vendors (id, user_id, store_name, store_address, cnic, is_approved) VALUES
(2, 3, 'Lahore Fashion Store', 'MM Alam Road, Gulberg III, Lahore', '35202-7654321-3', true);

UPDATE users SET vendor_id = 2 WHERE id = 3;

-- ──────────────────────────────────────
-- 3. CUSTOMERS (2 active buyers)
-- ──────────────────────────────────────
INSERT INTO users (id, full_name, email, phone, password_hash, role) VALUES
(4, 'Ahmed Raza', 'ahmed@customer.pk', '0312-4445566', '$2b$10$wxA3oAhNajZeHYp3m8a.YeMXgbOYx0QlSIDZlgWPJtW2le7OWS2se', 'customer'),
(5, 'Fatima Ali', 'fatima@customer.pk', '0345-9998877', '$2b$10$wxA3oAhNajZeHYp3m8a.YeMXgbOYx0QlSIDZlgWPJtW2le7OWS2se', 'customer');

-- ──────────────────────────────────────
-- 4. PRODUCTS (8 items across 2 vendors)
-- ──────────────────────────────────────

-- Vendor 1: Karachi Electronics Hub (4 products)
INSERT INTO products (id, vendor_id, name, description, price, private_stock, buffer, reserved_quantity, public_stock, barcode) VALUES
(1, 1, 'Samsung Galaxy A54 5G',
 'Samsung Galaxy A54 5G - 128GB Storage, 8GB RAM, Super AMOLED Display, 5000mAh Battery. Official PTA Approved.',
 72999.00, 50, 5, 0, 45, '8806094975123'),

(2, 1, 'Anker PowerCore 10000mAh',
 'Anker PowerCore portable charger 10000mAh. Ultra-compact, high-speed charging with PowerIQ technology.',
 4999.00, 100, 10, 0, 90, '8481940129871'),

(3, 1, 'JBL Tune 510BT Headphones',
 'JBL Tune 510BT wireless on-ear headphones. 40-hour battery life, JBL Pure Bass sound, multipoint connection.',
 8499.00, 30, 3, 0, 27, '6925281985642'),

(4, 1, 'iPhone 15 Silicone Case',
 'Premium silicone protective case for iPhone 15. MagSafe compatible, scratch resistant, multiple colors available.',
 2499.00, 200, 20, 0, 180, '1947582036914');

-- Vendor 2: Lahore Fashion Store (4 products)
INSERT INTO products (id, vendor_id, name, description, price, private_stock, buffer, reserved_quantity, public_stock, barcode) VALUES
(5, 2, 'Premium Lawn Suit (3-Piece)',
 'Khaddar Lawn 3-piece unstitched suit. Premium quality fabric with elegant embroidery, perfect for summer.',
 4500.00, 40, 5, 0, 35, '8922001453278'),

(6, 2, 'Gents Kurta Shalwar',
 'Premium cotton kurta shalwar for men. Available in white, cream, and sky blue. Free alteration included.',
 3200.00, 60, 5, 0, 55, '8922001789012'),

(7, 2, 'Bridal Dupatta (Heavy Embroidery)',
 'Heavy embroidered bridal dupatta with zardozi work. Available in red, maroon, and gold combinations.',
 12500.00, 15, 2, 0, 13, '8922001345678'),

(8, 2, 'Cotton Hijab Collection (Pack of 3)',
 'Premium cotton hijabs, pack of 3 assorted colors. Breathable fabric, wrinkle-free, machine washable.',
 1800.00, 80, 10, 0, 70, '8922001567890');

-- ──────────────────────────────────────
-- 5. ORDERS (3 sample orders)
-- ──────────────────────────────────────

-- Order 1: Ahmed orders electronics
INSERT INTO orders (id, customer_id, vendor_id, status, total_amount) VALUES
(1, 4, 1, 'confirmed', 77998.00);

INSERT INTO order_items (order_id, product_id, quantity, unit_price, subtotal) VALUES
(1, 1, 1, 72999.00, 72999.00),
(1, 2, 1, 4999.00, 4999.00);

-- Reserve stock for Order 1
UPDATE products SET reserved_quantity = 1, public_stock = 44 WHERE id = 1;
UPDATE products SET reserved_quantity = 1, public_stock = 89 WHERE id = 2;

INSERT INTO inventory_locks (product_id, order_id, quantity, status) VALUES
(1, 1, 1, 'active'),
(2, 1, 1, 'active');

INSERT INTO inventory_ledger (product_id, vendor_id, change_type, quantity_change, private_stock_after, public_stock_after, reference_id, notes) VALUES
(1, 1, 'reserve', -1, 50, 44, 1, 'Order #1 placement'),
(2, 1, 'reserve', -1, 100, 89, 1, 'Order #1 placement');

-- Order 2: Fatima orders fashion
INSERT INTO orders (id, customer_id, vendor_id, status, total_amount) VALUES
(2, 5, 2, 'packed', 9700.00);

INSERT INTO order_items (order_id, product_id, quantity, unit_price, subtotal) VALUES
(2, 5, 1, 4500.00, 4500.00),
(2, 6, 1, 3200.00, 3200.00),
(2, 8, 1, 1800.00, 1800.00);

-- Reserve stock for Order 2 (note: 1 extra was bought by someone)
UPDATE products SET reserved_quantity = 1, public_stock = 34 WHERE id = 5;
UPDATE products SET reserved_quantity = 1, public_stock = 54 WHERE id = 6;
UPDATE products SET reserved_quantity = 1, public_stock = 69 WHERE id = 8;

INSERT INTO inventory_locks (product_id, order_id, quantity, status) VALUES
(5, 2, 1, 'active'),
(6, 2, 1, 'active'),
(8, 2, 1, 'active');

INSERT INTO inventory_ledger (product_id, vendor_id, change_type, quantity_change, private_stock_after, public_stock_after, reference_id, notes) VALUES
(5, 2, 'reserve', -1, 40, 34, 2, 'Order #2 placement'),
(6, 2, 'reserve', -1, 60, 54, 2, 'Order #2 placement'),
(8, 2, 'reserve', -1, 80, 69, 2, 'Order #2 placement');

-- Order 3: Ahmed orders headphones (delivered)
INSERT INTO orders (id, customer_id, vendor_id, status, total_amount) VALUES
(3, 4, 1, 'delivered', 8499.00);

INSERT INTO order_items (order_id, product_id, quantity, unit_price, subtotal) VALUES
(3, 3, 1, 8499.00, 8499.00);

UPDATE products SET reserved_quantity = 0, public_stock = 26, private_stock = 29 WHERE id = 3;

INSERT INTO inventory_locks (product_id, order_id, quantity, status) VALUES
(3, 3, 1, 'completed');

INSERT INTO inventory_ledger (product_id, vendor_id, change_type, quantity_change, private_stock_after, public_stock_after, reference_id, notes) VALUES
(3, 1, 'reserve', -1, 30, 26, 3, 'Order #3 placement'),
(3, 1, 'sale', -1, 29, 26, 3, 'Order #3 delivered — stock deducted');

-- ──────────────────────────────────────
-- 6. INITIAL STOCK LEDGER ENTRIES
-- ──────────────────────────────────────
INSERT INTO inventory_ledger (product_id, vendor_id, change_type, quantity_change, private_stock_after, public_stock_after, notes) VALUES
(1, 1, 'stock_in', 50, 50, 45, 'Initial stock — Samsung Galaxy A54'),
(2, 1, 'stock_in', 100, 100, 90, 'Initial stock — Anker PowerCore'),
(3, 1, 'stock_in', 30, 30, 27, 'Initial stock — JBL Headphones'),
(4, 1, 'stock_in', 200, 200, 180, 'Initial stock — iPhone 15 Case'),
(5, 2, 'stock_in', 40, 40, 35, 'Initial stock — Lawn Suit'),
(6, 2, 'stock_in', 60, 60, 55, 'Initial stock — Kurta Shalwar'),
(7, 2, 'stock_in', 15, 15, 13, 'Initial stock — Bridal Dupatta'),
(8, 2, 'stock_in', 80, 80, 70, 'Initial stock — Cotton Hijab');

-- ──────────────────────────────────────
-- Reset sequences to avoid ID conflicts
-- ──────────────────────────────────────
SELECT setval('users_id_seq', (SELECT MAX(id) FROM users));
SELECT setval('vendors_id_seq', (SELECT MAX(id) FROM vendors));
SELECT setval('products_id_seq', (SELECT MAX(id) FROM products));
SELECT setval('orders_id_seq', (SELECT MAX(id) FROM orders));
SELECT setval('order_items_id_seq', (SELECT MAX(id) FROM order_items));
SELECT setval('inventory_locks_id_seq', (SELECT MAX(id) FROM inventory_locks));
SELECT setval('inventory_ledger_id_seq', (SELECT MAX(id) FROM inventory_ledger));

-- Sync platform escrow pool with open orders (seed / legacy data)
INSERT INTO platform_escrow_wallet (id, balance) VALUES (1, 0.00) ON CONFLICT (id) DO NOTHING;
UPDATE platform_escrow_wallet AS p
SET balance = sub.t
FROM (
  SELECT COALESCE(SUM(total_amount), 0) AS t
  FROM orders
  WHERE status NOT IN ('cancelled', 'delivered')
) AS sub
WHERE p.id = 1;

COMMIT;

-- ══════════════════════════════════════
-- Seed data loaded successfully!
-- ══════════════════════════════════════
-- Login Credentials:
-- Admin:    admin@vendra.pk    / password123
-- Vendor 1: usman@vendor.pk   / password123  (Karachi Electronics Hub)
-- Vendor 2: ayesha@vendor.pk  / password123  (Lahore Fashion Store)
-- Customer: ahmed@customer.pk  / password123
-- Customer: fatima@customer.pk / password123
-- ══════════════════════════════════════
