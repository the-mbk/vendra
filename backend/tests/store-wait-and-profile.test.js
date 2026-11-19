// ══════════════════════════════════════════════════════════════
// Store wait limit, store-confirmed handover, chat counterpart, own profile
//   - a rider who checks in at the store and then sits there loses the
//     delivery after rider_store_wait_max_min (no waiting pay for it)
//   - the store can confirm the handover once the rider has checked in,
//     which stops the waiting clock
//   - waiting pay never counts past the limit
//   - the chat says who you are talking to
//   - customers and riders edit their name, phone and photo
// Run: TEST_DATABASE_URL=postgresql://... npm test
// ══════════════════════════════════════════════════════════════

const { test, before, after, describe } = require('node:test');
const assert = require('node:assert/strict');
const { resetDatabase, startServer, cardToken, apiClient, query, moneyInvariant } = require('./helpers');

const CLIFTON = { lat: 24.8138, lng: 67.0300 };
const SADDAR = { lat: 24.8556, lng: 67.0224 };
// 1×1 transparent PNG
const PNG = Buffer.from('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII=', 'base64');

let srv;
let api;
const tokens = {};
const ids = {};

async function login(email, role) {
  const r = await api('POST', '/api/auth/login', { email, password: 'password123', role });
  assert.equal(r.status, 200, JSON.stringify(r.body));
  return r.body.data;
}

const orderRow = async (id) => (await query('SELECT * FROM orders WHERE id = $1', [id])).rows[0];

/** A delivery order packed and marked ready by the store */
async function readyOrder() {
  const placed = await api('POST', '/api/customer/checkout', {
    items: [{ productId: 4, quantity: 1 }], deliveryType: 'delivery',
    deliveryAddress: 'House 21, Clifton', customerLat: CLIFTON.lat, customerLng: CLIFTON.lng,
  }, tokens.ahmed);
  assert.equal(placed.status, 201, JSON.stringify(placed.body));
  const id = placed.body.data.id;
  assert.equal((await api('PUT', `/api/vendor/orders/${id}/approve`, undefined, tokens.usman)).status, 200);
  const o = await api('GET', `/api/vendor/orders/${id}`, undefined, tokens.usman);
  for (const item of o.body.data.items) await api('PUT', `/api/vendor/orders/${id}/items/${item.id}/pack`, { packed: true }, tokens.usman);
  for (const step of ['prepare', 'ready-for-pickup']) {
    assert.equal((await api('PUT', `/api/vendor/orders/${id}/${step}`, undefined, tokens.usman)).status, 200);
  }
  return id;
}

before(async () => {
  await resetDatabase();
  srv = await startServer();
  api = apiClient(srv.baseUrl);
  for (const [key, email, role] of [
    ['admin', 'admin@vendra.pk', 'admin'], ['usman', 'usman@vendor.pk', 'vendor'],
    ['ahmed', 'ahmed@customer.pk', 'customer'], ['bilal', 'bilal@rider.pk', 'rider'], ['hamza', 'hamza@rider.pk', 'rider'],
  ]) {
    const d = await login(email, role);
    tokens[key] = d.token;
    ids[key] = d.user.id;
  }
  const topup = await api('POST', '/api/payments/topup', { amount: 500000, token: await cardToken(srv.gatewayUrl) }, tokens.ahmed);
  assert.equal(topup.status, 200, JSON.stringify(topup.body));
  await api('PUT', '/api/rider/status', { isOnline: true, ...SADDAR }, tokens.bilal);
  await api('PUT', '/api/rider/status', { isOnline: true, ...SADDAR }, tokens.hamza);
});

after(() => srv.stop());

