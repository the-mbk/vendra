-- ══════════════════════════════════════════════════════════════
-- VENDRA: Seed Data for Development & Demo
-- Realistic Pakistani marketplace data (Karachi + Lahore)
-- ══════════════════════════════════════════════════════════════
-- Run on a FRESH database AFTER migrations:  npm run migrate && npm run seed
-- All passwords: "password123"
-- ══════════════════════════════════════════════════════════════

BEGIN;
SET CONSTRAINTS ALL DEFERRED;

-- ──────────────────────────────────────
-- 1. ADMIN
-- ──────────────────────────────────────
INSERT INTO users (id, full_name, email, phone, password_hash, role) VALUES
(1, 'Vendra Admin', 'admin@vendra.pk', '0300-1234567', '$2b$10$wxA3oAhNajZeHYp3m8a.YeMXgbOYx0QlSIDZlgWPJtW2le7OWS2se', 'admin');

-- ──────────────────────────────────────
-- 2. VENDORS (approved, with shop locations)
-- ──────────────────────────────────────
INSERT INTO users (id, full_name, email, phone, password_hash, role) VALUES
(2, 'Usman Tariq', 'usman@vendor.pk', '0321-5551234', '$2b$10$wxA3oAhNajZeHYp3m8a.YeMXgbOYx0QlSIDZlgWPJtW2le7OWS2se', 'vendor'),
(3, 'Ayesha Khan', 'ayesha@vendor.pk', '0333-7778899', '$2b$10$wxA3oAhNajZeHYp3m8a.YeMXgbOYx0QlSIDZlgWPJtW2le7OWS2se', 'vendor');

INSERT INTO vendors (id, user_id, store_name, store_address, cnic, latitude, longitude, is_approved) VALUES
(1, 2, 'Karachi Electronics Hub', 'Shop #12, Saddar Market, Karachi', '42101-1234567-1', 24.8556, 67.0224, true),
(2, 3, 'Lahore Fashion Store', 'MM Alam Road, Gulberg III, Lahore', '35202-7654321-3', 31.5129, 74.3512, true);

UPDATE users SET vendor_id = 1 WHERE id = 2;
UPDATE users SET vendor_id = 2 WHERE id = 3;

-- ──────────────────────────────────────
-- 3. CUSTOMERS
-- ──────────────────────────────────────
INSERT INTO users (id, full_name, email, phone, password_hash, role) VALUES
(4, 'Ahmed Raza', 'ahmed@customer.pk', '0312-4445566', '$2b$10$wxA3oAhNajZeHYp3m8a.YeMXgbOYx0QlSIDZlgWPJtW2le7OWS2se', 'customer'),
(5, 'Fatima Ali', 'fatima@customer.pk', '0345-9998877', '$2b$10$wxA3oAhNajZeHYp3m8a.YeMXgbOYx0QlSIDZlgWPJtW2le7OWS2se', 'customer');

-- ──────────────────────────────────────
-- 4. RIDERS (offline until they open the app)
-- ──────────────────────────────────────
INSERT INTO users (id, full_name, email, phone, password_hash, role) VALUES
(6, 'Bilal Hussain', 'bilal@rider.pk', '0301-2223344', '$2b$10$wxA3oAhNajZeHYp3m8a.YeMXgbOYx0QlSIDZlgWPJtW2le7OWS2se', 'rider'),
(7, 'Hamza Sheikh', 'hamza@rider.pk', '0302-6667788', '$2b$10$wxA3oAhNajZeHYp3m8a.YeMXgbOYx0QlSIDZlgWPJtW2le7OWS2se', 'rider');

INSERT INTO riders (id, user_id, vehicle_type, is_online, current_lat, current_lng, last_location_at) VALUES
(1, 6, 'motorbike', false, 24.8600, 67.0250, NOW()),
(2, 7, 'motorbike', false, 31.5100, 74.3450, NOW());

