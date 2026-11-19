// ══════════════════════════════════════════════════════════════
// Trust events — the anti-abuse audit trail (migration 015).
// Each gate that blocks or overrides something records who it counts
// against; the admin sees the 30-day counts on the store, on the rider
// and in a dispute dossier.
// ══════════════════════════════════════════════════════════════

const KINDS = ['walk_in_override', 'rider_task_timeout', 'handover_lockout'];
const WINDOW_DAYS = 30;

/** Records one event inside the caller's transaction */
async function recordTrustEvent(db, { kind, orderId, vendorId, userId = null }) {
  if (!KINDS.includes(kind)) throw new Error(`Unknown trust event "${kind}"`);
  await db.query(
    'INSERT INTO trust_events (kind, order_id, vendor_id, user_id) VALUES ($1, $2, $3, $4)',
    [kind, orderId, vendorId, userId]
  );
}

/**
 * SQL for a 30-day count of one kind, correlated to an outer column,
 * e.g. trustCountSql('walk_in_override', 'vendor_id', 'v.id').
 */
function trustCountSql(kind, column, outer) {
  if (!KINDS.includes(kind) || !['vendor_id', 'user_id'].includes(column)) throw new Error('Bad trust count');
  return `(SELECT COUNT(*)::int FROM trust_events te
           WHERE te.kind = '${kind}' AND te.${column} = ${outer}
             AND te.created_at >= NOW() - INTERVAL '${WINDOW_DAYS} days')`;
}

module.exports = { recordTrustEvent, trustCountSql, TRUST_WINDOW_DAYS: WINDOW_DAYS };
