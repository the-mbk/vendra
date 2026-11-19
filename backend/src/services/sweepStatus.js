// ══════════════════════════════════════════════════════════════
// When the background sweep (server.js) last ran, for the admin's
// platform health panel. Kept in memory: a restart starts it fresh.
// ══════════════════════════════════════════════════════════════

/** How often server.js runs the sweep */
const SWEEP_SECONDS = 30;

let lastRunAt = null;
let lastError = null;

/** Called after every sweep; err is the failure, or null when it completed */
function recordSweep(err) {
  lastRunAt = new Date();
  lastError = err ? err.message : null;
}

const sweepStatus = () => ({
  lastRunAt,
  secondsAgo: lastRunAt ? Math.round((Date.now() - lastRunAt.getTime()) / 1000) : null,
  lastError,
  intervalSeconds: SWEEP_SECONDS,
});

module.exports = { recordSweep, sweepStatus, SWEEP_SECONDS };
