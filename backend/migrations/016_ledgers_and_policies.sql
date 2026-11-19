-- ══════════════════════════════════════════════════════════════
-- 016: append-only ledgers (SSR 03) and two more policy rules
--
-- SSR 03 asks for an immutable stock ledger so inventory can't be quietly
-- edited. The money ledgers and the trust record get the same guarantee:
--   inventory_ledger, platform_ledger, trust_events   insert only
--   wallet_ledger   insert only, except that a card payout's reference and
--                   description are filled in once the gateway reports back
-- A correction is a new entry, never an edit. (TRUNCATE, used only to wipe a
-- development database, does not fire row triggers.)
--
-- Policies (SRDS §1.3 policy engine):
--   cancel_penalty_pct  share of the items a customer forfeits to the store
--                       when cancelling after the store accepted the order
--   low_stock_units     shelf units at or below which the store is told to restock
-- ══════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION forbid_ledger_change() RETURNS trigger AS $$
BEGIN
  RAISE EXCEPTION '% is append-only: % is not allowed', TG_TABLE_NAME, TG_OP
    USING ERRCODE = 'insufficient_privilege';
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION guard_wallet_ledger_update() RETURNS trigger AS $$
BEGIN
  IF (NEW.id, NEW.user_id, NEW.order_id, NEW.transaction_type, NEW.amount, NEW.balance_after, NEW.created_at)
     IS DISTINCT FROM
     (OLD.id, OLD.user_id, OLD.order_id, OLD.transaction_type, OLD.amount, OLD.balance_after, OLD.created_at) THEN
    RAISE EXCEPTION 'wallet_ledger is append-only: only reference and description can be filled in'
      USING ERRCODE = 'insufficient_privilege';
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS inventory_ledger_append_only ON inventory_ledger;
CREATE TRIGGER inventory_ledger_append_only BEFORE UPDATE OR DELETE ON inventory_ledger
  FOR EACH ROW EXECUTE FUNCTION forbid_ledger_change();

DROP TRIGGER IF EXISTS platform_ledger_append_only ON platform_ledger;
CREATE TRIGGER platform_ledger_append_only BEFORE UPDATE OR DELETE ON platform_ledger
  FOR EACH ROW EXECUTE FUNCTION forbid_ledger_change();

DROP TRIGGER IF EXISTS trust_events_append_only ON trust_events;
CREATE TRIGGER trust_events_append_only BEFORE UPDATE OR DELETE ON trust_events
  FOR EACH ROW EXECUTE FUNCTION forbid_ledger_change();

DROP TRIGGER IF EXISTS wallet_ledger_no_delete ON wallet_ledger;
CREATE TRIGGER wallet_ledger_no_delete BEFORE DELETE ON wallet_ledger
  FOR EACH ROW EXECUTE FUNCTION forbid_ledger_change();

DROP TRIGGER IF EXISTS wallet_ledger_guard_update ON wallet_ledger;
CREATE TRIGGER wallet_ledger_guard_update BEFORE UPDATE ON wallet_ledger
  FOR EACH ROW EXECUTE FUNCTION guard_wallet_ledger_update();

INSERT INTO policies (key, value, label, unit, description) VALUES
  ('cancel_penalty_pct', 10, 'Late cancellation fee', '%',
   'Share of the item subtotal paid to the store when a customer cancels after the store accepted (before packing). Cancelling a pending order is free.'),
  ('low_stock_units', 5, 'Low stock alert', 'units',
   'The store is told to restock a product when its free shelf units (shelf minus reserved) fall to this number or below')
ON CONFLICT (key) DO NOTHING;
