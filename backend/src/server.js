// ══════════════════════════════════════════════════════════════
// Vendra Backend - Server Entry Point
// ══════════════════════════════════════════════════════════════

require('dotenv').config();

const { createServer } = require('./app');
const { releaseDueEscrows } = require('./services/orderSettlement.service');

const PORT = process.env.PORT || 3000;
const ESCROW_SWEEP_MS = 30 * 1000;

const { server } = createServer();

server.listen(PORT, () => {
  console.log(`\n══════════════════════════════════════`);
  console.log(`  🏪 Vendra API Server`);
  console.log(`  📍 Running on http://localhost:${PORT}`);
  console.log(`  🔌 Realtime (Socket.IO) on the same port`);
  console.log(`  🕐 Started at ${new Date().toLocaleString()}`);
  console.log(`══════════════════════════════════════\n`);
});

// Release escrow for delivered orders whose dispute window has passed
setInterval(() => {
  releaseDueEscrows()
    .then((n) => n > 0 && console.log(`💸 Released escrow for ${n} order(s)`))
    .catch((err) => console.error('Escrow sweep failed:', err.message));
}, ESCROW_SWEEP_MS).unref();

module.exports = server;
