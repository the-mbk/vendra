// ══════════════════════════════════════════════════════════════
// The six anti-abuse gates end to end (VENDRA_SYSTEM_IMPROVEMENTS_AND_
// ABUSE_PREVENTION §2.4) and the audit trail behind them (migration 015):
//   1. False dispute trap   a dispute freezes escrow, nothing is refunded
//                           automatically, the dossier holds the handover proof
//   2. Phantom delivery     the customer's 4-digit code is required
//   3. GPS geofence         delivery only within geofence_m of the pin
//   4. Double-selling POS   reserved units need an explicit override (audited)
//   5. Counter pickup code  self pickup is handed over with the customer's code
//   6. Task hoarding        a rider who never reaches the store loses the task
// Run: TEST_DATABASE_URL=postgresql://... npm test
// ══════════════════════════════════════════════════════════════

const { test, before, after, describe } = require('node:test');
const assert = require('node:assert/strict');
const { resetDatabase, startServer, cardToken, apiClient, query, moneyInvariant } = require('./helpers');

const CLIFTON = { lat: 24.8138, lng: 67.0300 }; // Ahmed's pin
const SADDAR = { lat: 24.8556, lng: 67.0224 };  // Karachi Electronics Hub

let srv;
let api;
const tokens = {};
const ids = {};

async function login(email, role) {
  const r = await api('POST', '/api/auth/login', { email, password: 'password123', role });
  assert.equal(r.status, 200, JSON.stringify(r.body));
  return r.body.data.token;
}

const otpOf = async (id) => (await query('SELECT delivery_otp FROM orders WHERE id = $1', [id])).rows[0].delivery_otp;
const walletOf = async (userId) => Number((await query('SELECT wallet_balance FROM users WHERE id = $1', [userId])).rows[0].wallet_balance);
const orderRow = async (id) => (await query('SELECT * FROM orders WHERE id = $1', [id])).rows[0];
const trustEvents = async (orderId) =>
  (await query('SELECT kind, vendor_id, user_id FROM trust_events WHERE order_id = $1 ORDER BY id', [orderId])).rows;
const wrongCode = (code) => String((Number(code) + 1) % 10000).padStart(4, '0');

async function placeOrder(items, deliveryType = 'delivery') {
  const r = await api('POST', '/api/customer/checkout', deliveryType === 'delivery'
    ? { items, deliveryType, deliveryAddress: 'House 21, Clifton', customerLat: CLIFTON.lat, customerLng: CLIFTON.lng }
    : { items, deliveryType }, tokens.ahmed);
  assert.equal(r.status, 201, JSON.stringify(r.body));
  return r.body.data.id;
}

/** Accepted, packed and ready: delivery orders now wait for a rider */
async function readyOrder(items, deliveryType = 'delivery') {
  const id = await placeOrder(items, deliveryType);
  assert.equal((await api('PUT', `/api/vendor/orders/${id}/approve`, undefined, tokens.usman)).status, 200);
  const o = await api('GET', `/api/vendor/orders/${id}`, undefined, tokens.usman);
  for (const item of o.body.data.items) {
    assert.equal((await api('PUT', `/api/vendor/orders/${id}/items/${item.id}/pack`, { packed: true }, tokens.usman)).status, 200);
  }
  for (const step of ['prepare', 'ready-for-pickup']) {
    const r = await api('PUT', `/api/vendor/orders/${id}/${step}`, undefined, tokens.usman);
    assert.equal(r.status, 200, `${step}: ${JSON.stringify(r.body)}`);
  }
  return id;
}

async function onTheWay(items) {
  const id = await readyOrder(items);
  assert.equal((await api('POST', `/api/rider/tasks/${id}/accept`, undefined, tokens.bilal)).status, 200);
  assert.equal((await api('POST', `/api/rider/orders/${id}/picked`, SADDAR, tokens.bilal)).status, 200);
  assert.equal((await api('POST', `/api/rider/orders/${id}/on-the-way`, undefined, tokens.bilal)).status, 200);
  return id;
}

