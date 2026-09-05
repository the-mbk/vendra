// ══════════════════════════════════════════════════════════════
// Release escrow pool funds to vendor wallet when order completes
// ══════════════════════════════════════════════════════════════

const { lockEscrowRow, debitEscrowPool } = require('./escrowPool.service');

/**
 * @param {import('pg').PoolClient} client — active transaction
 * @param {number} orderId
 * @param {number} vendorId
 * @param {string} ledgerNote
 */
async function payoutVendorFromEscrow(client, orderId, vendorId, ledgerNote) {
  await lockEscrowRow(client);

  const orderCheck = await client.query(
    'SELECT id, total_amount FROM orders WHERE id = $1 AND vendor_id = $2 FOR UPDATE',
    [orderId, vendorId]
  );
  if (orderCheck.rows.length === 0) {
    const err = new Error('Order not found');
    err.statusCode = 404;
    throw err;
  }

  const totalAmount = parseFloat(orderCheck.rows[0].total_amount);
  await debitEscrowPool(client, totalAmount);

  const vendorUserRes = await client.query('SELECT user_id FROM vendors WHERE id = $1', [vendorId]);
  const vendorUserId = vendorUserRes.rows[0].user_id;

  const userWalletRes = await client.query(
    'SELECT wallet_balance FROM users WHERE id = $1 FOR UPDATE',
    [vendorUserId]
  );
  const walletBalance = parseFloat(userWalletRes.rows[0].wallet_balance);
  const newBalance = walletBalance + totalAmount;

  await client.query('UPDATE users SET wallet_balance = $1 WHERE id = $2', [newBalance, vendorUserId]);

  await client.query(
    `INSERT INTO wallet_ledger (user_id, order_id, transaction_type, amount, balance_after, description)
     VALUES ($1, $2, 'escrow_release', $3, $4, $5)`,
    [vendorUserId, orderId, totalAmount, newBalance, ledgerNote]
  );

  return { vendorUserId, totalAmount, vendorWalletBalanceAfter: newBalance };
}

module.exports = { payoutVendorFromEscrow };
