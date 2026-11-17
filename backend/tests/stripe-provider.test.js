// ══════════════════════════════════════════════════════════════
// The Stripe provider against a stubbed fetch (no network, no keys):
// PaymentIntents are normalised to the Vendra Pay shape, declines become
// failed payments, webhooks are verified like Stripe signs them, and
// withdrawals are converted to the platform's currency.
// ══════════════════════════════════════════════════════════════

const { test, describe, beforeEach, afterEach } = require('node:test');
const assert = require('node:assert/strict');
const crypto = require('crypto');

process.env.STRIPE_SECRET_KEY = 'sk_test_unit';
process.env.STRIPE_PUBLISHABLE_KEY = 'pk_test_unit';
process.env.STRIPE_WEBHOOK_SECRET = 'whsec_unit';
process.env.STRIPE_PKR_PER_UNIT = '280';
const stripe = require('../src/services/gateway/stripe');

const realFetch = global.fetch;
let calls;
let replies;

/** Queues Stripe responses: [status, body] per request, in order */
function stub(...responses) {
  replies = responses;
  global.fetch = async (url, init) => {
    calls.push({ url, method: init.method, headers: init.headers, body: init.body ? new URLSearchParams(init.body) : null });
    const [status, body] = replies.shift();
    return { ok: status < 400, status, json: async () => body };
  };
}

beforeEach(() => { calls = []; });
afterEach(() => { global.fetch = realFetch; });

const PI = {
  id: 'pi_123', object: 'payment_intent', amount: 150000, currency: 'pkr', status: 'succeeded',
  client_secret: 'pi_123_secret_abc', metadata: { vendra_ref: 'payment:7' },
  latest_charge: { payment_method_details: { card: { brand: 'visa', last4: '4242' } } },
};

describe('Stripe provider', () => {
  test('a card PaymentIntent is created confirmed, in paisa, and normalised', async () => {
    stub([200, PI]);
    const intent = await stripe.createPaymentIntent(
      { amount: 150000, token: 'pm_card_visa_x1', description: 'Top-up', metadata: { vendra_ref: 'payment:7' } }, 'vendra-payment-7');
    assert.deepEqual(
      { id: intent.id, status: intent.status, amount: intent.amount, card: intent.card, next_action: intent.next_action },
      { id: 'pi_123', status: 'succeeded', amount: 150000, card: { brand: 'visa', last4: '4242' }, next_action: null }
    );
    const req = calls[0];
    assert.equal(req.url, 'https://api.stripe.com/v1/payment_intents');
    assert.equal(req.headers.Authorization, 'Bearer sk_test_unit');
    assert.equal(req.headers['Idempotency-Key'], 'vendra-payment-7');
    assert.equal(req.body.get('amount'), '150000');
    assert.equal(req.body.get('currency'), 'pkr');
    assert.equal(req.body.get('payment_method'), 'pm_card_visa_x1');
    assert.equal(req.body.get('confirm'), 'true');
    assert.equal(req.body.get('metadata[vendra_ref]'), 'payment:7');
    assert.equal(req.body.get('expand[0]'), 'latest_charge');
  });

  test('3-D Secure: requires_action carries the client secret for the app', async () => {
    stub([200, { ...PI, status: 'requires_action', latest_charge: null }]);
    const intent = await stripe.createPaymentIntent({ amount: 150000, token: 'pm_card_3ds_xx', metadata: {} });
    assert.equal(intent.status, 'requires_action');
    assert.deepEqual(intent.next_action, { type: 'stripe_sdk', client_secret: 'pi_123_secret_abc' });
  });

  test('a declined card is a failed payment, not an exception', async () => {
    stub([402, { error: {
      type: 'card_error', code: 'card_declined', decline_code: 'insufficient_funds', message: 'Your card has insufficient funds.',
      payment_intent: { ...PI, status: 'requires_payment_method', latest_charge: null },
      payment_method: { card: { brand: 'visa', last4: '9995' } },
    } }]);
    const intent = await stripe.createPaymentIntent({ amount: 150000, token: 'pm_card_declined', metadata: {} });
    assert.equal(intent.status, 'failed');
    assert.equal(intent.last_payment_error.message, 'Your card has insufficient funds.');
    assert.deepEqual(intent.card, { brand: 'visa', last4: '9995' });
  });

  test('a failed 3-D Secure check reads as failed; a fresh intent as processing', () => {
    assert.equal(stripe.toIntent({ ...PI, status: 'requires_payment_method', last_payment_error: { message: 'Authentication failed.' } }).status, 'failed');
    assert.equal(stripe.toIntent({ ...PI, status: 'processing' }).status, 'processing');
    assert.equal(stripe.toIntent({ ...PI, status: 'canceled' }).status, 'canceled');
  });

  test('request errors keep Stripe\'s code; an unreachable Stripe is a 503', async () => {
    stub([400, { error: { type: 'invalid_request_error', code: 'amount_too_small', message: 'Amount must be at least $0.50 usd' } }]);
    await assert.rejects(stripe.createPaymentIntent({ amount: 100, token: 'pm_card_visa_x1', metadata: {} }),
      (err) => err.statusCode === 400 && err.details.code === 'AMOUNT_TOO_SMALL');
    global.fetch = async () => { throw new Error('ECONNRESET'); };
    await assert.rejects(stripe.getPaymentIntent('pi_123'), (err) => err.statusCode === 503);
  });

  test('only PaymentMethod ids count as a card token', () => {
    assert.equal(stripe.isPaymentToken('pm_1PqRsTuVwXyZ'), true);
    assert.equal(stripe.isPaymentToken('tok_visa_123456'), false);
    assert.equal(stripe.isPaymentToken('4242424242424242'), false);
  });
});

