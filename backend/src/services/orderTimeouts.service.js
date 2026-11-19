// ══════════════════════════════════════════════════════════════
// Orders that stall are cancelled and refunded, so stock and escrow
// are never held forever:
//   pending           the store hasn't accepted within vendor_accept_timeout_min
//   ready_for_pickup  a delivery order no rider has accepted within rider_assign_timeout_min
//                     (counted again from when a lapsed rider lost it)
// Task hoarding guards: a rider who accepted a delivery but hasn't reached
// the store within rider_pickup_timeout_min, or reached it but hasn't
// collected the order within rider_store_wait_max_min of arriving, loses it;
// it goes back to the other riders and counts against the rider (trust_events).
// ══════════════════════════════════════════════════════════════

const pool = require('../db');
const { releaseOrderLocks } = require('./inventory.service');
const { refundEscrow } = require('./orderSettlement.service');
const { announceOrder, notify } = require('./notification.service');
const { getPolicies } = require('./policy.service');
const { broadcastTask } = require('./riderDispatch.service');
const { recordTrustEvent } = require('./trust.service');
const { emitToUser } = require('../realtime');
const { withTransaction } = require('../utils/http');

const STALE_PENDING = `status = 'pending' AND created_at <= NOW() - ($1::numeric * INTERVAL '1 minute')`;
const STALE_READY = `status = 'ready_for_pickup' AND delivery_type = 'delivery' AND rider_user_id IS NULL
                     AND GREATEST(ready_at, rider_released_at) <= NOW() - ($2::numeric * INTERVAL '1 minute')`;
const IDLE_RIDER = `status = 'ready_for_pickup' AND delivery_type = 'delivery' AND rider_user_id IS NOT NULL
                    AND rider_arrived_at IS NULL AND assigned_at <= NOW() - ($1::numeric * INTERVAL '1 minute')`;
// Arrived, then sat at the store without collecting (the store had marked it ready)
const STALLED_RIDER = `status = 'ready_for_pickup' AND delivery_type = 'delivery' AND rider_user_id IS NOT NULL
                       AND rider_arrived_at <= NOW() - ($1::numeric * INTERVAL '1 minute')`;

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

const RELEASES = {
  // Accepted but never reached the store
  idle: {
    condition: IDLE_RIDER,
    policy: 'rider_pickup_timeout_min',
    rider: (id, min) => ({ title: `Delivery #${id} reassigned`, body: `You didn't reach the store within ${min} min, so it went back to other riders.` }),
    customer: (id) => ({ title: `Finding a new rider for Order #${id}`, body: 'Your rider was delayed, so the delivery was offered to riders nearby.' }),
    vendor: (id) => ({ title: `Order #${id} back in the rider pool`, body: 'The assigned rider never arrived. Another rider will collect it.' }),
  },
  // Arrived but didn't collect: no waiting pay, no delivery
  stalled: {
    condition: STALLED_RIDER,
    policy: 'rider_store_wait_max_min',
    rider: (id, min) => ({ title: `Delivery #${id} reassigned`, body: `You didn't collect it within ${min} min of arriving, so it went back to other riders. No waiting pay is due.` }),
    customer: (id) => ({ title: `Finding a new rider for Order #${id}`, body: "Your rider didn't collect the order in time, so it was offered to riders nearby." }),
    vendor: (id, min) => ({ title: `Order #${id} back in the rider pool`, body: `The rider waited over ${min} min without collecting. Keep the parcel ready: another rider will come.` }),
  },
};

/**
 * Takes deliveries back from riders who accepted them but never reached the
 * store, or reached it and then didn't collect within the store wait limit.
 * @returns {Promise<number>} deliveries put back in the pool
 */
async function releaseIdleRiders() {
  const policies = await getPolicies();
  let released = 0;
  for (const rule of Object.values(RELEASES)) {
    const minutes = policies[rule.policy];
    if (!(minutes > 0)) continue;
    const due = await pool.query(`SELECT id FROM orders WHERE ${rule.condition} ORDER BY id LIMIT 50`, [minutes]);
    for (const { id } of due.rows) {
      if (await releaseRider(id, rule, minutes)) released++;
    }
  }
  return released;
}

async function releaseRider(id, rule, minutes) {
  return withTransaction(async (client, afterCommit) => {
    const order = (await client.query(`SELECT * FROM orders WHERE id = $2 AND ${rule.condition} FOR UPDATE`, [minutes, id])).rows[0];
    if (!order) return false;
    const riderId = order.rider_user_id;
    await client.query(
      `UPDATE orders SET rider_user_id = NULL, assigned_at = NULL, rider_arrived_at = NULL,
              rider_released_at = NOW(), updated_at = NOW()
       WHERE id = $1`,
      [id]
    );
    await client.query('UPDATE riders SET is_available = true WHERE user_id = $1', [riderId]);
    await recordTrustEvent(client, { kind: 'rider_task_timeout', orderId: id, vendorId: order.vendor_id, userId: riderId });

    await notify(client, afterCommit, riderId, { type: 'task_released', orderId: id, ...rule.rider(id, minutes) });
    afterCommit.push(() => emitToUser(riderId, 'order:update', { orderId: id, status: order.status, escrowStatus: order.escrow_status, riderUserId: null }));
    await announceOrder(client, afterCommit, id, 'rider_released', {
      customer: rule.customer(id, minutes),
      vendor: rule.vendor(id, minutes),
    });
    await broadcastTask(client, afterCommit, order, { exceptUserId: riderId });
    return true;
  }).catch((err) => {
    console.error(`Releasing the rider from Order #${id} failed:`, err.message);
    return false;
  });
}

module.exports = { cancelStaleOrders, releaseIdleRiders };
