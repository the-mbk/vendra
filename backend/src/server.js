// ══════════════════════════════════════════════════════════════
// Vendra Backend - Server Entry Point
// ══════════════════════════════════════════════════════════════

require('dotenv').config();

const { APP_MODE, FEATURES, isDevelopment, assertProductionConfig } = require('./config/mode');

try {
  assertProductionConfig();
} catch (err) {
  console.error(err.message);
  process.exit(1);
}

const { createServer } = require('./app');
const { releaseDueEscrows } = require('./services/orderSettlement.service');
const { cancelStaleOrders } = require('./services/orderTimeouts.service');
const { reconcileOpen, fundOpeningBalances } = require('./services/payments.service');
const { initStorage } = require('./services/storage.service');

const PORT = process.env.PORT || 3000;
const SWEEP_MS = 30 * 1000;

const { server } = createServer();

initStorage()
  .then((storage) => {
    server.listen(PORT, () => {
      const on = Object.entries(FEATURES).filter(([, v]) => v).map(([k]) => k);
      console.log(`\n══════════════════════════════════════`);
      console.log(`  🏪 Vendra API Server  ·  ${APP_MODE.toUpperCase()} mode`);
      console.log(`  📍 Running on http://localhost:${PORT}`);
      console.log(`  🔌 Realtime (Socket.IO) on the same port`);
      console.log(`  🗂  Files in ${storage}`);
      console.log(`  💳 Payments via ${process.env.GATEWAY_URL || 'http://localhost:4242'}`);
      console.log(`  🧪 Dev features: ${on.length ? on.join(', ') : 'none'}`);
      console.log(`  🕐 Started at ${new Date().toLocaleString()}`);
      console.log(`══════════════════════════════════════\n`);
    });
  })
  .catch((err) => {
    console.error(`File storage is unreachable: ${err.message}`);
    console.error('Start it with "npm run db:up" (SeaweedFS on port 8333), or unset S3_BUCKET to keep files on disk.');
    process.exit(1);
  });

// Background work, every 30 seconds:
//   release escrow whose dispute window has passed, cancel and refund stalled orders,
//   catch up on payments/payouts whose webhooks went missing, and (development only)
//   back the demo data's opening balances with funds at the gateway
let openingFunded = !isDevelopment;
async function sweep() {
  const released = await releaseDueEscrows();
  if (released) console.log(`💸 Released escrow for ${released} order(s)`);
  const cancelled = await cancelStaleOrders();
  if (cancelled) console.log(`⏱  Cancelled and refunded ${cancelled} stalled order(s)`);
  const fixed = await reconcileOpen();
  if (fixed) console.log(`🔄 Caught up ${fixed} payment(s)/withdrawal(s) from the gateway`);
  if (!openingFunded) {
    const funded = await fundOpeningBalances().catch(() => null); // retried until the gateway is up
    if (funded !== null) {
      openingFunded = true;
      if (funded) console.log(`🏦 Added Rs. ${(funded / 100).toFixed(2)} at the gateway to back opening balances`);
    }
  }
}
setTimeout(() => sweep().catch((err) => console.error('Sweep failed:', err.message)), 2000).unref();
setInterval(() => sweep().catch((err) => console.error('Sweep failed:', err.message)), SWEEP_MS).unref();

module.exports = server;
