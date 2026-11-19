// ══════════════════════════════════════════════════════════════
// Admin audit trail: who approved this store, who changed the commission,
// who ruled on this dispute. One row per admin action, written in the same
// transaction as the action itself (so a rolled-back action leaves no
// entry), and append-only at the database level (migration 017).
// ══════════════════════════════════════════════════════════════

/** Actions recorded, for the admin's filter */
const AUDIT_ACTIONS = Object.freeze([
  'vendor_approved', 'vendor_disapproved', 'location_approved', 'location_rejected',
  'product_approved', 'product_hidden', 'policy_changed', 'rider_approved', 'rider_rejected',
  'dispute_resolved', 'password_reset', 'escrow_settled',
]);

/**
 * @param db      client inside the action's transaction (or the pool)
 * @param req     the admin's request (who and from where)
 * @param entry   { action, targetType, targetId?, summary, details? }
 */
async function recordAudit(db, req, { action, targetType, targetId = null, summary, details = null }) {
  if (!AUDIT_ACTIONS.includes(action)) throw new Error(`Unknown audit action "${action}"`);
  await db.query(
    `INSERT INTO admin_audit_log (admin_user_id, action, target_type, target_id, summary, details, ip_address)
     VALUES ($1, $2, $3, $4, $5, $6, $7)`,
    [req.user.userId, action, targetType, targetId, summary.slice(0, 300), details ? JSON.stringify(details) : null,
      (req.ip || '').slice(0, 64) || null]
  );
}

module.exports = { recordAudit, AUDIT_ACTIONS };
