// ══════════════════════════════════════════════════════════════
// Policy engine — admin-editable business rules stored in `policies`.
// Read on every use (no cache) so admin changes apply without a redeploy.
// ══════════════════════════════════════════════════════════════

const pool = require('../db');

/** @returns {Promise<Record<string, number>>} */
async function getPolicies(db = pool) {
  const r = await db.query('SELECT key, value FROM policies');
  const map = {};
  for (const row of r.rows) map[row.key] = Number(row.value);
  return map;
}

async function getPolicy(db, key) {
  const r = await db.query('SELECT value FROM policies WHERE key = $1', [key]);
  if (r.rows.length === 0) throw new Error(`Policy "${key}" is not configured`);
  return Number(r.rows[0].value);
}

async function listPolicies(db = pool) {
  const r = await db.query(
    `SELECT key, value, label, unit, description, updated_at FROM policies ORDER BY key`
  );
  return r.rows.map((p) => ({
    key: p.key,
    value: Number(p.value),
    label: p.label,
    unit: p.unit,
    description: p.description,
    updatedAt: p.updated_at,
  }));
}

module.exports = { getPolicies, getPolicy, listPolicies };
