// ══════════════════════════════════════════════════════════════
// Platform escrow pool — single ledger row for all held order funds
// Customer checkout credits pool; refunds debit pool; vendor pickup releases.
// ══════════════════════════════════════════════════════════════

const pool = require('../db');

const ESCROW_ROW_ID = 1;

async function ensureEscrowRow(client) {
  await client.query(
    `INSERT INTO platform_escrow_wallet (id, balance) VALUES ($1, 0) ON CONFLICT (id) DO NOTHING`,
    [ESCROW_ROW_ID]
  );
}

/** Call inside a transaction before updating pool balance */
async function lockEscrowRow(client) {
  await ensureEscrowRow(client);
  await client.query('SELECT balance FROM platform_escrow_wallet WHERE id = $1 FOR UPDATE', [ESCROW_ROW_ID]);
}

async function creditEscrowPool(client, amount) {
  await ensureEscrowRow(client);
  const r = await client.query(
    'UPDATE platform_escrow_wallet SET balance = balance + $1 WHERE id = $2 RETURNING balance',
    [amount, ESCROW_ROW_ID]
  );
  return parseFloat(r.rows[0].balance);
}

async function debitEscrowPool(client, amount) {
  await ensureEscrowRow(client);
  const r = await client.query(
    'UPDATE platform_escrow_wallet SET balance = balance - $1 WHERE id = $2 AND balance >= $1 RETURNING balance',
    [amount, ESCROW_ROW_ID]
  );
  if (r.rows.length === 0) {
    const err = new Error('Escrow pool balance insufficient for this operation');
    err.code = 'ESCROW_POOL_UNDERFLOW';
    throw err;
  }
  return parseFloat(r.rows[0].balance);
}

async function getEscrowPoolBalanceReadOnly() {
  try {
    const r = await pool.query('SELECT balance FROM platform_escrow_wallet WHERE id = $1', [ESCROW_ROW_ID]);
    if (r.rows.length === 0) return 0;
    return parseFloat(r.rows[0].balance);
  } catch (e) {
    if (e.code === '42P01') return 0;
    throw e;
  }
}

module.exports = {
  lockEscrowRow,
  creditEscrowPool,
  debitEscrowPool,
  getEscrowPoolBalanceReadOnly,
};
