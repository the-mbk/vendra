// ══════════════════════════════════════════════════════════════
// Escrow settlement (FR03, FR04)
//
// Checkout puts the order total into the platform escrow pool. Then:
//   delivered  → rider payout leaves the pool at once (the job is done);
//                the rest stays held for the dispute window
//   release    → vendor gets subtotal − commission; platform keeps
//                commission + (delivery fee − rider payout)
//   split      → a dispute outcome: the customer gets refundPct % of the item
//                subtotal back, the vendor the rest (less commission on it)
//   refund     → everything still held goes back to the customer
// All amounts are integer paisa.
// ══════════════════════════════════════════════════════════════

const pool = require('../db');
const { lockEscrowRow, debitEscrowPool } = require('./escrowPool.service');
const { creditWallet } = require('./wallet.service');
const { getPolicies } = require('./policy.service');
const { notify, announceOrder } = require('./notification.service');
const { httpError, withTransaction } = require('../utils/http');
const { toPaisa, paisaToString, paisaToNumber, percentOf, formatRs, commissionBreakdown } = require('../utils/money');

async function lockOrder(client, orderId) {
  const r = await client.query('SELECT * FROM orders WHERE id = $1 FOR UPDATE', [orderId]);
  if (r.rows.length === 0) throw httpError(404, 'Order not found.');
  return r.rows[0];
}

/** Amount of this order still sitting in the escrow pool */
function heldPaisa(order) {
  return toPaisa(order.total_amount) - toPaisa(order.rider_payout);
}

/**
 * Once payment is settled the GPS trail is no longer needed as dispute evidence;
 * the trip distance and payout stay on the order. Keeps the database small.
 */
async function pruneTrip(client, orderId) {
  await client.query('DELETE FROM rider_locations WHERE order_id = $1', [orderId]);
}

/** Pays the rider out of the pool and records it on the order */
async function payRider(client, order, payoutPaisa) {
  if (payoutPaisa <= 0 || !order.rider_user_id) return;
  await lockEscrowRow(client);
  await debitEscrowPool(client, paisaToString(payoutPaisa));
  await creditWallet(client, {
    userId: order.rider_user_id,
    amountPaisa: payoutPaisa,
    type: 'rider_payout',
    orderId: order.id,
    description: `Delivery payout for Order #${order.id}`,
  });
  await client.query('UPDATE orders SET rider_payout = $1 WHERE id = $2', [paisaToString(payoutPaisa), order.id]);
}

/**
 * Starts the dispute window after delivery. With a zero window the escrow
 * is released straight away.
 */
async function scheduleEscrowRelease(client, afterCommit, orderId) {
  const { dispute_window_min: windowMin } = await getPolicies(client);
  await client.query(
    `UPDATE orders SET escrow_release_due_at = NOW() + ($1::numeric * INTERVAL '1 minute') WHERE id = $2`,
    [windowMin, orderId]
  );
  if (windowMin <= 0) await releaseEscrow(client, afterCommit, orderId);
}

/**
 * Pays the vendor out of escrow. `refundPct` (dispute "split" outcome) first returns
 * that share of the item subtotal to the customer; commission is only taken on what
 * the vendor actually receives.
 */
