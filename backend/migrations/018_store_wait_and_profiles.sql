-- ══════════════════════════════════════════════════════════════
-- 018: store wait limit, store-confirmed handover, profile photos
--
-- A rider who taps "Arrived at store" stops the hoarding clock and starts
-- paid waiting. Without a limit a rider could sit at the store and keep the
-- delivery (and the waiting pay) indefinitely. Now:
--   rider_store_wait_max_min  arrived but not collected within this time:
--                             the delivery goes back to other riders, the
--                             rider earns nothing for it, and waiting pay
--                             never counts past this limit.
--   orders.pickup_confirmed_by  who confirmed the handover at the store:
--                             the rider ("Picked up") or the store
--                             ("Handed over", which also stops the clock).
-- users.avatar_url: the profile photo customers and riders can set.
-- ══════════════════════════════════════════════════════════════

ALTER TABLE users ADD COLUMN IF NOT EXISTS avatar_url VARCHAR(500);

ALTER TABLE orders ADD COLUMN IF NOT EXISTS pickup_confirmed_by VARCHAR(10);
DO $$ BEGIN
  ALTER TABLE orders ADD CONSTRAINT orders_pickup_confirmed_by_check
    CHECK (pickup_confirmed_by IS NULL OR pickup_confirmed_by IN ('rider', 'store'));
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

INSERT INTO policies (key, value, label, unit, description) VALUES
  ('rider_store_wait_max_min', 15, 'Longest wait at the store', 'min',
   'A rider who has arrived but not collected the order within this time loses the delivery: it goes back to other riders, and waiting pay stops at this limit')
ON CONFLICT (key) DO NOTHING;
