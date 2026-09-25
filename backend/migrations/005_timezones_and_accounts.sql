-- ══════════════════════════════════════════════════════════════
-- VENDRA: Migration 005 — Time zones + account recovery
-- 1. Every TIMESTAMP column becomes TIMESTAMPTZ, so instants are stored
--    unambiguously whatever time zone the database server runs in.
--    Existing values are read in the zone they were written in (this
--    session's TimeZone, i.e. the server default the app used until now).
-- 2. Temporary passwords set by an admin must be changed at next login.
-- ══════════════════════════════════════════════════════════════

DO $$
DECLARE
    col RECORD;
BEGIN
    FOR col IN
        SELECT table_name, column_name
        FROM information_schema.columns
        WHERE table_schema = 'public'
          AND data_type = 'timestamp without time zone'
    LOOP
        EXECUTE format(
            'ALTER TABLE %I ALTER COLUMN %I TYPE TIMESTAMPTZ USING %I AT TIME ZONE %L',
            col.table_name, col.column_name, col.column_name, current_setting('TimeZone')
        );
    END LOOP;
END $$;

ALTER TABLE users ADD COLUMN IF NOT EXISTS must_change_password BOOLEAN NOT NULL DEFAULT false;
ALTER TABLE users ADD COLUMN IF NOT EXISTS password_changed_at TIMESTAMPTZ;