describe('Store wait limit', () => {
  const { releaseIdleRiders } = require('../src/services/orderTimeouts.service');
  const { FEATURES, FAST_TIMER_CAPS } = require('../src/config/mode');

  test('the limit is a policy the apps can read', async () => {
    const stored = Number((await query(`SELECT value FROM policies WHERE key = 'rider_store_wait_max_min'`)).rows[0].value);
    assert.equal(stored, 15);
    const config = await api('GET', '/api/public-config');
    const expected = FEATURES.fastTimers ? Math.min(stored, FAST_TIMER_CAPS.rider_store_wait_max_min) : stored;
    assert.equal(config.body.data.riderStoreWaitMaxMinutes, expected);
  });

  test('a rider who checks in and then sits at the store loses the delivery', async () => {
    const id = await readyOrder();
    assert.equal((await api('POST', `/api/rider/tasks/${id}/accept`, undefined, tokens.bilal)).status, 200);
    assert.equal((await api('POST', `/api/rider/orders/${id}/arrived`, SADDAR, tokens.bilal)).status, 200);

    // The store sees who is at the counter, by short name
    const seen = await api('GET', `/api/vendor/orders/${id}`, undefined, tokens.usman);
    assert.equal(seen.body.data.rider_name, 'Bilal H.');
    assert.ok(seen.body.data.rider_arrived_at);

    assert.equal(await releaseIdleRiders(), 0, 'inside the limit nothing happens');
    await query(`UPDATE orders SET rider_arrived_at = NOW() - INTERVAL '2 hours' WHERE id = $1`, [id]);
    assert.equal(await releaseIdleRiders(), 1);

    const o = await orderRow(id);
    assert.equal(o.status, 'ready_for_pickup');
    assert.equal(o.rider_user_id, null);
    assert.equal(o.rider_arrived_at, null, 'the next rider starts with a fresh check-in');
    const events = await query('SELECT kind, user_id FROM trust_events WHERE order_id = $1', [id]);
    assert.deepEqual(events.rows, [{ kind: 'rider_task_timeout', user_id: ids.bilal }]);
    const note = await query(
      `SELECT body FROM notifications WHERE user_id = $1 AND order_id = $2 AND type = 'task_released'`, [ids.bilal, id]);
    assert.match(note.rows[0].body, /of arriving/);

    // Another rider takes it over
    assert.equal((await api('POST', `/api/rider/tasks/${id}/accept`, undefined, tokens.hamza)).status, 200);
    ids.handoverOrder = id;
  });

  test('the store can hand over only once the rider has checked in', async () => {
    const id = ids.handoverOrder;
    const early = await api('PUT', `/api/vendor/orders/${id}/hand-over`, undefined, tokens.usman);
    assert.equal(early.status, 409);
    assert.equal(early.body.code, 'RIDER_NOT_ARRIVED');

    assert.equal((await api('POST', `/api/rider/orders/${id}/arrived`, SADDAR, tokens.hamza)).status, 200);
    // Arrived 30 min ago: waiting pay must stop at the limit
    await query(`UPDATE orders SET rider_arrived_at = NOW() - INTERVAL '30 minutes' WHERE id = $1`, [id]);
    const done = await api('PUT', `/api/vendor/orders/${id}/hand-over`, undefined, tokens.usman);
    assert.equal(done.status, 200, JSON.stringify(done.body));
    assert.equal(done.body.data.status, 'picked');

    const o = await orderRow(id);
    assert.equal(o.pickup_confirmed_by, 'store');
    assert.ok(o.picked_at);
    const told = await query(`SELECT 1 FROM notifications WHERE user_id = $1 AND order_id = $2 AND type = 'order_picked'`, [ids.hamza, id]);
    assert.equal(told.rows.length, 1, 'the rider hears that the store handed it over');

    assert.equal((await api('PUT', `/api/vendor/orders/${id}/hand-over`, undefined, tokens.usman)).status, 409, 'only once');

    await api('POST', `/api/rider/orders/${id}/on-the-way`, undefined, tokens.hamza);
    const otp = (await orderRow(id)).delivery_otp;
    const delivered = await api('POST', `/api/rider/orders/${id}/deliver`, { ...CLIFTON, otp }, tokens.hamza);
    assert.equal(delivered.status, 200, JSON.stringify(delivered.body));
    const limit = (await api('GET', '/api/public-config')).body.data.riderStoreWaitMaxMinutes;
    assert.equal(delivered.body.data.waitMinutes, limit, 'waiting pay counts up to the limit only');
  });

  test('a rider who confirms the pickup is recorded as such', async () => {
    const id = await readyOrder();
    assert.equal((await api('POST', `/api/rider/tasks/${id}/accept`, undefined, tokens.hamza)).status, 200);
    assert.equal((await api('POST', `/api/rider/orders/${id}/picked`, SADDAR, tokens.hamza)).status, 200);
    assert.equal((await orderRow(id)).pickup_confirmed_by, 'rider');
    ids.chatOrder = id;
  });
});