-- ──────────────────────────────────────
-- 5. PRODUCTS (approved, categorised) + 1 awaiting admin approval
-- ──────────────────────────────────────
INSERT INTO products (id, vendor_id, category_id, name, description, price, private_stock, buffer, reserved_quantity, public_stock, barcode, is_approved) VALUES
(1, 1, (SELECT id FROM categories WHERE name = 'Electronics'), 'Samsung Galaxy A54 5G',
 'Samsung Galaxy A54 5G - 128GB Storage, 8GB RAM, Super AMOLED Display, 5000mAh Battery. Official PTA Approved.',
 72999.00, 50, 5, 0, 45, '8806094975123', true),
(2, 1, (SELECT id FROM categories WHERE name = 'Mobile Accessories'), 'Anker PowerCore 10000mAh',
 'Anker PowerCore portable charger 10000mAh. Ultra-compact, high-speed charging with PowerIQ technology.',
 4999.00, 100, 10, 0, 90, '8481940129871', true),
(3, 1, (SELECT id FROM categories WHERE name = 'Electronics'), 'JBL Tune 510BT Headphones',
 'JBL Tune 510BT wireless on-ear headphones. 40-hour battery life, JBL Pure Bass sound, multipoint connection.',
 8499.00, 30, 3, 0, 27, '6925281985642', true),
(4, 1, (SELECT id FROM categories WHERE name = 'Mobile Accessories'), 'iPhone 15 Silicone Case',
 'Premium silicone protective case for iPhone 15. MagSafe compatible, scratch resistant, multiple colors available.',
 2499.00, 200, 20, 0, 180, '1947582036914', true),
(5, 2, (SELECT id FROM categories WHERE name = 'Fashion'), 'Premium Lawn Suit (3-Piece)',
 'Khaddar Lawn 3-piece unstitched suit. Premium quality fabric with elegant embroidery, perfect for summer.',
 4500.00, 40, 5, 0, 35, '8922001453278', true),
(6, 2, (SELECT id FROM categories WHERE name = 'Fashion'), 'Gents Kurta Shalwar',
 'Premium cotton kurta shalwar for men. Available in white, cream, and sky blue. Free alteration included.',
 3200.00, 60, 5, 0, 55, '8922001789012', true),
(7, 2, (SELECT id FROM categories WHERE name = 'Fashion'), 'Bridal Dupatta (Heavy Embroidery)',
 'Heavy embroidered bridal dupatta with zardozi work. Available in red, maroon, and gold combinations.',
 12500.00, 15, 2, 0, 13, '8922001345678', true),
(8, 2, (SELECT id FROM categories WHERE name = 'Fashion'), 'Cotton Hijab Collection (Pack of 3)',
 'Premium cotton hijabs, pack of 3 assorted colors. Breathable fabric, wrinkle-free, machine washable.',
 1800.00, 80, 10, 0, 70, '8922001567890', true),
(9, 1, (SELECT id FROM categories WHERE name = 'Electronics'), 'Xiaomi Redmi Buds 5',
 'Redmi Buds 5 true wireless earbuds with 46dB active noise cancellation and 40-hour battery.',
 6999.00, 25, 3, 0, 22, '6941812745632', false);

INSERT INTO inventory_ledger (product_id, vendor_id, change_type, quantity_change, private_stock_after, public_stock_after, notes) VALUES
(1, 1, 'stock_in', 50, 50, 45, 'Initial stock'),
(2, 1, 'stock_in', 100, 100, 90, 'Initial stock'),
(3, 1, 'stock_in', 30, 30, 27, 'Initial stock'),
(4, 1, 'stock_in', 200, 200, 180, 'Initial stock'),
(5, 2, 'stock_in', 40, 40, 35, 'Initial stock'),
(6, 2, 'stock_in', 60, 60, 55, 'Initial stock'),
(7, 2, 'stock_in', 15, 15, 13, 'Initial stock'),
(8, 2, 'stock_in', 80, 80, 70, 'Initial stock'),
(9, 1, 'stock_in', 25, 25, 22, 'Initial stock');

