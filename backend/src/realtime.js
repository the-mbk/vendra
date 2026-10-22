// ══════════════════════════════════════════════════════════════
// Vendra Backend - Realtime (Socket.IO)
// Clients connect with { auth: { token } } and are placed in rooms:
//   user:<id>  vendor:<vendorId>  riders  admins
// Anonymous clients still receive public stock updates.
//
// Live tracking: a customer may have several deliveries on the road, each
// rider pinging every 10 s. The app watches one order at a time:
//   emit('track:order', { orderId }, ack)  → joins track:<orderId> (owner only)
//   emit('untrack:order')                  → leaves it
// Rider pings go only to that room, so orders nobody is looking at send nothing.
// ══════════════════════════════════════════════════════════════

const { Server } = require('socket.io');
const jwt = require('jsonwebtoken');
const { corsOrigin } = require('./utils/cors');
const pool = require('./db');

let io = null;

function initRealtime(httpServer) {
  io = new Server(httpServer, {
    cors: { origin: corsOrigin, credentials: true },
  });

  io.use((socket, next) => {
    const token = socket.handshake.auth?.token || socket.handshake.query?.token;
    if (!token) {
      socket.data.user = null;
      return next();
    }
    try {
      const decoded = jwt.verify(token, process.env.JWT_SECRET);
      socket.data.user = { userId: decoded.userId, role: decoded.role, vendorId: decoded.vendorId || null };
      next();
    } catch {
      next(new Error('Invalid token'));
    }
  });

  io.on('connection', (socket) => {
    const user = socket.data.user;
    if (!user) return;
    socket.join(`user:${user.userId}`);
    if (user.role === 'vendor' && user.vendorId) socket.join(`vendor:${user.vendorId}`);
    if (user.role === 'rider') socket.join('riders');
    if (user.role === 'admin') socket.join('admins');
    if (user.role === 'customer' || user.role === 'admin') {
      socket.on('track:order', (payload, ack) => trackOrder(socket, payload, ack));
      socket.on('untrack:order', (_payload, ack) => {
        untrack(socket);
        if (typeof ack === 'function') ack({ ok: true });
      });
    }
  });

  return io;
}

/** Leaves the order this socket was watching, if any */
function untrack(socket) {
  if (socket.data.trackedOrderId) socket.leave(`track:${socket.data.trackedOrderId}`);
  socket.data.trackedOrderId = null;
}

/** Watch one order's rider (replaces the previous one). Customers may only watch their own orders. */
async function trackOrder(socket, payload, ack) {
  const reply = typeof ack === 'function' ? ack : () => {};
  const orderId = Number(payload?.orderId);
  if (!Number.isInteger(orderId) || orderId <= 0) return reply({ ok: false, error: 'orderId is required' });
  try {
    const { userId, role } = socket.data.user;
    const r = await pool.query('SELECT customer_id FROM orders WHERE id = $1', [orderId]);
    if (!r.rows.length || (role !== 'admin' && r.rows[0].customer_id !== userId)) {
      return reply({ ok: false, error: 'Order not found' });
    }
    untrack(socket);
    socket.join(`track:${orderId}`);
    socket.data.trackedOrderId = orderId;
    reply({ ok: true, orderId });
  } catch {
    reply({ ok: false, error: 'Could not start tracking' });
  }
}

/**
 * Sends to the sockets watching this order. Returns false (and sends nothing)
 * when nobody is watching.
 */
function emitToTrackers(orderId, event, data) {
  const room = `track:${orderId}`;
  if (!io?.sockets.adapter.rooms.get(room)?.size) return false;
  io.to(room).emit(event, data);
  return true;
}

const emitToUser = (userId, event, data) => io?.to(`user:${userId}`).emit(event, data);
const emitToVendor = (vendorId, event, data) => io?.to(`vendor:${vendorId}`).emit(event, data);
const emitToRiders = (event, data) => io?.to('riders').emit(event, data);
const emitToAdmins = (event, data) => io?.to('admins').emit(event, data);
const broadcast = (event, data) => io?.emit(event, data);

/**
 * Stock change: everyone sees the public count (customer marketplace),
 * the owning vendor also sees private + reserved (POS).
 */
function emitStock(product) {
  broadcast('stock:update', {
    productId: product.id,
    vendorId: product.vendor_id,
    publicStock: product.public_stock,
  });
  emitToVendor(product.vendor_id, 'stock:vendor', {
    productId: product.id,
    privateStock: product.private_stock,
    reservedQuantity: product.reserved_quantity,
    buffer: product.buffer,
    publicStock: product.public_stock,
  });
}

function closeRealtime() {
  return new Promise((resolve) => (io ? io.close(() => resolve()) : resolve()));
}

module.exports = {
  initRealtime,
  closeRealtime,
  emitToUser,
  emitToTrackers,
  emitToVendor,
  emitToRiders,
  emitToAdmins,
  broadcast,
  emitStock,
};
