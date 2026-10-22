// ══════════════════════════════════════════════════════════════
// Vendra Pay sandbox gateway on its own: cards, charges, OTP, payouts, webhooks
// ══════════════════════════════════════════════════════════════

const { describe, it, before, after } = require('node:test');
const assert = require('node:assert/strict');
const http = require('http');
const crypto = require('crypto');
const { createGateway } = require('../gateway/src/app');

const PK = 'pk_test_vendra';
const SK = 'sk_test_vendra';

describe('Vendra Pay gateway', () => {
  let gw;
  let base;
  let hook;
  const received = [];

  before(async () => {
    // A webhook receiver that records signed events
    hook = http.createServer((req, res) => {
      let body = '';
      req.on('data', (c) => { body += c; });
      req.on('end', () => {
        received.push({ signature: req.headers['vendra-signature'], body });
        res.writeHead(200).end('ok');
      });
    });
    await new Promise((r) => hook.listen(0, r));

    gw = createGateway({ payoutDelaySec: 0, webhookUrl: `http://127.0.0.1:${hook.address().port}/` });
    await new Promise((r) => gw.server.listen(0, r));
    base = `http://127.0.0.1:${gw.server.address().port}`;
  });

  after(async () => {
    await new Promise((r) => gw.server.close(r));
    gw.close();
    await new Promise((r) => hook.close(r));
  });

  const call = async (method, path, body, key = SK, headers = {}) => {
    const res = await fetch(base + path, {
      method,
      headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${key}`, ...headers },
      body: body === undefined ? undefined : JSON.stringify(body),
    });
    return { status: res.status, body: await res.json() };
  };
  const token = async (number) => (await call('POST', '/v1/tokens', { number, exp_month: 12, exp_year: 2030, cvc: '123' }, PK)).body.id;
  const charge = async (number, amount = 50000, headers) =>
    (await call('POST', '/v1/payment_intents', { amount, currency: 'pkr', token: await token(number) }, SK, headers)).body;

  it('accepts only valid test cards', async () => {
    const t = (body) => call('POST', '/v1/tokens', { exp_month: 12, exp_year: 2030, cvc: '123', ...body }, PK);
    assert.equal((await t({ number: '4242 4242 4242 4241' })).body.error.code, 'invalid_number');
    assert.equal((await t({ number: '4111111111111111' })).body.error.code, 'test_card_required', 'a real-looking card is refused');
    assert.equal((await t({ number: '4242424242424242', exp_year: 2020 })).body.error.code, 'invalid_expiry_year');
    assert.equal((await t({ number: '4242424242424242', cvc: '1' })).body.error.code, 'incomplete_cvc');
    const ok = await t({ number: '4242-4242-4242-4242' });
    assert.equal(ok.status, 200);
    assert.deepEqual([ok.body.card.brand, ok.body.card.last4], ['visa', '4242']);
    assert.ok(!JSON.stringify(ok.body).includes('4242424242424242'), 'the full number never comes back');
  });

  it('keeps the secret key for server calls', async () => {
    const r = await call('POST', '/v1/payment_intents', { amount: 100, token: await token('4242424242424242') }, PK);
    assert.equal(r.status, 401);
    assert.equal((await call('GET', '/v1/balance', undefined, 'sk_wrong')).status, 401);
  });

  it('charges, declines and asks for a one-time password by card', async () => {
    assert.equal((await charge('4242424242424242')).status, 'succeeded');
    const declined = await charge('4000000000000002');
    assert.equal(declined.status, 'failed');
    assert.equal(declined.last_payment_error.code, 'card_declined');
    assert.equal((await charge('4000000000009995')).last_payment_error.code, 'insufficient_funds');

    const otp = await charge('4000002760003184');
    assert.equal(otp.status, 'requires_action');
    const wrong = await call('POST', `/v1/payment_intents/${otp.id}/verify`, { otp: '000000' }, PK);
    assert.equal(wrong.status, 402);
    assert.match(wrong.body.error.message, /2 attempts left/);
    const right = await call('POST', `/v1/payment_intents/${otp.id}/verify`, { otp: '123456' }, PK);
    assert.equal(right.body.status, 'succeeded');
  });

  it('refuses to reuse a card token', async () => {
    const tok = await token('4242424242424242');
    await call('POST', '/v1/payment_intents', { amount: 100, token: tok });
    const again = await call('POST', '/v1/payment_intents', { amount: 100, token: tok });
    assert.equal(again.body.error.code, 'token_already_used');
  });

  it('returns the first result for a repeated Idempotency-Key', async () => {
    const tok = await token('4242424242424242');
    const h = { 'Idempotency-Key': crypto.randomUUID() };
    const a = await call('POST', '/v1/payment_intents', { amount: 700, token: tok }, SK, h);
    const b = await call('POST', '/v1/payment_intents', { amount: 700, token: tok }, SK, h);
    assert.equal(a.body.id, b.body.id);
  });

  it('pays out from the balance, and bounced payouts come back', async () => {
    const before = gw.balance().available;
    const payout = async (number, amount) =>
      (await call('POST', '/v1/payouts', { amount, token: await token(number) })).body;

    const tooMuch = await payout('4000056655665556', before + 100);
    assert.equal(tooMuch.error.code, 'balance_insufficient');

    const good = await payout('4000056655665556', 1000);
    const bounce = await payout('4000000000000119', 2000);
    assert.equal(good.status, 'in_transit');
    assert.equal(gw.balance().available, before - 3000, 'money leaves the balance while in transit');

    await gw.tick();
    assert.equal((await call('GET', `/v1/payouts/${good.id}`)).body.status, 'paid');
    const bounced = (await call('GET', `/v1/payouts/${bounce.id}`)).body;
    assert.equal(bounced.status, 'failed');
    assert.equal(bounced.failure_code, 'could_not_process');
    assert.equal(gw.balance().available, before - 1000, 'a bounced payout returns to the balance');
  });

  it('adds merchant funds with a top-up', async () => {
    const before = gw.balance().available;
    const r = await call('POST', '/v1/topups', { amount: 12345, description: 'Opening balances' });
    assert.equal(r.body.status, 'succeeded');
    assert.equal(gw.balance().available, before + 12345);
  });

  it('signs every webhook', async () => {
    await gw.tick();
    await new Promise((r) => setTimeout(r, 100));
    const types = received.map((e) => JSON.parse(e.body).type);
    for (const t of ['payment_intent.succeeded', 'payment_intent.payment_failed', 'payout.paid', 'payout.failed']) {
      assert.ok(types.includes(t), `received ${t}`);
    }
    for (const { signature, body } of received) {
      const [, t, v1] = signature.match(/^t=(\d+),v1=([0-9a-f]{64})$/);
      const expected = crypto.createHmac('sha256', 'whsec_vendra').update(`${t}.${body}`).digest('hex');
      assert.equal(v1, expected);
    }
  });
});
