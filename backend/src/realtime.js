// ══════════════════════════════════════════════════════════════
// Vendra Backend - Realtime (Socket.IO)
// Clients connect with { auth: { token } } and are placed in rooms:
//   user:<id>  vendor:<vendorId>  riders  admins
// Anonymous clients still receive public stock updates.
// ══════════════════════════════════════════════════════════════

const { Server } = require('socket.io');
const jwt = require('jsonwebtoken');
const { corsOrigin } = require('./utils/cors');

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
  });

  return io;
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
  emitToVendor,
  emitToRiders,
  emitToAdmins,
  broadcast,
  emitStock,
};
