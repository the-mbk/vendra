-- ══════════════════════════════════════════════════════════════
-- VENDRA: Migration 013 — store pictures
-- A store has a logo (square, shown next to its name) and a cover
-- photo (wide, the banner on its store page and store cards). Both are
-- public files under /uploads/products, like product photos, uploaded by
-- the store owner from the vendor app. Without one, the apps show the
-- store's initials (logo) or its brand colours (cover).
-- ══════════════════════════════════════════════════════════════

ALTER TABLE vendors ADD COLUMN IF NOT EXISTS logo_url TEXT;
ALTER TABLE vendors ADD COLUMN IF NOT EXISTS cover_url TEXT;