-- ──────────────────────────────────────
-- 6. WALLET TOP-UPS (simulated deposits)
-- ──────────────────────────────────────
INSERT INTO wallet_ledger (user_id, transaction_type, amount, balance_after, description) VALUES
(4, 'deposit', 200000.00, 200000.00, 'Top-up of Rs. 200000.00'),
(5, 'deposit', 50000.00, 50000.00, 'Top-up of Rs. 50000.00');

-- ──────────────────────────────────────
-- 7. ORDERS
-- ──────────────────────────────────────

-- Order 1: Ahmed (Clifton, Karachi) — delivery, accepted by the store
INSERT INTO orders (id, customer_id, vendor_id, status, subtotal, delivery_fee, total_amount, delivery_type,
                    delivery_address, customer_lat, customer_lng, estimated_minutes, escrow_status) VALUES
(1, 4, 1, 'confirmed', 77998.00, 150.00, 78148.00, 'delivery', 'House 21, Block 5, Clifton, Karachi', 24.8138, 67.0300, 15, 'held');
INSERT INTO order_items (order_id, product_id, quantity, unit_price, subtotal) VALUES
(1, 1, 1, 72999.00, 72999.00),
(1, 2, 1, 4999.00, 4999.00);
UPDATE products SET reserved_quantity = 1, public_stock = 44 WHERE id = 1;
UPDATE products SET reserved_quantity = 1, public_stock = 89 WHERE id = 2;
INSERT INTO inventory_locks (product_id, order_id, quantity, status) VALUES (1, 1, 1, 'active'), (2, 1, 1, 'active');
INSERT INTO inventory_ledger (product_id, vendor_id, change_type, quantity_change, private_stock_after, public_stock_after, reference_id, notes) VALUES
(1, 1, 'reserve', -1, 50, 44, 1, 'Online order reserved'),
(2, 1, 'reserve', -1, 100, 89, 1, 'Online order reserved');
INSERT INTO wallet_ledger (user_id, order_id, transaction_type, amount, balance_after, description) VALUES
(4, 1, 'escrow_hold', 78148.00, 121852.00, 'Escrow hold for Order #1');

-- Order 2: Fatima (Model Town, Lahore) — delivery, packed
INSERT INTO orders (id, customer_id, vendor_id, status, subtotal, delivery_fee, total_amount, delivery_type,
                    delivery_address, customer_lat, customer_lng, estimated_minutes, escrow_status) VALUES
(2, 5, 2, 'packed', 9500.00, 150.00, 9650.00, 'delivery', '45-C, Model Town, Lahore', 31.4834, 74.3260, 15, 'held');
INSERT INTO order_items (order_id, product_id, quantity, unit_price, subtotal) VALUES
(2, 5, 1, 4500.00, 4500.00),
(2, 6, 1, 3200.00, 3200.00),
(2, 8, 1, 1800.00, 1800.00);
UPDATE products SET reserved_quantity = 1, public_stock = 34 WHERE id = 5;
UPDATE products SET reserved_quantity = 1, public_stock = 54 WHERE id = 6;
UPDATE products SET reserved_quantity = 1, public_stock = 69 WHERE id = 8;
INSERT INTO inventory_locks (product_id, order_id, quantity, status) VALUES (5, 2, 1, 'active'), (6, 2, 1, 'active'), (8, 2, 1, 'active');
INSERT INTO inventory_ledger (product_id, vendor_id, change_type, quantity_change, private_stock_after, public_stock_after, reference_id, notes) VALUES
(5, 2, 'reserve', -1, 40, 34, 2, 'Online order reserved'),
(6, 2, 'reserve', -1, 60, 54, 2, 'Online order reserved'),
(8, 2, 'reserve', -1, 80, 69, 2, 'Online order reserved');
INSERT INTO wallet_ledger (user_id, order_id, transaction_type, amount, balance_after, description) VALUES
(5, 2, 'escrow_hold', 9650.00, 40350.00, 'Escrow hold for Order #2');

