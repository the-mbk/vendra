-- Run once on existing databases: psql -U postgres -d vendra_db -f migration_escrow_pool.sql

CREATE TABLE IF NOT EXISTS platform_escrow_wallet (
    id SMALLINT PRIMARY KEY DEFAULT 1 CHECK (id = 1),
    balance DECIMAL(14,2) NOT NULL DEFAULT 0.00
);

INSERT INTO platform_escrow_wallet (id, balance) VALUES (1, 0.00) ON CONFLICT (id) DO NOTHING;

UPDATE platform_escrow_wallet AS p
SET balance = sub.t
FROM (
  SELECT COALESCE(SUM(total_amount), 0) AS t
  FROM orders
  WHERE status NOT IN ('cancelled', 'delivered')
) AS sub
WHERE p.id = 1;