describe('Chat counterpart', () => {
  test('each side sees who they are talking to; phones only while the delivery is open', async () => {
    const id = ids.chatOrder;
    const forCustomer = await api('GET', `/api/orders/${id}/messages`, undefined, tokens.ahmed);
    assert.equal(forCustomer.status, 200);
    assert.equal(forCustomer.body.data.with.role, 'rider');
    assert.equal(forCustomer.body.data.with.name, 'Hamza S.');
    assert.ok(forCustomer.body.data.with.phone);
    assert.ok(forCustomer.body.data.with.vehicleType);

    const forRider = await api('GET', `/api/orders/${id}/messages`, undefined, tokens.hamza);
    assert.equal(forRider.body.data.with.role, 'customer');
    assert.equal(forRider.body.data.with.name, 'Ahmed R.');
    assert.equal(forRider.body.data.with.vehicleType, null);

    await api('POST', `/api/rider/orders/${id}/on-the-way`, undefined, tokens.hamza);
    const otp = (await orderRow(id)).delivery_otp;
    assert.equal((await api('POST', `/api/rider/orders/${id}/deliver`, { ...CLIFTON, otp }, tokens.hamza)).status, 200);
    const after = await api('GET', `/api/orders/${id}/messages`, undefined, tokens.ahmed);
    assert.equal(after.body.data.with.name, 'Hamza S.');
    assert.equal(after.body.data.with.phone, null);
  });
});

describe('Own profile', () => {
  test('a customer changes name and phone; the phone is normalised and validated', async () => {
    const bad = await api('PUT', '/api/auth/profile', { phone: '12345' }, tokens.ahmed);
    assert.equal(bad.status, 400);
    const shortName = await api('PUT', '/api/auth/profile', { fullName: 'A' }, tokens.ahmed);
    assert.equal(shortName.status, 400);

    const ok = await api('PUT', '/api/auth/profile', { fullName: '  Ahmed   Raza Khan ', phone: '+92 300 7654321' }, tokens.ahmed);
    assert.equal(ok.status, 200, JSON.stringify(ok.body));
    assert.deepEqual([ok.body.data.fullName, ok.body.data.phone], ['Ahmed Raza Khan', '0300-7654321']);
    const me = await api('GET', '/api/auth/me', undefined, tokens.ahmed);
    assert.equal(me.body.data.fullName, 'Ahmed Raza Khan');
  });

  test('an approved rider keeps the CNIC name but can change phone and photo', async () => {
    const locked = await api('PUT', '/api/auth/profile', { fullName: 'Someone Else' }, tokens.bilal);
    assert.equal(locked.status, 409);
    assert.equal(locked.body.code, 'NAME_LOCKED');
    assert.equal((await api('PUT', '/api/auth/profile', { fullName: 'Bilal Hussain', phone: '0311-2223334' }, tokens.bilal)).status, 200,
      'resending the same name is fine');

    const form = new FormData();
    form.append('image', new Blob([PNG], { type: 'image/png' }), 'me.png');
    const up = await api('POST', '/api/auth/profile/photo', form, tokens.bilal);
    assert.equal(up.status, 200, JSON.stringify(up.body));
    assert.match(up.body.data.avatarUrl, /^\/uploads\/products\//);
    const me = await api('GET', '/api/auth/me', undefined, tokens.bilal);
    assert.equal(me.body.data.avatarUrl, up.body.data.avatarUrl);

    const removed = await api('DELETE', '/api/auth/profile/photo', undefined, tokens.bilal);
    assert.equal(removed.body.data.avatarUrl, null);
  });

  test('store staff signed in with a PIN cannot edit the owner profile', async () => {
    const made = await api('POST', '/api/vendor/staff', { fullName: 'Ali Cashier', role: 'cashier', pin: '4321' }, tokens.usman);
    assert.equal(made.status, 201, JSON.stringify(made.body));
    const sw = await api('POST', '/api/vendor/staff/switch', { staffId: made.body.data.id, pin: '4321' }, tokens.usman);
    assert.equal(sw.status, 200, JSON.stringify(sw.body));
    const r = await api('PUT', '/api/auth/profile', { fullName: 'Nope' }, sw.body.data.token);
    assert.ok([401, 403].includes(r.status), JSON.stringify(r.body));
    assert.equal((await api('PUT', '/api/auth/profile', { fullName: 'Nope' })).status, 401, 'signed out');
  });

  test('money still balances', async () => {
    const m = await moneyInvariant();
    assert.equal(m.accounted.toFixed(2), m.deposits.toFixed(2));
  });
});