before(async () => {
  await resetDatabase();
  srv = await startServer();
  api = apiClient(srv.baseUrl);
  tokens.admin = await login('admin@vendra.pk', 'admin');
  tokens.usman = await login('usman@vendor.pk', 'vendor');
  tokens.ahmed = await login('ahmed@customer.pk', 'customer');
  tokens.bilal = await login('bilal@rider.pk', 'rider');
  tokens.hamza = await login('hamza@rider.pk', 'rider');
  for (const [key, email] of [['ahmed', 'ahmed@customer.pk'], ['usman', 'usman@vendor.pk'], ['bilal', 'bilal@rider.pk']]) {
    ids[key] = (await query('SELECT id FROM users WHERE email = $1', [email])).rows[0].id;
  }
  ids.store = (await query('SELECT id FROM vendors WHERE user_id = $1', [ids.usman])).rows[0].id;
  for (let i = 0; i < 2; i++) {
    const r = await api('POST', '/api/payments/topup', { amount: 500000, token: await cardToken(srv.gatewayUrl) }, tokens.ahmed);
    assert.equal(r.status, 200, JSON.stringify(r.body));
  }
  await api('PUT', '/api/rider/status', { isOnline: true, ...SADDAR }, tokens.bilal);
});

after(() => srv.stop());

describe('Gates 2 + 3: phantom delivery (handover code) and GPS geofence', () => {
  test('away from the pin the delivery is refused before any code is checked', async () => {
    const id = await onTheWay([{ productId: 4, quantity: 1 }]);
    const far = await api('POST', `/api/rider/orders/${id}/deliver`, { ...SADDAR, otp: await otpOf(id) }, tokens.bilal);
    assert.equal(far.status, 422);
    assert.equal(far.body.code, 'OUTSIDE_GEOFENCE');
    assert.ok(far.body.distanceMeters > far.body.geofenceMeters);
    assert.equal((await orderRow(id)).status, 'on_the_way');

    // At the pin: no code, then a wrong one, are both refused
    const none = await api('POST', `/api/rider/orders/${id}/deliver`, CLIFTON, tokens.bilal);
    assert.equal(none.body.code, 'OTP_REQUIRED');
    const wrong = await api('POST', `/api/rider/orders/${id}/deliver`, { ...CLIFTON, otp: wrongCode(await otpOf(id)) }, tokens.bilal);
    assert.equal(wrong.status, 422);
    assert.equal(wrong.body.code, 'WRONG_OTP');
    assert.equal((await orderRow(id)).status, 'on_the_way');
    ids.delivered = id;
  });

  test('five wrong codes lock the handover and count against the rider', async () => {
    const id = ids.delivered;
    const code = await otpOf(id);
    let last;
    for (let i = 0; i < 4; i++) {
      last = await api('POST', `/api/rider/orders/${id}/deliver`, { ...CLIFTON, otp: wrongCode(code) }, tokens.bilal);
    }
    assert.equal(last.body.attemptsLeft, 0);
    const locked = await api('POST', `/api/rider/orders/${id}/deliver`, { ...CLIFTON, otp: code }, tokens.bilal);
    assert.equal(locked.status, 429);
    assert.equal(locked.body.code, 'OTP_LOCKED');
    assert.deepEqual(await trustEvents(id), [{ kind: 'handover_lockout', vendor_id: ids.store, user_id: ids.bilal }]);

    const riders = await api('GET', '/api/admin/riders', undefined, tokens.admin);
    assert.equal(riders.body.data.find((r) => r.id === ids.bilal).trust.handoverLockouts, 1);

    // Lock over: the right code at the pin completes it, with the proof recorded
    await query('UPDATE orders SET otp_locked_until = NOW() - INTERVAL \'1 second\' WHERE id = $1', [id]);
    const ok = await api('POST', `/api/rider/orders/${id}/deliver`, { ...CLIFTON, otp: code }, tokens.bilal);
    assert.equal(ok.status, 200, JSON.stringify(ok.body));
    const o = await orderRow(id);
    assert.equal(o.status, 'delivered');
    assert.ok(o.otp_verified_at, 'code verification time recorded');
    assert.deepEqual([o.delivery_lat, o.delivery_lng], [CLIFTON.lat, CLIFTON.lng]);
  });
});

