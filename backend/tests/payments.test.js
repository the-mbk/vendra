// ══════════════════════════════════════════════════════════════
// Card payments, withdrawals, webhooks, reconciliation, order timeouts
// and the development/production switch — end to end against Postgres
// and an in-process Vendra Pay gateway.
// ══════════════════════════════════════════════════════════════

const { test, before, after, describe } = require('node:test');
const assert = require('node:assert/strict');
const { execFileSync } = require('node:child_process');
const path = require('node:path');
const { resetDatabase, startServer, cardToken, apiClient, query, moneyInvariant } = require('./helpers');

const CLIFTON = { lat: 24.8138, lng: 67.0300 };
const CARDS = {
  ok: '4242424242424242',
  debit: '4000056655665556',
  otp: '4000002760003184',
  declined: '4000000000000002',
  bounces: '4000000000000119',
};

let srv;
let api;
const tokens = {};

const card = (number = CARDS.ok) => cardToken(srv.gatewayUrl, number);
const wallet = async (t) => (await api('GET', '/api/wallet?limit=200', undefined, t)).body.data;
const balanceOf = async (t) => (await wallet(t)).balance;
/** Lets the gateway land payouts and deliver webhooks */
async function settle() {
  await srv.gateway.tick();
  await new Promise((r) => setTimeout(r, 150));
}

async function assertMoneyBalanced() {
  const m = await moneyInvariant();
  assert.equal(m.accounted.toFixed(2), m.deposits.toFixed(2), 'wallets + pool + platform = money in − money out');
  assert.equal(m.pool.toFixed(2), m.held.toFixed(2), 'escrow pool = money held on open orders');
}

async function login(email, role) {
  const r = await api('POST', '/api/auth/login', { email, password: 'password123', role });
  assert.equal(r.status, 200, JSON.stringify(r.body));
  return r.body.data.token;
}

async function setPolicies(values) {
  const r = await api('PUT', '/api/admin/policies', { values }, tokens.admin);
  assert.equal(r.status, 200, JSON.stringify(r.body));
}

const checkoutBody = (extra = {}) => ({
  items: [{ productId: 2, quantity: 1 }],
  deliveryType: 'delivery',
  deliveryAddress: 'House 21, Clifton',
  customerLat: CLIFTON.lat,
  customerLng: CLIFTON.lng,
  ...extra,
});

before(async () => {
  await resetDatabase();
  srv = await startServer();
  api = apiClient(srv.baseUrl);
  tokens.admin = await login('admin@vendra.pk', 'admin');
  tokens.usman = await login('usman@vendor.pk', 'vendor');
  tokens.ahmed = await login('ahmed@customer.pk', 'customer');
  tokens.bilal = await login('bilal@rider.pk', 'rider');
});

after(async () => {
  await srv?.stop();
});

describe('Card top-ups', () => {
  test('a card top-up reaches the wallet with its gateway reference', async () => {
    const before = await balanceOf(tokens.ahmed);
    const r = await api('POST', '/api/payments/topup', { amount: 2500, token: await card() }, tokens.ahmed);
    assert.equal(r.status, 200, JSON.stringify(r.body));
    assert.equal(r.body.data.payment.status, 'succeeded');
    assert.deepEqual(r.body.data.payment.card, { brand: 'visa', last4: '4242' });
    assert.equal(r.body.data.walletBalance, before + 2500);

    await settle(); // the webhook for the same payment must not credit it again
    const w = await wallet(tokens.ahmed);
    assert.equal(w.balance, before + 2500);
    const deposit = w.transactions.find((t) => t.type === 'deposit');
    assert.match(deposit.reference, /^pi_/);
    assert.match(deposit.description, /Visa •••• 4242/);
    await assertMoneyBalanced();
  });

  test('a declined card leaves the wallet untouched', async () => {
    const before = await balanceOf(tokens.ahmed);
    const r = await api('POST', '/api/payments/topup', { amount: 1000, token: await card(CARDS.declined) }, tokens.ahmed);
    assert.equal(r.status, 402);
    assert.equal(r.body.data.payment.status, 'failed');
    assert.match(r.body.message, /declined/);
    assert.equal(await balanceOf(tokens.ahmed), before);
  });

  test('a 3-D Secure card is credited once, after the one-time password', async () => {
    const before = await balanceOf(tokens.ahmed);
    const r = await api('POST', '/api/payments/topup', { amount: 1200, token: await card(CARDS.otp) }, tokens.ahmed);
    assert.equal(r.status, 200);
    const p = r.body.data.payment;
    assert.equal(p.status, 'requires_action');
    assert.equal(p.nextAction.type, 'otp');
    assert.match(p.nextAction.hint, /123456/, 'development mode shows the sandbox code');
    assert.equal(await balanceOf(tokens.ahmed), before, 'nothing credited before the OTP');

    // The app sends the OTP straight to the gateway with the publishable key
    const verify = await fetch(`${srv.gatewayUrl}/v1/payment_intents/${p.gatewayIntentId}/verify`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', Authorization: 'Bearer pk_test_vendra' },
      body: JSON.stringify({ otp: '123456' }),
    });
    assert.equal((await verify.json()).status, 'succeeded');

    // Webhook and the app's refresh race each other; the wallet is credited exactly once
    const [a, b] = await Promise.all([
      api('POST', `/api/payments/${p.id}/refresh`, undefined, tokens.ahmed),
      api('POST', `/api/payments/${p.id}/refresh`, undefined, tokens.ahmed),
    ]);
    assert.equal(a.body.data.payment.status, 'succeeded');
    assert.equal(b.body.data.payment.status, 'succeeded');
    await settle();
    assert.equal(await balanceOf(tokens.ahmed), before + 1200);
    await assertMoneyBalanced();
  });

  test('top-ups need a card token and a sensible amount', async () => {
    assert.equal((await api('POST', '/api/payments/topup', { amount: 500 }, tokens.ahmed)).body.code, 'CARD_TOKEN_REQUIRED');
    assert.equal((await api('POST', '/api/payments/topup', { amount: 5, token: await card() }, tokens.ahmed)).body.code, 'AMOUNT_OUT_OF_RANGE');
    assert.equal((await api('POST', '/api/customer/wallet/topup', { amount: 500 }, tokens.ahmed)).status, 404, 'free top-ups are gone');
    assert.equal((await api('POST', '/api/payments/topup', { amount: 500, token: await card() }, tokens.usman)).status, 403);
  });
});

