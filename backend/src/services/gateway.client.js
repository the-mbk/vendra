// ══════════════════════════════════════════════════════════════
// Client for the card payment gateway (Vendra Pay locally; same shape as Stripe).
// The backend only ever handles single-use card tokens, never card numbers.
//
//   GATEWAY_URL               where the backend reaches the gateway (default http://localhost:4242)
//   GATEWAY_PUBLIC_URL        where the apps reach it, if different
//   GATEWAY_SECRET_KEY        server-side key (sk_…)
//   GATEWAY_PUBLISHABLE_KEY   key the apps use to tokenize cards (pk_…)
//   GATEWAY_WEBHOOK_SECRET    verifies webhook signatures (whsec_…)
// ══════════════════════════════════════════════════════════════

const crypto = require('crypto');
const { httpError } = require('../utils/http');
const { isDevelopment } = require('../config/mode');

const SIGNATURE_TOLERANCE_SEC = 5 * 60;

const config = () => ({
  url: (process.env.GATEWAY_URL || 'http://localhost:4242').replace(/\/$/, ''),
  publicUrl: (process.env.GATEWAY_PUBLIC_URL || process.env.GATEWAY_URL || 'http://localhost:4242').replace(/\/$/, ''),
  secretKey: process.env.GATEWAY_SECRET_KEY || 'sk_test_vendra',
  publishableKey: process.env.GATEWAY_PUBLISHABLE_KEY || 'pk_test_vendra',
  webhookSecret: process.env.GATEWAY_WEBHOOK_SECRET || 'whsec_vendra',
});

/**
 * Calls the gateway. Card and request errors become 4xx httpErrors carrying the
 * gateway's code; an unreachable gateway is a 503.
 */
async function call(method, path, body, idempotencyKey) {
  const { url, secretKey } = config();
  let res;
  try {
    res = await fetch(url + path, {
      method,
      headers: {
        Authorization: `Bearer ${secretKey}`,
        'Content-Type': 'application/json',
        ...(idempotencyKey ? { 'Idempotency-Key': idempotencyKey } : {}),
      },
      body: body === undefined ? undefined : JSON.stringify(body),
      signal: AbortSignal.timeout(10_000),
    });
  } catch (err) {
    throw httpError(503, 'The payment service is unavailable right now. Please try again in a moment.', {
      code: 'GATEWAY_UNAVAILABLE',
      ...(isDevelopment ? { cause: err.message } : {}),
    });
  }
  const payload = await res.json().catch(() => ({}));
  if (!res.ok) {
    const e = payload.error || {};
    const status = res.status === 402 || res.status === 400 ? 400 : res.status === 404 ? 404 : 502;
    throw httpError(status, e.message || 'The payment service rejected the request.', {
      code: (e.code || 'gateway_error').toUpperCase(),
      gatewayStatus: res.status,
    });
  }
  return payload;
}

const createPaymentIntent = (params, idempotencyKey) => call('POST', '/v1/payment_intents', { currency: 'pkr', ...params }, idempotencyKey);
const getPaymentIntent = (id) => call('GET', `/v1/payment_intents/${encodeURIComponent(id)}`);
const createPayout = (params, idempotencyKey) => call('POST', '/v1/payouts', { currency: 'pkr', ...params }, idempotencyKey);
const getPayout = (id) => call('GET', `/v1/payouts/${encodeURIComponent(id)}`);
const getBalance = () => call('GET', '/v1/balance');
const createTopup = (params, idempotencyKey) => call('POST', '/v1/topups', { currency: 'pkr', ...params }, idempotencyKey);

/**
 * Checks the Vendra-Signature header (t=<unix>,v1=<hex HMAC-SHA256 of "t.body">)
 * and returns the parsed event, or null when it doesn't verify.
 */
function verifyWebhook(rawBody, header) {
  const match = /^t=(\d+),v1=([0-9a-f]{64})$/.exec(header || '');
  if (!match) return null;
  const [, t, v1] = match;
  if (Math.abs(Date.now() / 1000 - Number(t)) > SIGNATURE_TOLERANCE_SEC) return null;
  const expected = crypto.createHmac('sha256', config().webhookSecret).update(`${t}.${rawBody}`).digest('hex');
  if (!crypto.timingSafeEqual(Buffer.from(v1), Buffer.from(expected))) return null;
  try {
    return JSON.parse(rawBody);
  } catch {
    return null;
  }
}

/** What the apps need to tokenize cards */
const publicGatewayConfig = () => {
  const { publicUrl, publishableKey } = config();
  return { gatewayUrl: publicUrl, publishableKey };
};

module.exports = {
  createPaymentIntent,
  getPaymentIntent,
  createPayout,
  getPayout,
  getBalance,
  createTopup,
  verifyWebhook,
  publicGatewayConfig,
};