describe('Gate 1: false dispute trap', () => {
  test('a dispute freezes escrow, refunds nothing and survives the release sweep', async () => {
    const id = ids.delivered;
    const before = await walletOf(ids.ahmed);
    const d = await api('POST', '/api/disputes',
      { orderId: id, issueType: 'item_not_received', description: 'The rider never came to my door.' }, tokens.ahmed);
    assert.equal(d.status, 201, JSON.stringify(d.body));
    assert.equal(d.body.data.order.escrowStatus, 'disputed');
    assert.equal(await walletOf(ids.ahmed), before, 'no automatic refund');

    // The dispute window passing does not release (or refund) frozen escrow
    await query('UPDATE orders SET escrow_release_due_at = NOW() - INTERVAL \'1 hour\' WHERE id = $1', [id]);
    await require('../src/services/orderSettlement.service').releaseDueEscrows();
    assert.equal((await orderRow(id)).escrow_status, 'disputed');
    ids.dispute = d.body.data.id;
  });

  test('the dossier carries the handover proof and the parties\' track records', async () => {
    const r = await api('GET', `/api/admin/disputes/${ids.dispute}/dossier`, undefined, tokens.admin);
    assert.equal(r.status, 200, JSON.stringify(r.body));
    const { delivery, history } = r.body.data;
    assert.ok(delivery.handoverCodeVerifiedAt);
    assert.deepEqual(delivery.handover, { lat: CLIFTON.lat, lng: CLIFTON.lng });
    assert.equal(delivery.handoverDistanceFromPinMeters, 0);
    assert.equal(history.customer.earlierClaims, 0);
    assert.deepEqual(history.rider, { deliveries: 1, taskTimeouts: 0, handoverLockouts: 1 });
    assert.equal(history.windowDays, 30);
  });

  test('the admin dismisses it: the store is paid, the customer gets nothing back', async () => {
    const [customer, vendor] = [await walletOf(ids.ahmed), await walletOf(ids.usman)];
    const r = await api('PUT', `/api/admin/disputes/${ids.dispute}/resolve`,
      { resolution: 'release', note: 'Handover code verified at the pin' }, tokens.admin);
    assert.equal(r.status, 200, JSON.stringify(r.body));
    assert.equal(await walletOf(ids.ahmed), customer);
    assert.ok(await walletOf(ids.usman) > vendor);
    assert.equal((await orderRow(ids.delivered)).escrow_status, 'released');
  });
});

describe('Gate 4: double-selling at the POS', () => {
  test('reserved units are refused; an override is audited against the store', async () => {
    const id = await placeOrder([{ productId: 3, quantity: 1 }]);
    await api('PUT', '/api/vendor/products/3', { private_stock: 1 }, tokens.usman);

    const refused = await api('POST', '/api/vendor/pos/sales', { items: [{ productId: 3, quantity: 1 }] }, tokens.usman);
    assert.equal(refused.status, 409);
    assert.equal(refused.body.code, 'RESERVED_STOCK');
    assert.deepEqual(await trustEvents(id), [], 'a refused sale leaves no trace');

    const sale = await api('POST', '/api/vendor/pos/sales',
      { items: [{ productId: 3, quantity: 1, overrideReservation: true }] }, tokens.usman);
    assert.equal(sale.status, 201, JSON.stringify(sale.body));
    assert.equal((await orderRow(id)).status, 'cancelled');
    assert.deepEqual(await trustEvents(id), [{ kind: 'walk_in_override', vendor_id: ids.store, user_id: ids.usman }]);

    const vendors = await api('GET', '/api/admin/vendors', undefined, tokens.admin);
    assert.equal(vendors.body.data.find((v) => v.id === ids.store).trust.walkInOverrides, 1);
    await api('PUT', '/api/vendor/products/3', { private_stock: 20 }, tokens.usman);
  });
});

describe('Gate 5: counter pickup code', () => {
  test('the store can only hand a self-pickup order over with the customer\'s code', async () => {
    const id = await readyOrder([{ productId: 4, quantity: 1 }], 'self_pickup');
    const none = await api('PUT', `/api/vendor/orders/${id}/deliver`, {}, tokens.usman);
    assert.equal(none.status, 400);
    assert.equal(none.body.code, 'OTP_REQUIRED');
    const wrong = await api('PUT', `/api/vendor/orders/${id}/deliver`, { otp: wrongCode(await otpOf(id)) }, tokens.usman);
    assert.equal(wrong.body.code, 'WRONG_OTP');
    assert.equal((await orderRow(id)).status, 'ready_for_pickup');

    const ok = await api('PUT', `/api/vendor/orders/${id}/deliver`, { otp: await otpOf(id) }, tokens.usman);
    assert.equal(ok.status, 200, JSON.stringify(ok.body));
    const o = await orderRow(id);
    assert.equal(o.status, 'delivered');
    assert.ok(o.otp_verified_at);
  });
});