describe('Paying for an order by card', () => {
  test('the card is charged the order total and the money goes into escrow', async () => {
    const before = await balanceOf(tokens.ahmed);
    const r = await api('POST', '/api/payments/checkout', checkoutBody({ token: await card() }), tokens.ahmed);
    assert.equal(r.status, 200, JSON.stringify(r.body));
    const { payment, order } = r.body.data;
    assert.equal(payment.status, 'succeeded');
    assert.equal(payment.orderId, order.id);
    assert.equal(order.paymentMethod, 'card');
    assert.equal(payment.amount, order.totalAmount, 'charged exactly the total');
    assert.equal(await balanceOf(tokens.ahmed), before, 'card money passes through the wallet into escrow');

    const o = (await query('SELECT escrow_status, payment_method FROM orders WHERE id = $1', [order.id])).rows[0];
    assert.deepEqual(o, { escrow_status: 'held', payment_method: 'card' });
    await assertMoneyBalanced();
  });

  test('a cart that cannot be ordered is refused before the card is charged', async () => {
    const r = await api('POST', '/api/payments/checkout', checkoutBody({ token: await card(), items: [{ productId: 2, quantity: 100000 }] }), tokens.ahmed);
    assert.equal(r.status, 409);
    assert.equal(r.body.code, 'INSUFFICIENT_STOCK');
    const charged = await query(`SELECT COUNT(*)::int AS n FROM payments WHERE status = 'succeeded' AND purpose = 'checkout' AND order_id IS NULL`);
    assert.equal(charged.rows[0].n, 0);
  });

  test('if stock runs out during the OTP step, the payment stays in the wallet', async () => {
    const before = await balanceOf(tokens.ahmed);
    const r = await api('POST', '/api/payments/checkout', checkoutBody({ token: await card(CARDS.otp) }), tokens.ahmed);
    const p = r.body.data.payment;
    assert.equal(p.status, 'requires_action');

    const stock = (await query('SELECT private_stock FROM products WHERE id = 2')).rows[0];
    await query('UPDATE products SET private_stock = 0, public_stock = 0 WHERE id = 2'); // sold out meanwhile
    await fetch(`${srv.gatewayUrl}/v1/payment_intents/${p.gatewayIntentId}/verify`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', Authorization: 'Bearer pk_test_vendra' },
      body: JSON.stringify({ otp: '123456' }),
    });
    const done = await api('POST', `/api/payments/${p.id}/refresh`, undefined, tokens.ahmed);
    assert.equal(done.body.data.payment.status, 'succeeded');
    assert.equal(done.body.data.payment.orderId, null);
    assert.match(done.body.data.payment.orderError, /Insufficient stock/);
    assert.equal(await balanceOf(tokens.ahmed), before + p.amount, 'paid money is kept in the wallet');

    await query('UPDATE products SET private_stock = $1 WHERE id = 2', [stock.private_stock]);
    await query('UPDATE products SET public_stock = GREATEST(0, private_stock - buffer - reserved_quantity) WHERE id = 2');
    await settle();
    await assertMoneyBalanced();
  });
});