describe('Stripe webhooks', () => {
  function sign(body, { secret = 'whsec_unit', t = Math.floor(Date.now() / 1000), extra = '' } = {}) {
    const v1 = crypto.createHmac('sha256', secret).update(`${t}.${body}`).digest('hex');
    return `t=${t},v1=${v1}${extra}`;
  }
  const body = JSON.stringify({ id: 'evt_1', type: 'payment_intent.succeeded', data: { object: PI } });

  test('a correctly signed event is accepted and its PaymentIntent normalised', () => {
    const event = stripe.verifyWebhook(body, { 'stripe-signature': sign(body, { extra: ',v0=deadbeef' }) });
    assert.equal(event.type, 'payment_intent.succeeded');
    assert.equal(event.data.object.status, 'succeeded');
    assert.equal(event.data.object.metadata.vendra_ref, 'payment:7');
  });

  test('wrong secret, tampered body or an old timestamp are refused', () => {
    assert.equal(stripe.verifyWebhook(body, { 'stripe-signature': sign(body, { secret: 'whsec_other' }) }), null);
    assert.equal(stripe.verifyWebhook(body.replace('150000', '1'), { 'stripe-signature': sign(body) }), null);
    assert.equal(stripe.verifyWebhook(body, { 'stripe-signature': sign(body, { t: Math.floor(Date.now() / 1000) - 3600 }) }), null);
    assert.equal(stripe.verifyWebhook(body, {}), null);
  });
});

describe('Stripe Connect withdrawals', () => {
  test('a withdrawal is a transfer in the platform\'s currency at the configured rate', async () => {
    stub(
      [200, { id: 'acct_platform', country: 'US', default_currency: 'usd' }],
      [200, { id: 'tr_1', amount: 1786, currency: 'usd', destination: 'acct_1AbCdEf', reversed: false }],
    );
    const payout = await stripe.createTransfer({
      amountPaisa: 500000, destination: 'acct_1AbCdEf', description: 'Vendra withdrawal #3', metadata: { vendra_ref: 'withdrawal:3' },
    }, 'vendra-withdrawal-3');
    // Rs 5,000 at 280 per USD = $17.86
    assert.equal(calls[1].body.get('amount'), '1786');
    assert.equal(calls[1].body.get('currency'), 'usd');
    assert.equal(calls[1].body.get('destination'), 'acct_1AbCdEf');
    assert.equal(calls[1].headers['Idempotency-Key'], 'vendra-withdrawal-3');
    assert.deepEqual({ id: payout.id, status: payout.status, amount: payout.amount }, { id: 'tr_1', status: 'paid', amount: 1786 });
  });

  test('payout accounts are v2 recipients with the Express dashboard, one per user', async () => {
    global.fetch = async (url, init) => {
      calls.push({ url, headers: init.headers, json: JSON.parse(init.body) });
      return { ok: true, status: 200, json: async () => ({ id: 'acct_new', object: 'v2.core.account' }) };
    };
    await stripe.createConnectAccount({ email: 'bilal@rider.pk', userId: 6, role: 'rider', name: 'Bilal Hussain' });
    const req = calls[0];
    assert.equal(req.url, 'https://api.stripe.com/v2/core/accounts');
    assert.match(req.headers['Stripe-Version'], /^\d{4}-\d{2}-\d{2}\.\w+$/);
    assert.equal(req.json.dashboard, 'express');
    assert.equal(req.json.identity.country, 'us', 'from the cached platform account');
    assert.equal(req.json.configuration.recipient.capabilities.stripe_balance.stripe_transfers.requested, true);
    assert.deepEqual(req.json.defaults.responsibilities, { fees_collector: 'application', losses_collector: 'application' });
    assert.equal(req.headers['Idempotency-Key'], 'vendra-connect-6');
  });
});
