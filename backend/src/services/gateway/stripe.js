// ══════════════════════════════════════════════════════════════
// Stripe provider (test or live keys). Normalises Stripe's objects to the
// Vendra Pay shapes payments.service.js works with, so the rest of the
// backend doesn't know which gateway is behind it.
//
//   STRIPE_SECRET_KEY        sk_test_… (server only)
//   STRIPE_PUBLISHABLE_KEY   pk_test_… (sent to the apps for Stripe's card field)
//   STRIPE_WEBHOOK_SECRET    whsec_… from the dashboard endpoint or `stripe listen`
//
// Cards: the apps collect them in Stripe's own card field and send a
// PaymentMethod id (pm_…); card numbers never reach the Vendra API. The
// PaymentIntent is confirmed here; when the bank asks for 3-D Secure the
// intent is `requires_action` and the app finishes it with Stripe's SDK
// (next_action.client_secret), then asks the API to refresh.
// Amounts are in paisa: PKR is a two-decimal currency at Stripe.
// ══════════════════════════════════════════════════════════════

const crypto = require('crypto');
const { httpError } = require('../../utils/http');
const { isDevelopment } = require('../../config/mode');

const API = 'https://api.stripe.com';
const SIGNATURE_TOLERANCE_SEC = 5 * 60;

const config = () => ({
  secretKey: process.env.STRIPE_SECRET_KEY || '',
  publishableKey: process.env.STRIPE_PUBLISHABLE_KEY || '',
  webhookSecret: process.env.STRIPE_WEBHOOK_SECRET || '',
});

/** { a: 1, metadata: { x: 'y' }, expand: ['b'] } → a=1&metadata[x]=y&expand[0]=b */
function formEncode(params, prefix = '', out = new URLSearchParams()) {
  for (const [key, value] of Object.entries(params || {})) {
    if (value === undefined || value === null) continue;
    const name = prefix ? `${prefix}[${key}]` : key;
    if (typeof value === 'object') formEncode(value, name, out);
    else out.append(name, String(value));
  }
  return out;
}

/**
 * Calls Stripe. Request errors become 4xx httpErrors carrying Stripe's code; an
 * unreachable Stripe is a 503. A card error is returned as `{ cardError }` instead
 * of thrown, because it still carries the PaymentIntent (now failed).
 */