describe('Withdrawals', () => {
  test('a vendor withdraws to a debit card and the payout lands', async () => {
    const before = await balanceOf(tokens.usman);
    const r = await api('POST', '/api/withdrawals', { amount: 1000, token: await card(CARDS.debit) }, tokens.usman);
    assert.equal(r.status, 201, JSON.stringify(r.body));
    assert.equal(r.body.data.withdrawal.status, 'in_transit');
    assert.equal(r.body.data.walletBalance, before - 1000, 'the wallet is debited straight away');

    await settle();
    const list = (await api('GET', '/api/withdrawals', undefined, tokens.usman)).body.data;
    assert.equal(list[0].status, 'paid');
    assert.match(list[0].gatewayPayoutId, /^po_/);
    const debit = (await wallet(tokens.usman)).transactions.find((t) => t.type === 'withdrawal');
    assert.equal(debit.reference, list[0].gatewayPayoutId);
    assert.match(debit.description, /Visa •••• 5556/);
    await assertMoneyBalanced();
  });

  test('a bounced payout returns the money to the wallet', async () => {
    const before = await balanceOf(tokens.usman);
    const r = await api('POST', '/api/withdrawals', { amount: 800, token: await card(CARDS.bounces) }, tokens.usman);
    assert.equal(r.status, 201);
    assert.equal(await balanceOf(tokens.usman), before - 800);

    await settle();
    const w = (await api('GET', '/api/withdrawals', undefined, tokens.usman)).body.data[0];
    assert.equal(w.status, 'failed');
    assert.match(w.failureMessage, /couldn't process/);
    assert.equal(await balanceOf(tokens.usman), before, 'refunded to the wallet');
    const reversal = (await wallet(tokens.usman)).transactions.find((t) => t.type === 'withdrawal_reversal');
    assert.equal(reversal.amount, 800);
    await assertMoneyBalanced();
  });

  test('withdrawals respect the minimum and the balance', async () => {
    const small = await api('POST', '/api/withdrawals', { amount: 100, token: await card(CARDS.debit) }, tokens.usman);
    assert.equal(small.body.code, 'AMOUNT_OUT_OF_RANGE');
    const bal = await balanceOf(tokens.bilal);
    const tooMuch = await api('POST', '/api/withdrawals', { amount: bal + 1000, token: await card(CARDS.debit) }, tokens.bilal);
    assert.equal(tooMuch.status, 400);
    assert.equal(tooMuch.body.code, 'INSUFFICIENT_BALANCE');
    assert.equal(await balanceOf(tokens.bilal), bal);
  });
});

describe('Webhooks and reconciliation', () => {
  test('unsigned or forged webhooks are rejected', async () => {
    const res = await fetch(`${srv.baseUrl}/api/payments/webhook`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', 'Vendra-Signature': `t=${Math.floor(Date.now() / 1000)},v1=${'0'.repeat(64)}` },
      body: JSON.stringify({ id: 'evt_fake', type: 'payment_intent.succeeded', data: { object: { metadata: { vendra_ref: 'payment:1' } } } }),
    });
    assert.equal(res.status, 400);
  });

  test('the gateway balance matches the books', async () => {
    await settle();
    let rec = (await api('GET', '/api/admin/finance/reconciliation', undefined, tokens.admin)).body.data;
    assert.equal(rec.gateway.reachable, true);
    assert.ok(rec.openingBalances.unfunded > 0, 'demo opening balances have no card payment behind them');
    assert.equal(rec.balanced, true, JSON.stringify(rec));

    // Backing the opening balances with platform funds keeps it balanced
    await require('../src/services/payments.service').fundOpeningBalances();
    rec = (await api('GET', '/api/admin/finance/reconciliation', undefined, tokens.admin)).body.data;
    assert.equal(rec.openingBalances.unfunded, 0);
    assert.equal(rec.balanced, true, JSON.stringify(rec));
    assert.equal(rec.gateway.available, rec.expectedGatewayBalance);
  });

  test('admins see every payment and withdrawal', async () => {
    const p = (await api('GET', '/api/admin/payments', undefined, tokens.admin)).body;
    assert.ok(p.data.length >= 5);
    assert.ok(p.data[0].user.email);
    const failed = (await api('GET', '/api/admin/withdrawals?status=failed', undefined, tokens.admin)).body.data;
    assert.ok(failed.every((w) => w.status === 'failed') && failed.length >= 1);
  });
});

