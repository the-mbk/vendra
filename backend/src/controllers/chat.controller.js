// ══════════════════════════════════════════════════════════════
// Vendra Backend - Order chat (customer ↔ assigned rider)
// "Gate code is 402", "I'm outside the main gate": the two can talk without
// either seeing the other's phone number. Open while the rider is on the
// delivery (ready_for_pickup → on_the_way); afterwards the thread is
// read-only and stays as dispute evidence (the admin order view shows it).
//   GET  /api/orders/:id/messages          → { open, messages: [...], with }
//        with: who you're talking to — { role, name (short), photoUrl, phone
//        (only while the delivery is open), vehicleType (riders) } — so either
//        side knows who to name if they report the conversation.
//   POST /api/orders/:id/messages { body } → the new message (201)
// The other side gets it live as 'chat:message'.
// ══════════════════════════════════════════════════════════════

const pool = require('../db');
const { emitToUser } = require('../realtime');
const { httpError, asyncHandler, intParam } = require('../utils/http');
const { shortName, contactWhile } = require('../utils/privacy');

const OPEN_STATUSES = ['ready_for_pickup', 'picked', 'on_the_way'];
const MAX_LENGTH = 500;

/** The order and the caller's side of it, or 404 for anyone else */
async function chatParty(orderId, userId) {
  const o = (await pool.query(
    'SELECT id, status, delivery_type, customer_id, rider_user_id FROM orders WHERE id = $1', [orderId]
  )).rows[0];
  const role = o?.customer_id === userId ? 'customer' : o?.rider_user_id && o.rider_user_id === userId ? 'rider' : null;
  if (!o || !role || o.delivery_type !== 'delivery') throw httpError(404, 'Order not found.');
  const open = Boolean(o.rider_user_id) && OPEN_STATUSES.includes(o.status);
  return { order: o, role, open, otherUserId: role === 'customer' ? o.rider_user_id : o.customer_id };
}

const messageView = (m) => ({
  id: m.id,
  orderId: m.order_id,
  senderRole: m.sender_role,
  body: m.body,
  createdAt: m.created_at,
});

/**
 * Messages of one order. A rider only sees messages from their own time on the
 * order: a delivery handed to another rider doesn't carry the old conversation.
 */
async function listMessages(orderId, riderUserId = null) {
  const r = await pool.query(
    `SELECT * FROM order_messages
     WHERE order_id = $1 AND ($2::int IS NULL OR sender_role = 'customer' OR sender_user_id = $2)
     ORDER BY id`,
    [orderId, riderUserId]
  );
  return r.rows.map(messageView);
}

/** The other person on the delivery, as much as the caller may see */
async function counterpart(order, otherUserId, role) {
  if (!otherUserId) return null;
  const u = (await pool.query(
    `SELECT u.full_name, u.phone, u.avatar_url, r.vehicle_type
     FROM users u LEFT JOIN riders r ON r.user_id = u.id WHERE u.id = $1`,
    [otherUserId]
  )).rows[0];
  if (!u) return null;
  const isRider = role === 'customer';
  return {
    role: isRider ? 'rider' : 'customer',
    name: shortName(u.full_name, isRider ? 'Your rider' : 'Customer'),
    photoUrl: u.avatar_url || null,
    phone: contactWhile(order.status, u.phone),
    vehicleType: isRider ? u.vehicle_type || null : null,
  };
}

const getMessages = asyncHandler(async (req, res) => {
  const { order, role, open, otherUserId } = await chatParty(intParam(req.params.id), req.user.userId);
  const [messages, other] = await Promise.all([
    listMessages(order.id, role === 'rider' ? req.user.userId : null),
    counterpart(order, otherUserId, role),
  ]);
  res.json({ success: true, data: { open, messages, with: other } });
});

const postMessage = asyncHandler(async (req, res) => {
  const { order, role, open, otherUserId } = await chatParty(intParam(req.params.id), req.user.userId);
  if (!open) {
    throw httpError(409, 'Chat is open only while a rider is on this delivery.', { code: 'CHAT_CLOSED' });
  }
  const body = typeof req.body.body === 'string' ? req.body.body.trim() : '';
  if (!body) throw httpError(400, 'Write a message first.');
  if (body.length > MAX_LENGTH) throw httpError(400, `Keep messages to ${MAX_LENGTH} characters.`);

  const m = (await pool.query(
    `INSERT INTO order_messages (order_id, sender_user_id, sender_role, body) VALUES ($1, $2, $3, $4) RETURNING *`,
    [order.id, req.user.userId, role, body]
  )).rows[0];
  const view = messageView(m);
  emitToUser(otherUserId, 'chat:message', view);
  res.status(201).json({ success: true, data: view });
});

module.exports = { getMessages, postMessage, listMessages };