async function call(method, path, params, { idempotencyKey, account } = {}) {
  const { secretKey } = config();
  if (!secretKey) {
    throw httpError(503, 'Card payments are not configured (STRIPE_SECRET_KEY is missing).', { code: 'GATEWAY_UNAVAILABLE' });
  }
  const query = method === 'GET' && params ? `?${formEncode(params)}` : '';
  let res;
  try {
    res = await fetch(API + path + query, {
      method,
      headers: {
        Authorization: `Bearer ${secretKey}`,
        'Content-Type': 'application/x-www-form-urlencoded',
        'Stripe-Version': '2024-06-20',
        ...(idempotencyKey ? { 'Idempotency-Key': idempotencyKey } : {}),
        ...(account ? { 'Stripe-Account': account } : {}),
      },
      body: method === 'GET' ? undefined : formEncode(params).toString(),
      signal: AbortSignal.timeout(20_000),
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
    if (e.type === 'card_error' && e.payment_intent) return { cardError: e };
    const status = res.status === 402 || res.status === 400 ? 400 : res.status === 404 ? 404 : res.status === 429 ? 503 : 502;
    throw httpError(status, e.message || 'The payment service rejected the request.', {
      code: (e.code || e.type || 'gateway_error').toUpperCase(),
      gatewayStatus: res.status,
    });
  }
  return payload;
}

// ──────────────────────────────────────
// PaymentIntents (money in)
// ──────────────────────────────────────

/** Stripe status → processing | requires_action | succeeded | failed | canceled */
function intentStatus(pi) {
  switch (pi.status) {
    case 'succeeded': return 'succeeded';
    case 'canceled': return 'canceled';
    case 'requires_action': return 'requires_action';
    // After a declined attempt or a failed 3-D Secure check the intent waits for a new card: for us it failed
    case 'requires_payment_method': return pi.last_payment_error ? 'failed' : 'processing';
    default: return 'processing'; // requires_confirmation, processing, requires_capture
  }
}

/** A Stripe PaymentIntent in the Vendra Pay shape */
function toIntent(pi, failure = null) {
  const charge = pi.latest_charge && typeof pi.latest_charge === 'object' ? pi.latest_charge : null;
  const pm = pi.payment_method && typeof pi.payment_method === 'object' ? pi.payment_method : null;
  const card = charge?.payment_method_details?.card || pm?.card || failure?.payment_method?.card || null;
  const status = failure ? 'failed' : intentStatus(pi);
  const error = failure || pi.last_payment_error;
  return {
    id: pi.id,
    object: 'payment_intent',
    amount: pi.amount,
    currency: pi.currency,
    status,
    card: card ? { brand: card.brand, last4: card.last4 } : null,
    metadata: pi.metadata || {},
    last_payment_error: status === 'failed' && error ? { code: error.decline_code || error.code, message: error.message } : null,
    next_action: status === 'requires_action' ? { type: 'stripe_sdk', client_secret: pi.client_secret } : null,
  };
}

/**
 * Charges a PaymentMethod (pm_…) the app created with Stripe's card field.
 * params: { amount (paisa), token (pm_…), description, metadata }
 */
async function createPaymentIntent({ amount, token, description, metadata }, idempotencyKey) {
  const r = await call('POST', '/v1/payment_intents', {
    amount,
    currency: 'pkr',
    payment_method: token,
    payment_method_types: ['card'],
    confirm: true,
    // 3-D Secure is finished in the app with Stripe's SDK (handleNextAction)
    use_stripe_sdk: true,
    description,
    metadata,
    expand: ['latest_charge'],
  }, { idempotencyKey });
  if (r.cardError) return toIntent(r.cardError.payment_intent, r.cardError);
  return toIntent(r);
}

async function getPaymentIntent(id) {
  return toIntent(await call('GET', `/v1/payment_intents/${encodeURIComponent(id)}`, { expand: ['latest_charge', 'payment_method'] }));
}

/** The platform's Stripe balance, in its own currency (not PKR: Stripe converts on settlement) */
async function getBalance() {
  const b = await call('GET', '/v1/balance');
  const sum = (list) => (list || []).reduce((s, x) => s + x.amount, 0);
  return { currency: b.available?.[0]?.currency || null, available: sum(b.available), pending: sum(b.pending) };
}

// ──────────────────────────────────────
// Connect (money out): Express accounts + transfers
// ──────────────────────────────────────

let platformAccount = null;

/** The platform's own Stripe account: country and settlement currency (cached) */
async function getPlatform() {
  if (!platformAccount) {
    const a = await call('GET', '/v1/account');
    platformAccount = { id: a.id, country: a.country, currency: a.default_currency };
  }
  return platformAccount;
}

/**
 * Rupees per one unit of the platform's currency, for withdrawals: Stripe transfers
 * must be in the platform's currency. STRIPE_PKR_PER_UNIT (default 280, roughly PKR per USD).
 */
const pkrPerUnit = () => {
  const r = Number(process.env.STRIPE_PKR_PER_UNIT);
  return Number.isFinite(r) && r > 0 ? r : 280;
};

/** Rupee paisa → the platform currency's minor units (cents for USD) */
const toPlatformMinor = (paisa) => Math.max(1, Math.round(paisa / pkrPerUnit()));

const V2_VERSION = process.env.STRIPE_V2_VERSION || '2026-10-28.endive';

/** Accounts v2 call (JSON body, its own API version); errors as in call() */
async function callV2(method, path, body, { idempotencyKey } = {}) {
  const { secretKey } = config();
  let res;
  try {
    res = await fetch(API + path, {
      method,
      headers: {
        Authorization: `Bearer ${secretKey}`,
        'Content-Type': 'application/json',
        'Stripe-Version': V2_VERSION,
        ...(idempotencyKey ? { 'Idempotency-Key': idempotencyKey } : {}),
      },
      body: body === undefined ? undefined : JSON.stringify(body),
      signal: AbortSignal.timeout(20_000),
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
    throw httpError(res.status === 400 ? 400 : res.status === 404 ? 404 : 502, e.message || 'The payment service rejected the request.', {
      code: (e.code || e.type || 'gateway_error').toUpperCase(),
      gatewayStatus: res.status,
    });
  }
  return payload;
}

/**
 * A payout account for a wallet owner: a v2 recipient account (it only receives
 * transfers) with the Express dashboard, in the platform's country (or
 * STRIPE_CONNECT_COUNTRY). New Connect platforms must create accounts with
 * Accounts v2; the v1 endpoints used afterwards (account links, retrieve,
 * transfers, login links) accept its acct_… id. With the Express dashboard the
 * platform covers fees and losses, as Stripe requires.
 */
async function createConnectAccount({ email, userId, role, name }) {
  const country = (process.env.STRIPE_CONNECT_COUNTRY || (await getPlatform()).country).toLowerCase();
  return callV2('POST', '/v2/core/accounts', {
    contact_email: email,
    display_name: name || email,
    dashboard: 'express',
    identity: { country, entity_type: 'individual' },
    configuration: { recipient: { capabilities: { stripe_balance: { stripe_transfers: { requested: true } } } } },
    defaults: { responsibilities: { fees_collector: 'application', losses_collector: 'application' } },
    metadata: { vendra_user_id: String(userId), role },
  }, { idempotencyKey: `vendra-connect-${userId}` });
}

/** Stripe-hosted onboarding (or update) page for the account; single use, expires in minutes */
async function createAccountLink(accountId, { refreshUrl, returnUrl }) {
  return call('POST', '/v1/account_links', {
    account: accountId,
    refresh_url: refreshUrl,
    return_url: returnUrl,
    type: 'account_onboarding',
  });
}

const getConnectAccount = (accountId) => call('GET', `/v1/accounts/${encodeURIComponent(accountId)}`);

/** Express dashboard login link (the user sees their Stripe balance and bank payouts) */
const createLoginLink = (accountId) => call('POST', `/v1/accounts/${encodeURIComponent(accountId)}/login_links`, {});

/**
 * Sends a withdrawal to the user's connected account, converted to the platform's
 * currency. Returned in the Vendra Pay payout shape: a transfer arrives at once.
 */
async function createTransfer({ amountPaisa, destination, description, metadata }, idempotencyKey) {
  const { currency } = await getPlatform();
  const amount = toPlatformMinor(amountPaisa);
  const t = await call('POST', '/v1/transfers', { amount, currency, destination, description, metadata }, { idempotencyKey });
  return {
    id: t.id,
    status: t.reversed ? 'failed' : 'paid',
    amount: t.amount,
    currency: t.currency,
    destination: { brand: 'stripe', last4: String(t.destination).slice(-4) },
    failure_message: t.reversed ? 'The transfer was reversed.' : null,
  };
}

/**
 * Test mode only: adds `amount` (platform minor units) to the platform's available
 * balance with Stripe's pm_card_bypassPending test card, so withdrawals of demo
 * money (opening balances that never came through a card) can be sent.
 */
async function fundTestBalance(amountMinor, idempotencyKey) {
  if (!config().secretKey.startsWith('sk_test_')) throw new Error('Test balance funding needs a test key.');
  const { currency } = await getPlatform();
  const pi = await call('POST', '/v1/payment_intents', {
    amount: amountMinor,
    currency,
    payment_method: 'pm_card_bypassPending',
    payment_method_types: ['card'],
    confirm: true,
    description: 'Vendra: platform funds for demo withdrawals (test mode)',
    metadata: { vendra_ref: 'platform_funding' },
  }, { idempotencyKey });
  if (pi.cardError || pi.status !== 'succeeded') throw new Error('Funding the Stripe test balance failed.');
  return { id: pi.id, amountPaisa: Math.round(amountMinor * pkrPerUnit()) };
}

// ──────────────────────────────────────
// Webhooks
// ──────────────────────────────────────

/**
 * Checks the Stripe-Signature header (t=<unix>,v1=<hex HMAC-SHA256 of "t.body">[,v1=…][,v0=…])
 * and returns the event with PaymentIntents normalised, or null when it doesn't verify.
 */
function verifyWebhook(rawBody, headers) {
  const { webhookSecret } = config();
  const header = headers['stripe-signature'];
  if (!webhookSecret || !header) return null;
  const parts = header.split(',').map((p) => p.split('='));
  const t = parts.find(([k]) => k === 't')?.[1];
  const signatures = parts.filter(([k]) => k === 'v1').map(([, v]) => v);
  if (!t || signatures.length === 0 || Math.abs(Date.now() / 1000 - Number(t)) > SIGNATURE_TOLERANCE_SEC) return null;
  const expected = Buffer.from(crypto.createHmac('sha256', webhookSecret).update(`${t}.${rawBody}`).digest('hex'));
  const valid = signatures.some((v) => {
    const got = Buffer.from(v);
    return got.length === expected.length && crypto.timingSafeEqual(got, expected);
  });
  if (!valid) return null;
  let event;
  try {
    event = JSON.parse(rawBody);
  } catch {
    return null;
  }
  const object = event?.data?.object;
  if (object?.object === 'payment_intent') event.data.object = toIntent(object);
  return event;
}

/** What the apps need for Stripe's card field */
const publicGatewayConfig = () => ({ provider: 'stripe', gatewayUrl: null, publishableKey: config().publishableKey });

/** Stripe's card field gives the app a PaymentMethod id */
const isPaymentToken = (token) => /^pm_[A-Za-z0-9_]{8,}$/.test(token);

module.exports = {
  name: 'stripe',
  // Stripe can't pay out to a user's card (withdrawals go to Connect accounts instead),
  // and holds the platform's funds in its own settlement currency, not PKR
  capabilities: { cardPayouts: false, pkrBalance: false, platformTopups: false },
  isPaymentToken,
  createPaymentIntent,
  getPaymentIntent,
  getBalance,
  verifyWebhook,
  publicGatewayConfig,
  getPlatform,
  createConnectAccount,
  createAccountLink,
  getConnectAccount,
  createLoginLink,
  createTransfer,
  fundTestBalance,
  toPlatformMinor,
  pkrPerUnit,
  call,
  toIntent,
  formEncode,
};
