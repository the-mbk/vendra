-- ══════════════════════════════════════════════════════════════
-- VENDRA: Migration 009 — pickup geofence + store location review
-- - The rider must be near the store to mark "arrived" or "picked up"
--   (pickup_geofence_m), as they must be near the customer to deliver.
-- - An approved store can't move itself: a new location is a request the
--   admin approves or rejects. Until then the store stays where it was.
-- ══════════════════════════════════════════════════════════════

INSERT INTO policies (key, value, label, unit, description) VALUES
    ('pickup_geofence_m', 200, 'Pickup geofence', 'm',
     'Rider must be within this distance of the store to mark arrived or picked up')
ON CONFLICT (key) DO NOTHING;

ALTER TABLE vendors
    ADD COLUMN IF NOT EXISTS pending_latitude DOUBLE PRECISION,
    ADD COLUMN IF NOT EXISTS pending_longitude DOUBLE PRECISION,
    ADD COLUMN IF NOT EXISTS pending_address TEXT,
    ADD COLUMN IF NOT EXISTS location_requested_at TIMESTAMPTZ,
    -- Why the last request was rejected (cleared by the next request)
    ADD COLUMN IF NOT EXISTS location_rejection_reason TEXT;

CREATE INDEX IF NOT EXISTS idx_vendors_location_requests
    ON vendors (location_requested_at) WHERE location_requested_at IS NOT NULL;
