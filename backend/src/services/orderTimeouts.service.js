// ══════════════════════════════════════════════════════════════
// Orders that stall are cancelled and refunded, so stock and escrow
// are never held forever:
//   pending           the store hasn't accepted within vendor_accept_timeout_min
//   ready_for_pickup  a delivery order no rider has accepted within rider_assign_timeout_min
// ══════════════════════════════════════════════════════════════

const pool = require('../db');
const { releaseOrderLocks } = require('./inventory.service');
const { refundEscrow } = require('./orderSettlement.service');
const { announceOrder } = require('./notification.service');
const { getPolicies } = require('./policy.service');
const { withTransaction } = require('../utils/http');

const STALE_PENDING = `status = 'pending' AND created_at <= NOW() - ($1::numeric * INTERVAL '1 minute')`;
const STALE_READY = `status = 'ready_for_pickup' AND delivery_type = 'delivery' AND rider_user_id IS NULL
                     AND ready_at <= NOW() - ($2::numeric * INTERVAL '1 minute')`;

const REASONS = {
  pending: {
    reason: "Store didn't respond in time",
    customer: (id, refund) => ({ title: `Order #${id} cancelled`, body: `The store didn't accept it in time. Rs. ${refund.toFixed(2)} refunded to your wallet.` }),
    vendor: (id) => ({ title: `Order #${id} expired`, body: 'It was not accepted in time, so it was cancelled and the customer refunded.' }),
  },
  ready_for_pickup: {
    reason: 'No rider available',
    customer: (id, refund) => ({ title: `Order #${id} cancelled`, body: `No rider was available to deliver it. Rs. ${refund.toFixed(2)} refunded to your wallet.` }),
    vendor: (id) => ({ title: `Order #${id} cancelled`, body: 'No rider accepted it in time. Reserved stock is back on sale.' }),
  },
};

/** @returns {Promise<number>} orders cancelled */
async function cancelStaleOrders() {
  const p = await getPolicies();
  const minutes = [p.vendor_accept_timeout_min, p.rider_assign_timeout_min];
  const due = await pool.query(
    `SELECT id FROM orders WHERE (${STALE_PENDING}) OR (${STALE_READY}) ORDER BY id LIMIT 50`,
    minutes
  );

  let cancelled = 0;
  for (const { id } of due.rows) {
    const done = await withTransaction(async (client, afterCommit) => {
      // Re-check under the order lock: the store or a rider may have acted meanwhile
      const order = (await client.query(
        `SELECT id, status FROM orders WHERE id = $3 AND ((${STALE_PENDING}) OR (${STALE_READY})) FOR UPDATE`,
        [...minutes, id]
      )).rows[0];
      if (!order) return false;
      const text = REASONS[order.status];
      await releaseOrderLocks(client, afterCommit, id, `Order cancelled automatically: ${text.reason}`);
      await client.query(
        `UPDATE orders SET status = 'cancelled', cancellation_reason = $2, updated_at = NOW() WHERE id = $1`,
        [id, text.reason]
      );
      const { refund } = await refundEscrow(client, afterCommit, id, { note: `Escrow refund for Order #${id}: ${text.reason.toLowerCase()}` });
      await announceOrder(client, afterCommit, id, 'order_cancelled', {
        customer: text.customer(id, refund),
        vendor: text.vendor(id),
      });
      return true;
    }).catch((err) => {
      console.error(`Auto-cancel of Order #${id} failed:`, err.message);
      return false;
    });
    if (done) cancelled++;
  }
  return cancelled;
}

module.exports = { cancelStaleOrders };
