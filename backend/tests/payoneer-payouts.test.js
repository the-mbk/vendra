// ══════════════════════════════════════════════════════════════
// Withdrawals to Payoneer (PAYOUT_PROVIDER=payoneer) against the in-process
// Payoneer simulator: link an account on Payoneer's registration page,
// wait for approval (IPCN), withdraw in USD, and get the money back when
// a payout fails.
// Run: TEST_DATABASE_URL=postgresql://... npm test
// ══════════════════════════════════════════════════════════════

process.env.PAYOUT_PROVIDER = 'payoneer';

const { test, before, after, describe } = require('node:test');
const assert = require('node:assert/strict');
const { resetDatabase, startServer, cardToken, apiClient, query, moneyInvariant } = require('./helpers');
const { createPayoneerSim } = require('../payoneer-sim/src/app');

let srv;
let sim;
let api;
const tokens = {};

async function login(email, role) {
  const r = await api('POST', '/api/auth/login', { email, password: 'password123', role });
  assert.equal(r.status, 200, JSON.stringify(r.body));
  return r.body.data.token;
}

/** What the user does in the browser: open the link and submit Payoneer's form */
async function signUpAtPayoneer(url, { email, name = 'Test Payee', mode = 'new' }) {
  const page = await fetch(url);
  assert.equal(page.status, 200);
  assert.match(await page.text(), /Get paid by Vendra/);
  const token = new URL(url).searchParams.get('token');
  const res = await fetch(new URL('/partners/sign-up', url), {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({ token, mode, email, name, password: 'x', bank: 'PK36SCBL0000001123456702' }).toString(),
    redirect: 'manual',
  });
  return res;
}

before(async () => {
  await resetDatabase();
  srv = await startServer();
  api = apiClient(srv.baseUrl);
  sim = createPayoneerSim({ approvalDelaySec: 0, payoutDelaySec: 0 });
  await new Promise((resolve) => sim.server.listen(0, resolve));
  const simUrl = `http://127.0.0.1:${sim.server.address().port}`;
  sim.setPublicUrl(simUrl);
  sim.setIpcnUrl(`${srv.baseUrl}/api/payouts/payoneer/ipcn?token=ipcn_vendra`);
  process.env.PAYONEER_API_URL = simUrl;
  process.env.PUBLIC_API_URL = srv.baseUrl;

  tokens.ahmed = await login('ahmed@customer.pk', 'customer');
  tokens.fatima = await login('fatima@customer.pk', 'customer');
  for (const t of [tokens.ahmed, tokens.fatima]) {
    const r = await api('POST', '/api/payments/topup', { amount: 20000, token: await cardToken(srv.gatewayUrl) }, t);
    assert.equal(r.status, 200, JSON.stringify(r.body));
  }
});

after(async () => {
  await new Promise((resolve) => sim?.server.close(resolve));
  sim?.close();
  await srv?.stop();
});

const balanceOf = async (token) => (await api('GET', '/api/wallet', undefined, token)).body.data.balance;

