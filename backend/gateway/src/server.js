// Vendra Pay entry point. Configuration comes from the environment (see README.md).
const fs = require('fs');
const path = require('path');
const { createGateway } = require('./app');

const PORT = Number(process.env.PORT || 4242);
const DATA_DIR = process.env.DATA_DIR || path.join(__dirname, '..', 'data');
fs.mkdirSync(DATA_DIR, { recursive: true });

const gateway = createGateway({
  dbPath: path.join(DATA_DIR, 'vendra-pay.sqlite'),
  publishableKey: process.env.PUBLISHABLE_KEY || 'pk_test_vendra',
  secretKey: process.env.SECRET_KEY || 'sk_test_vendra',
  webhookSecret: process.env.WEBHOOK_SECRET || 'whsec_vendra',
  webhookUrl: process.env.WEBHOOK_URL || null,
  payoutDelaySec: Number(process.env.PAYOUT_DELAY_SEC ?? 20),
  log: (line) => console.log(line),
});

gateway.startClock();
gateway.server.listen(PORT, () => {
  console.log(`Vendra Pay sandbox on http://localhost:${PORT}  (dashboard at /)`);
  console.log(`Webhooks → ${process.env.WEBHOOK_URL || 'not configured (set WEBHOOK_URL)'}`);
});

const stop = () => gateway.server.close(() => { gateway.close(); process.exit(0); });
process.on('SIGTERM', stop);
process.on('SIGINT', stop);