async function releaseEscrow(client, afterCommit, orderId, { note, allowFrom = ['held'], refundPct = 0 } = {}) {
  const order = await lockOrder(client, orderId);
  if (!allowFrom.includes(order.escrow_status)) {
    throw httpError(409, `Escrow for Order #${orderId} is already ${order.escrow_status}.`);
  }

  const { commission_pct: commissionPct } = await getPolicies(client);
  const held = heldPaisa(order);
  const subtotal = toPaisa(order.subtotal);
  const customerRefund = percentOf(subtotal, refundPct);
  const vendorGross = subtotal - customerRefund;
  const commission = percentOf(vendorGross, commissionPct);
  const vendorShare = vendorGross - commission;
  const deliveryMargin = held - subtotal; // delivery fee − rider payout

  await lockEscrowRow(client);
  await debitEscrowPool(client, paisaToString(held));

  if (customerRefund > 0) {
    await creditWallet(client, {
      userId: order.customer_id,
      amountPaisa: customerRefund,
      type: 'escrow_refund',
      orderId,
      description: `Partial refund (${Number(refundPct)}% of items) for Order #${orderId}`,
    });
  }

  const vendorUser = await client.query('SELECT user_id FROM vendors WHERE id = $1', [order.vendor_id]);
  const vendorUserId = vendorUser.rows[0].user_id;
  await creditWallet(client, {
    userId: vendorUserId,
    amountPaisa: vendorShare,
    type: 'escrow_release',
    orderId,
    description: `${note || `Escrow released for Order #${orderId}`}: ${commissionBreakdown(vendorGross, commissionPct, commission)}`,
  });

  const platformEntries = [['commission', commission], ['delivery_margin', deliveryMargin]];
  for (const [type, amount] of platformEntries) {
    if (amount !== 0) {
      await client.query(
        'INSERT INTO platform_ledger (order_id, entry_type, amount) VALUES ($1, $2, $3)',
        [orderId, type, paisaToString(amount)]
      );
    }
  }

  await client.query(
    `UPDATE orders SET escrow_status = 'released', escrow_settled_at = NOW(), updated_at = NOW() WHERE id = $1`,
    [orderId]
  );
  await pruneTrip(client, orderId);

  await notify(client, afterCommit, vendorUserId, {
    type: 'escrow_released',
    orderId,
    title: `Rs. ${paisaToString(vendorShare)} added to your wallet`,
    body: `Escrow for Order #${orderId} has been released.`,
  });
  await announceOrder(client, afterCommit, orderId, 'escrow_released');

  return {
    vendorSharePaisa: vendorShare,
    commissionPaisa: commission,
    deliveryMarginPaisa: deliveryMargin,
    vendorShare: paisaToNumber(vendorShare),
    commission: paisaToNumber(commission),
    customerRefund: paisaToNumber(customerRefund),
  };
}

/**
 * Returns what is still held to the customer. `storeFeePct` (a late cancellation,
 * policy cancel_penalty_pct) first pays that share of the item subtotal to the store
 * for the work already done; no commission is taken on it.
 */
async function refundEscrow(client, afterCommit, orderId, { note, allowFrom = ['held'], storeFeePct = 0 } = {}) {
  const order = await lockOrder(client, orderId);
  if (!allowFrom.includes(order.escrow_status)) {
    throw httpError(409, `Escrow for Order #${orderId} is already ${order.escrow_status}.`);
  }

  const held = heldPaisa(order);
  const storeFee = Math.min(held, percentOf(toPaisa(order.subtotal), storeFeePct));
  const refund = held - storeFee;
  await lockEscrowRow(client);
  await debitEscrowPool(client, paisaToString(held));
  if (refund > 0) {
    await creditWallet(client, {
      userId: order.customer_id,
      amountPaisa: refund,
      type: 'escrow_refund',
      orderId,
      description: note || `Escrow refund for Order #${orderId}`,
    });
  }
  if (storeFee > 0) {
    const vendorUserId = (await client.query('SELECT user_id FROM vendors WHERE id = $1', [order.vendor_id])).rows[0].user_id;
    await creditWallet(client, {
      userId: vendorUserId,
      amountPaisa: storeFee,
      type: 'escrow_release',
      orderId,
      description: `Late cancellation fee for Order #${orderId}: ${Number(storeFeePct)}% of items ${formatRs(toPaisa(order.subtotal))}`,
    });
  }
  await client.query(
    `UPDATE orders SET escrow_status = 'refunded', escrow_settled_at = NOW(), updated_at = NOW() WHERE id = $1`,
    [orderId]
  );
  await pruneTrip(client, orderId);
  return { refundPaisa: refund, refund: paisaToNumber(refund), storeFee: paisaToNumber(storeFee) };
}

/** Releases every delivered order whose dispute window has passed. Returns count released. */
async function releaseDueEscrows() {
  const due = await pool.query(
    `SELECT id FROM orders
     WHERE escrow_status = 'held' AND status = 'delivered' AND escrow_release_due_at <= NOW()
     ORDER BY escrow_release_due_at
     LIMIT 50`
  );
  let released = 0;
  for (const { id } of due.rows) {
    try {
      await withTransaction((client, afterCommit) => releaseEscrow(client, afterCommit, id));
      released++;
    } catch (err) {
      // Another worker or a dispute got there first — skip
      if (err.statusCode !== 409) console.error(`Escrow release failed for Order #${id}:`, err.message);
    }
  }
  return released;
}

module.exports = {
  lockOrder,
  heldPaisa,
  payRider,
  scheduleEscrowRelease,
  releaseEscrow,
  refundEscrow,
  releaseDueEscrows,
};
