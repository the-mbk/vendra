// Payoneer sandbox simulator entry point. Configuration comes from the environment (see README.md).
const fs = require('fs');
const path = require('path');
const { createPayoneerSim } = require('./app');

const PORT = Number(process.env.PORT || 4343);
const DATA_DIR = process.env.DATA_DIR || path.join(__dirname, '..', 'data');
fs.mkdirSync(DATA_DIR, { recursive: true });

const sim = createPayoneerSim({
  dbPath: path.join(DATA_DIR, 'payoneer-sim.sqlite'),
  clientId: process.env.CLIENT_ID || 'vendra_sandbox',
  clientSecret: process.env.CLIENT_SECRET || 'vendra_sandbox_secret',
  programId: process.env.PROGRAM_ID || '100086',
  ipcnUrl: process.env.IPCN_URL || null,
  publicUrl: process.env.PUBLIC_URL || `http://localhost:${PORT}`,
  approvalDelaySec: Number(process.env.APPROVAL_DELAY_SEC ?? 8),
  payoutDelaySec: Number(process.env.PAYOUT_DELAY_SEC ?? 15),
  log: (line) => console.log(line),
});

sim.startClock();
sim.server.listen(PORT, () => {
  console.log(`Payoneer sandbox simulator on http://localhost:${PORT}  (program dashboard at /)`);
  console.log(`IPCN → ${process.env.IPCN_URL || 'not configured (set IPCN_URL)'}`);
});

const stop = () => sim.server.close(() => { sim.close(); process.exit(0); });
process.on('SIGTERM', stop);
process.on('SIGINT', stop);
