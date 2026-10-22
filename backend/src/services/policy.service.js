// ══════════════════════════════════════════════════════════════
// Policy engine — admin-editable business rules stored in `policies`.
// Read on every use (no cache) so admin changes apply without a redeploy.
// In development mode (fastTimers) timing policies are capped at a few
// minutes so a whole order cycle fits in a demo; the stored value is kept.
// ══════════════════════════════════════════════════════════════

const pool = require('../db');
const { FEATURES, FAST_TIMER_CAPS } = require('../config/mode');

/** The value actually used for a policy */
function effective(key, value) {
  const cap = FEATURES.fastTimers ? FAST_TIMER_CAPS[key] : undefined;
  return cap === undefined ? value : Math.min(value, cap);
}

/** @returns {Promise<Record<string, number>>} effective values */
async function getPolicies(db = pool) {
  const r = await db.query('SELECT key, value FROM policies');
  const map = {};
  for (const row of r.rows) map[row.key] = effective(row.key, Number(row.value));
  return map;
}

async function getPolicy(db, key) {
  const r = await db.query('SELECT value FROM policies WHERE key = $1', [key]);
  if (r.rows.length === 0) throw new Error(`Policy "${key}" is not configured`);
  return effective(key, Number(r.rows[0].value));
}

async function listPolicies(db = pool) {
  const r = await db.query(
    `SELECT key, value, label, unit, description, updated_at FROM policies ORDER BY key`
  );
  return r.rows.map((p) => ({
    key: p.key,
    value: Number(p.value),
    // Differs from value only in development mode, where fast timers cap it
    effectiveValue: effective(p.key, Number(p.value)),
    label: p.label,
    unit: p.unit,
    description: p.description,
    updatedAt: p.updated_at,
  }));
}

module.exports = { getPolicies, getPolicy, listPolicies };