describe('Withdrawals to Payoneer', () => {
  test('the apps are told withdrawals go to Payoneer', async () => {
    const r = await api('GET', '/api/public-config');
    assert.equal(r.body.data.payments.payoutsTo, 'payoneer');
  });

  test('no Payoneer account yet: withdrawing asks to link one', async () => {
    const acct = await api('GET', '/api/payouts/account', undefined, tokens.ahmed);
    assert.deepEqual({ provider: acct.body.data.provider, required: acct.body.data.required, account: acct.body.data.account },
      { provider: 'payoneer', required: true, account: null });
    const w = await api('POST', '/api/withdrawals', { amount: 5000 }, tokens.ahmed);
    assert.equal(w.status, 409);
    assert.equal(w.body.code, 'PAYOUT_ACCOUNT_REQUIRED');
  });

  test('linking: Payoneer\'s page, then pending until Payoneer approves', async () => {
    const ob = await api('POST', '/api/payouts/account/onboarding', undefined, tokens.ahmed);
    assert.equal(ob.status, 200, JSON.stringify(ob.body));
    const res = await signUpAtPayoneer(ob.body.data.url, { email: 'ahmed@customer.pk', name: 'Ahmed Raza' });
    assert.equal(res.status, 303);
    assert.equal(res.headers.get('location'), `${srv.baseUrl}/api/payouts/onboarding/done`, 'back to the "return to the app" page');

    const acct = await api('GET', '/api/payouts/account', undefined, tokens.ahmed);
    assert.deepEqual(acct.body.data.account, { id: 'vendra-4', status: 'pending', detailsSubmitted: true, payoutsEnabled: false });
    const w = await api('POST', '/api/withdrawals', { amount: 5000 }, tokens.ahmed);
    assert.equal(w.body.code, 'PAYOUT_ACCOUNT_PENDING');
  });

  test('Payoneer\'s approval arrives by IPCN', async () => {
    await sim.tick();
    const u = (await query('SELECT payoneer_status FROM users WHERE id = 4')).rows[0];
    assert.equal(u.payoneer_status, 'active', 'set by the callback, before the app asks');
  });

  test('a withdrawal is paid out in USD and lands in the Payoneer balance', async () => {
    const before = await balanceOf(tokens.ahmed);
    const w = await api('POST', '/api/withdrawals', { amount: 5000 }, tokens.ahmed);
    assert.equal(w.status, 201, JSON.stringify(w.body));
    const wd = w.body.data.withdrawal;
    assert.equal(wd.provider, 'payoneer');
    assert.equal(wd.status, 'in_transit');
    assert.equal(wd.gatewayAmount, 17.86, 'Rs 5,000 at 280 per USD');
    assert.equal(wd.gatewayCurrency, 'usd');
    assert.equal(wd.destinationAccount, 'vendra-4');
    assert.equal(await balanceOf(tokens.ahmed), before - 5000);

    await sim.tick();
    const row = (await query('SELECT status FROM withdrawals WHERE id = $1', [wd.id])).rows[0];
    assert.equal(row.status, 'paid');
    assert.equal(sim.payee('vendra-4').balance, 1786, 'cents at Payoneer');
    const n = await query(`SELECT body FROM notifications WHERE user_id = 4 AND type = 'withdrawal_paid' ORDER BY id DESC LIMIT 1`);
    assert.match(n.rows[0].body, /Payoneer balance/);

    const portal = await api('POST', '/api/payouts/account/dashboard', undefined, tokens.ahmed);
    assert.match(portal.body.data.url, /\/payee\/vendra-4$/);
  });

  test('a failed payout returns the money to the wallet', async () => {
    const ob = await api('POST', '/api/payouts/account/onboarding', undefined, tokens.fatima);
    await signUpAtPayoneer(ob.body.data.url, { email: 'fatima+fail@customer.pk', mode: 'existing' });
    await sim.tick();
    const before = await balanceOf(tokens.fatima);
    const w = await api('POST', '/api/withdrawals', { amount: 2000 }, tokens.fatima);
    assert.equal(w.status, 201, JSON.stringify(w.body));
    await sim.tick();
    const row = (await query('SELECT status, failure_message FROM withdrawals WHERE id = $1', [w.body.data.withdrawal.id])).rows[0];
    assert.equal(row.status, 'failed');
    assert.ok(row.failure_message);
    assert.equal(await balanceOf(tokens.fatima), before, 'refunded');
  });

  test('a missed callback is caught up by the sweep', async () => {
    sim.setIpcnUrl(null);
    const w = await api('POST', '/api/withdrawals', { amount: 1000 }, tokens.ahmed);
    await sim.tick();
    assert.equal((await query('SELECT status FROM withdrawals WHERE id = $1', [w.body.data.withdrawal.id])).rows[0].status, 'in_transit');
    await require('../src/services/payments.service').reconcileOpen();
    assert.equal((await query('SELECT status FROM withdrawals WHERE id = $1', [w.body.data.withdrawal.id])).rows[0].status, 'paid');
    sim.setIpcnUrl(`${srv.baseUrl}/api/payouts/payoneer/ipcn?token=ipcn_vendra`);
  });

  test('callbacks without the shared token are refused', async () => {
    const r = await fetch(`${srv.baseUrl}/api/payouts/payoneer/ipcn?token=wrong&APPROVED&apuid=vendra-4`);
    assert.equal(r.status, 403);
  });

  test('the books still balance', async () => {
    const m = await moneyInvariant();
    assert.equal(m.accounted.toFixed(2), m.deposits.toFixed(2));
    assert.equal(m.pool.toFixed(2), m.held.toFixed(2));
  });
});