-- Order 3: Ahmed — self pickup, completed and settled (10% commission)
INSERT INTO orders (id, customer_id, vendor_id, status, subtotal, delivery_fee, total_amount, delivery_type,
                    delivered_at, escrow_status, escrow_settled_at) VALUES
(3, 4, 1, 'delivered', 8499.00, 0.00, 8499.00, 'self_pickup', NOW() - INTERVAL '3 days', 'released', NOW() - INTERVAL '2 days');
INSERT INTO order_items (order_id, product_id, quantity, unit_price, subtotal) VALUES (3, 3, 1, 8499.00, 8499.00);
UPDATE products SET private_stock = 29, reserved_quantity = 0, public_stock = 26 WHERE id = 3;
INSERT INTO inventory_locks (product_id, order_id, quantity, status) VALUES (3, 3, 1, 'consumed');
INSERT INTO inventory_ledger (product_id, vendor_id, change_type, quantity_change, private_stock_after, public_stock_after, reference_id, notes) VALUES
(3, 1, 'reserve', -1, 30, 26, 3, 'Online order reserved'),
(3, 1, 'sale', -1, 29, 26, 3, 'Self pickup completed');
INSERT INTO wallet_ledger (user_id, order_id, transaction_type, amount, balance_after, description) VALUES
(4, 3, 'escrow_hold', 8499.00, 113353.00, 'Escrow hold for Order #3'),
(2, 3, 'escrow_release', 7649.10, 7649.10, 'Escrow released for Order #3 (after 10% commission)');
INSERT INTO platform_ledger (order_id, entry_type, amount) VALUES (3, 'commission', 849.90);

-- ──────────────────────────────────────
-- 8. BALANCES + ESCROW POOL
-- ──────────────────────────────────────
UPDATE users SET wallet_balance = 113353.00 WHERE id = 4;
UPDATE users SET wallet_balance = 40350.00 WHERE id = 5;
UPDATE users SET wallet_balance = 7649.10 WHERE id = 2;

INSERT INTO platform_escrow_wallet (id, balance) VALUES (1, 0.00) ON CONFLICT (id) DO NOTHING;
UPDATE platform_escrow_wallet
SET balance = (SELECT COALESCE(SUM(total_amount - rider_payout), 0) FROM orders WHERE escrow_status IN ('held', 'disputed'))
WHERE id = 1;

-- ──────────────────────────────────────
-- 9. Reset sequences
-- ──────────────────────────────────────
SELECT setval('users_id_seq', (SELECT MAX(id) FROM users));
SELECT setval('vendors_id_seq', (SELECT MAX(id) FROM vendors));
SELECT setval('riders_id_seq', (SELECT MAX(id) FROM riders));
SELECT setval('products_id_seq', (SELECT MAX(id) FROM products));
SELECT setval('orders_id_seq', (SELECT MAX(id) FROM orders));
SELECT setval('order_items_id_seq', (SELECT MAX(id) FROM order_items));
SELECT setval('inventory_locks_id_seq', (SELECT MAX(id) FROM inventory_locks));
SELECT setval('inventory_ledger_id_seq', (SELECT MAX(id) FROM inventory_ledger));
SELECT setval('wallet_ledger_id_seq', (SELECT MAX(id) FROM wallet_ledger));

COMMIT;

-- ══════════════════════════════════════
-- Login credentials (password123 for all):
--   Admin     admin@vendra.pk
--   Vendor    usman@vendor.pk     Karachi Electronics Hub
--   Vendor    ayesha@vendor.pk    Lahore Fashion Store
--   Customer  ahmed@customer.pk   Clifton, Karachi
--   Customer  fatima@customer.pk  Model Town, Lahore
--   Rider     bilal@rider.pk      Karachi
--   Rider     hamza@rider.pk      Lahore
-- ══════════════════════════════════════
