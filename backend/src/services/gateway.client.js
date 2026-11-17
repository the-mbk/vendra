// ══════════════════════════════════════════════════════════════
// The card payment gateway, chosen by PAYMENT_PROVIDER:
//   vendrapay (default)  the local sandbox in backend/gateway/ (tests, offline demos)
//   stripe               Stripe, with STRIPE_SECRET_KEY / STRIPE_PUBLISHABLE_KEY
// Both expose the same functions and return Vendra Pay–shaped objects
// (see gateway/vendrapay.js); `capabilities` says what a provider can't do.
// ══════════════════════════════════════════════════════════════

const PROVIDERS = ['vendrapay', 'stripe'];

const name = (process.env.PAYMENT_PROVIDER || 'vendrapay').toLowerCase();
if (!PROVIDERS.includes(name)) {
  throw new Error(`PAYMENT_PROVIDER must be one of ${PROVIDERS.join(', ')} (got "${process.env.PAYMENT_PROVIDER}").`);
}

module.exports = require(`./gateway/${name}`);