describe('Gate 6: task hoarding', () => {
  const { releaseIdleRiders, cancelStaleOrders } = require('../src/services/orderTimeouts.service');
  const { FEATURES, FAST_TIMER_CAPS } = require('../src/config/mode');

  test('the deadline is a policy the rider app can read', async () => {
    const stored = Number((await query(`SELECT value FROM policies WHERE key = 'rider_pickup_timeout_min'`)).rows[0].value);
    const config = await api('GET', '/api/public-config');
    const expected = FEATURES.fastTimers ? Math.min(stored, FAST_TIMER_CAPS.rider_pickup_timeout_min) : stored;
    assert.equal(config.body.data.riderPickupTimeoutMinutes, expected);
  });

  test('a rider who never reaches the store loses the task; it goes back to the pool', async () => {
    const id = await readyOrder([{ productId: 4, quantity: 1 }]);
    assert.equal((await api('POST', `/api/rider/tasks/${id}/accept`, undefined, tokens.bilal)).status, 200);

    assert.equal(await releaseIdleRiders(), 0, 'inside the deadline nothing happens');
    // Accepted long ago, and the store marked it ready even earlier
    await query(`UPDATE orders SET assigned_at = NOW() - INTERVAL '2 hours', ready_at = NOW() - INTERVAL '3 hours' WHERE id = $1`, [id]);
    assert.equal(await releaseIdleRiders(), 1);

    const o = await orderRow(id);
    assert.equal(o.status, 'ready_for_pickup');
    assert.equal(o.rider_user_id, null);
    assert.ok(o.rider_released_at);
    assert.deepEqual(await trustEvents(id), [{ kind: 'rider_task_timeout', vendor_id: ids.store, user_id: ids.bilal }]);
    const note = await query(`SELECT 1 FROM notifications WHERE user_id = $1 AND order_id = $2 AND type = 'task_released'`, [ids.bilal, id]);
    assert.equal(note.rows.length, 1);

    // The "no rider" clock restarts from the release, so the order isn't cancelled at once
    await cancelStaleOrders();
    assert.equal((await orderRow(id)).status, 'ready_for_pickup');

    // The lapsed rider can't take it back; it is hidden from their task list
    const tasks = await api('GET', '/api/rider/tasks', undefined, tokens.bilal);
    assert.ok(!tasks.body.data.tasks.some((t) => t.id === id));
    const again = await api('POST', `/api/rider/tasks/${id}/accept`, undefined, tokens.bilal);
    assert.equal(again.status, 409);
    assert.equal(again.body.code, 'TASK_LAPSED');

    // Another rider nearby can
    await api('PUT', '/api/rider/status', { isOnline: true, ...SADDAR }, tokens.hamza);
    assert.equal((await api('POST', `/api/rider/tasks/${id}/accept`, undefined, tokens.hamza)).status, 200);
    const riders = await api('GET', '/api/admin/riders', undefined, tokens.admin);
    assert.equal(riders.body.data.find((r) => r.id === ids.bilal).trust.taskTimeouts, 1);
  });

  test('a rider waiting at the store is not hoarding', async () => {
    const id = await readyOrder([{ productId: 4, quantity: 1 }]);
    assert.equal((await api('POST', `/api/rider/tasks/${id}/accept`, undefined, tokens.bilal)).status, 200);
    assert.equal((await api('POST', `/api/rider/orders/${id}/arrived`, SADDAR, tokens.bilal)).status, 200);
    await query(`UPDATE orders SET assigned_at = NOW() - INTERVAL '2 hours' WHERE id = $1`, [id]);
    assert.equal(await releaseIdleRiders(), 0);
    assert.equal((await orderRow(id)).rider_user_id, ids.bilal);
  });

  test('money still balances after all of the above', async () => {
    const m = await moneyInvariant();
    assert.equal(m.accounted.toFixed(2), m.deposits.toFixed(2));
    assert.equal(m.pool.toFixed(2), m.held.toFixed(2));
  });
});
