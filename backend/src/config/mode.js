// ══════════════════════════════════════════════════════════════
// APP_MODE — development | production
//
// development  turns on the demo helpers:
//   manualLocation  riders may set their position by hand / simulate a drive
//   testCards       payment screens list the Vendra Pay test cards
//   fastTimers      dispute window and auto-cancel timeouts are capped at a few minutes
//   demoLogin       login screens list the seeded demo accounts; seeding is allowed
// production   turns them all off, and refuses to start with development secrets.
//
// The apps read the mode and features from GET /api/public-config, so switching
// modes needs only a backend restart.
// ══════════════════════════════════════════════════════════════

const MODES = ['development', 'production'];

const raw = (process.env.APP_MODE || (process.env.NODE_ENV === 'production' ? 'production' : 'development')).toLowerCase();
if (!MODES.includes(raw)) {
  throw new Error(`APP_MODE must be "development" or "production" (got "${process.env.APP_MODE}").`);
}

const APP_MODE = raw;
const isDevelopment = APP_MODE === 'development';
const isProduction = !isDevelopment;

const FEATURES = Object.freeze({
  manualLocation: isDevelopment,
  testCards: isDevelopment,
  fastTimers: isDevelopment,
  demoLogin: isDevelopment,
});

/** Upper limits (minutes) on timing policies while fastTimers is on */
const FAST_TIMER_CAPS = Object.freeze({
  dispute_window_min: 2,
  vendor_accept_timeout_min: 5,
  rider_assign_timeout_min: 10,
});

const DEV_JWT_SECRETS = new Set(['', 'dev-secret', 'test-secret', 'demo-secret', 'vendra_super_secret_key_change_in_production']);

/** Throws when production mode is configured with development values */
function assertProductionConfig(env = process.env) {
  if (!isProduction) return;
  const problems = [];
  if (DEV_JWT_SECRETS.has(env.JWT_SECRET || '') || (env.JWT_SECRET || '').length < 32) {
    problems.push('JWT_SECRET must be a random value of at least 32 characters');
  }
  if (!env.ALLOWED_ORIGINS) problems.push('ALLOWED_ORIGINS must list the deployed frontends');
  if (problems.length) throw new Error(`Production mode: ${problems.join('; ')}.`);
}

module.exports = { APP_MODE, isDevelopment, isProduction, FEATURES, FAST_TIMER_CAPS, assertProductionConfig };
