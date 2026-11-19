-- ══════════════════════════════════════════════════════════════
-- 017: delivery notes, order chat, admin audit trail
--
-- delivery_note   what the customer wants the rider to know ("gate code 402"),
--                 written at checkout, shown to the assigned rider only
-- order_messages  customer ↔ assigned rider chat for one delivery, so neither
--                 needs the other's phone number. Writable only while the
--                 delivery is in progress; kept read-only afterwards as evidence.
-- admin_audit_log who did what in the admin panel (approvals, policy changes,
--                 dispute rulings, manual settlements). Append-only, like the
--                 other ledgers (migration 016).
-- ══════════════════════════════════════════════════════════════

ALTER TABLE orders ADD COLUMN IF NOT EXISTS delivery_note VARCHAR(200);

CREATE TABLE IF NOT EXISTS order_messages (
    id SERIAL PRIMARY KEY,
    order_id INTEGER NOT NULL REFERENCES orders(id),
    sender_user_id INTEGER NOT NULL REFERENCES users(id),
    sender_role VARCHAR(10) NOT NULL CHECK (sender_role IN ('customer', 'rider')),
    body VARCHAR(500) NOT NULL CHECK (length(btrim(body)) > 0),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS order_messages_order_idx ON order_messages (order_id, id);

CREATE TABLE IF NOT EXISTS admin_audit_log (
    id SERIAL PRIMARY KEY,
    admin_user_id INTEGER REFERENCES users(id),
    action VARCHAR(40) NOT NULL,
    target_type VARCHAR(20) NOT NULL,
    target_id INTEGER,
    summary VARCHAR(300) NOT NULL,
    details JSONB,
    ip_address VARCHAR(64),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS admin_audit_log_created_idx ON admin_audit_log (created_at DESC, id DESC);
CREATE INDEX IF NOT EXISTS admin_audit_log_target_idx ON admin_audit_log (target_type, target_id);

DROP TRIGGER IF EXISTS order_messages_append_only ON order_messages;
CREATE TRIGGER order_messages_append_only BEFORE UPDATE OR DELETE ON order_messages
  FOR EACH ROW EXECUTE FUNCTION forbid_ledger_change();

DROP TRIGGER IF EXISTS admin_audit_log_append_only ON admin_audit_log;
CREATE TRIGGER admin_audit_log_append_only BEFORE UPDATE OR DELETE ON admin_audit_log
  FOR EACH ROW EXECUTE FUNCTION forbid_ledger_change();
