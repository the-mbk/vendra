// ══════════════════════════════════════════════════════════════
// Wallets — balance arithmetic happens in SQL, never in JS floats.
// Amounts are integer paisa (see utils/money.js).
// ══════════════════════════════════════════════════════════════

const { httpError } = require('../utils/http');
const { paisaToString, toPaisa } = require('../utils/money');

/** @returns {Promise<number>} the ledger row id */
async function writeLedger(client, { userId, orderId, type, amountPaisa, balanceAfter, description, reference }) {
  const r = await client.query(
    `INSERT INTO wallet_ledger (user_id, order_id, transaction_type, amount, balance_after, description, reference)
     VALUES ($1, $2, $3, $4, $5, $6, $7) RETURNING id`,
    [userId, orderId || null, type, paisaToString(amountPaisa), balanceAfter, description, reference || null]
  );
  return r.rows[0].id;
}

// `reference` is the gateway id (pi_… / po_…) for card money movements.

/** @returns {Promise<number>} balance after, in paisa */
async function creditWallet(client, { userId, amountPaisa, type, orderId, description, reference }) {
  const r = await client.query(
    'UPDATE users SET wallet_balance = wallet_balance + $1 WHERE id = $2 RETURNING wallet_balance',
    [paisaToString(amountPaisa), userId]
  );
  if (r.rows.length === 0) throw httpError(404, 'Wallet owner not found.');
  const balanceAfter = r.rows[0].wallet_balance;
  await writeLedger(client, { userId, orderId, type, amountPaisa, balanceAfter, description, reference });
  return toPaisa(balanceAfter);
}

/**
 * Debits only if the balance covers it; otherwise throws 400 with the shortfall
 * @returns {Promise<number>} balance after, in paisa (pass onLedger to get the ledger row id)
 */
async function debitWallet(client, { userId, amountPaisa, type, orderId, description, reference, onLedger }) {
  const r = await client.query(
    `UPDATE users SET wallet_balance = wallet_balance - $1
     WHERE id = $2 AND wallet_balance >= $1
     RETURNING wallet_balance`,
    [paisaToString(amountPaisa), userId]
  );
  if (r.rows.length === 0) {
    const bal = await client.query('SELECT wallet_balance FROM users WHERE id = $1', [userId]);
    const have = bal.rows[0] ? Number(bal.rows[0].wallet_balance) : 0;
    throw httpError(
      400,
      `Insufficient wallet balance. Total is Rs. ${paisaToString(amountPaisa)} but you have Rs. ${have.toFixed(2)}.`,
      { code: 'INSUFFICIENT_BALANCE' }
    );
  }
  const balanceAfter = r.rows[0].wallet_balance;
  const ledgerId = await writeLedger(client, { userId, orderId, type, amountPaisa, balanceAfter, description, reference });
  onLedger?.(ledgerId);
  return toPaisa(balanceAfter);
}

module.exports = { creditWallet, debitWallet };
