// ══════════════════════════════════════════════════════════════
// Notifications (FR09) — stored in `notifications` and pushed over
// Socket.IO after the surrounding transaction commits.
// ══════════════════════════════════════════════════════════════

const realtime = require('../realtime');

function formatNotification(n) {
  return {
    id: n.id,
    type: n.type,
    title: n.title,
    body: n.body,
    orderId: n.order_id,
    isRead: n.is_read,
    createdAt: n.created_at,
  };
}

async function notify(client, afterCommit, userId, { type, title, body = null, orderId = null }) {
  if (!userId) return;
  const r = await client.query(
    `INSERT INTO notifications (user_id, type, title, body, order_id)
     VALUES ($1, $2, $3, $4, $5) RETURNING *`,
    [userId, type, title, body, orderId]
  );
  const payload = formatNotification(r.rows[0]);
  afterCommit.push(() => realtime.emitToUser(userId, 'notification', payload));
}

async function notifyAdmins(client, afterCommit, message) {
  const admins = await client.query(`SELECT id FROM users WHERE role = 'admin'`);
  for (const a of admins.rows) await notify(client, afterCommit, a.id, message);
}

async function orderParties(client, orderId) {
  const r = await client.query(
    `SELECT o.id, o.status, o.escrow_status, o.customer_id, o.rider_user_id, o.vendor_id,
            v.user_id AS vendor_user_id, v.store_name
     FROM orders o JOIN vendors v ON v.id = o.vendor_id
     WHERE o.id = $1`,
    [orderId]
  );
  return r.rows[0];
}

/**
 * Notifies the parties of an order and pushes an `order:update` event to each.
 * messages: { customer?, vendor?, rider? } each { title, body }
 */
async function announceOrder(client, afterCommit, orderId, type, messages = {}) {
  const o = await orderParties(client, orderId);
  if (!o) return;

  const targets = {
    customer: o.customer_id,
    vendor: o.vendor_user_id,
    rider: o.rider_user_id,
  };
  for (const [role, userId] of Object.entries(targets)) {
    if (messages[role] && userId) {
      await notify(client, afterCommit, userId, { type, orderId, ...messages[role] });
    }
  }

  const update = { orderId: o.id, status: o.status, escrowStatus: o.escrow_status, riderUserId: o.rider_user_id };
  afterCommit.push(() => {
    realtime.emitToUser(o.customer_id, 'order:update', update);
    realtime.emitToVendor(o.vendor_id, 'order:update', update);
    if (o.rider_user_id) realtime.emitToUser(o.rider_user_id, 'order:update', update);
    realtime.emitToAdmins('order:update', update);
  });
  return o;
}

module.exports = { notify, notifyAdmins, announceOrder, formatNotification, orderParties };