describe('Stalled orders', () => {
  test('an order the store never accepts is cancelled and refunded', async () => {
    const co = await api('POST', '/api/customer/checkout', checkoutBody(), tokens.ahmed);
    assert.equal(co.status, 201);
    // Every pending order of Ahmed's (this one and earlier ones) is past a zero timeout
    const before = await balanceOf(tokens.ahmed);
    const pending = Number((await query(
      `SELECT COALESCE(SUM(total_amount), 0) AS t FROM orders WHERE customer_id = 4 AND status = 'pending'`
    )).rows[0].t);
    await setPolicies({ vendor_accept_timeout_min: 0 });
    const n = await require('../src/services/orderTimeouts.service').cancelStaleOrders();
    await setPolicies({ vendor_accept_timeout_min: 30 });
    assert.ok(n >= 1);

    const o = (await query('SELECT status, escrow_status, cancellation_reason FROM orders WHERE id = $1', [co.body.data.id])).rows[0];
    assert.deepEqual(o, { status: 'cancelled', escrow_status: 'refunded', cancellation_reason: "Store didn't respond in time" });
    assert.equal(await balanceOf(tokens.ahmed), before + pending, 'every stalled order refunded');
    const locks = await query(`SELECT COUNT(*)::int AS n FROM inventory_locks WHERE order_id = $1 AND status = 'active'`, [co.body.data.id]);
    assert.equal(locks.rows[0].n, 0, 'reserved stock released');
    await assertMoneyBalanced();
  });

  test('a ready order no rider takes is cancelled and refunded', async () => {
    const co = await api('POST', '/api/customer/checkout', checkoutBody(), tokens.ahmed);
    const id = co.body.data.id;
    for (const step of ['approve', 'prepare', 'ready-for-pickup']) {
      assert.equal((await api('PUT', `/api/vendor/orders/${id}/${step}`, undefined, tokens.usman)).status, 200);
    }
    await setPolicies({ rider_assign_timeout_min: 0 });
    await require('../src/services/orderTimeouts.service').cancelStaleOrders();
    await setPolicies({ rider_assign_timeout_min: 60 });
    const o = (await query('SELECT status, cancellation_reason FROM orders WHERE id = $1', [id])).rows[0];
    assert.deepEqual(o, { status: 'cancelled', cancellation_reason: 'No rider available' });
    await assertMoneyBalanced();
  });
});

describe('Development and production modes', () => {
  test('public config tells the apps the mode, features and gateway', async () => {
    const c = (await api('GET', '/api/public-config?role=rider')).body.data;
    assert.equal(c.mode, 'development');
    assert.deepEqual(c.features, { manualLocation: true, testCards: true, fastTimers: true, demoLogin: true });
    assert.equal(c.payments.publishableKey, 'pk_test_vendra');
    assert.ok(c.payments.gatewayUrl);
    assert.deepEqual(c.demoAccounts.map((a) => a.email), ['bilal@rider.pk', 'hamza@rider.pk']);
  });

  test('fast timers cap the dispute window without changing the stored policy', async () => {
    await setPolicies({ dispute_window_min: 1440 });
    const p = (await api('GET', '/api/admin/policies', undefined, tokens.admin)).body.data.find((x) => x.key === 'dispute_window_min');
    assert.equal(p.value, 1440);
    assert.equal(p.effectiveValue, 2);
    assert.equal((await api('GET', '/api/public-config')).body.data.disputeWindowMinutes, 2);
  });

  test('riders may post manual positions in development', async () => {
    const r = await api('POST', '/api/rider/location', { lat: 24.86, lng: 67.02, source: 'manual' }, tokens.bilal);
    assert.equal(r.status, 200, JSON.stringify(r.body));
  });

  test('production mode turns every helper off and refuses development secrets', () => {
    const backend = path.join(__dirname, '..');
    const run = (env, code) => execFileSync(process.execPath, ['-e', code], {
      cwd: backend, env: { ...process.env, APP_MODE: 'production', ...env }, encoding: 'utf8',
    });
    const features = JSON.parse(run({}, "process.stdout.write(JSON.stringify(require('./src/config/mode').FEATURES))"));
    assert.deepEqual(features, { manualLocation: false, testCards: false, fastTimers: false, demoLogin: false });

    const check = "try { require('./src/config/mode').assertProductionConfig(); console.log('ok') } catch (e) { console.log(e.message) }";
    assert.match(run({ JWT_SECRET: 'dev-secret', ALLOWED_ORIGINS: '' }, check), /JWT_SECRET.*ALLOWED_ORIGINS/);
    assert.equal(run({ JWT_SECRET: 'x'.repeat(40), ALLOWED_ORIGINS: 'https://admin.vendra.pk' }, check).trim(), 'ok');

    const seed = "require('./src/seed').seed().then(() => console.log('seeded'), (e) => console.log(e.message))";
    assert.match(run({ DATABASE_URL: 'postgresql://nobody@127.0.0.1:1/none' }, seed), /never loaded in production/);
  });
});
