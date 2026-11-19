// ══════════════════════════════════════════════════════════════
// VENDRA_FUTURE_UIUX_USE_CASES_AND_FUNCTIONALITIES, the server side:
//   §2.2  delivery note + customer ↔ rider chat (no phone numbers needed)
//   §4.2  demand map for idle riders
//   §5.1  live fleet map data
//   §5.2  escrow settlement preview and manual release
//   §5.3  admin audit trail (append-only)
// Run: TEST_DATABASE_URL=postgresql://... npm test
// ══════════════════════════════════════════════════════════════

const { test, before, after, describe } = require('node:test');
const assert = require('node:assert/strict');
const { resetDatabase, startServer, cardToken, apiClient, query } = require('./helpers');

const CLIFTON = { lat: 24.8138, lng: 67.0300 };
const SADDAR = { lat: 24.8556, lng: 67.0224 };

let srv;
let api;
const tokens = {};
let orderId;

async function login(email, role) {
  const r = await api('POST', '/api/auth/login', { email, password: 'password123', role });
  assert.equal(r.status, 200, JSON.stringify(r.body));
  return r.body.data.token;
}

const otpOf = async (id) => (await query('SELECT delivery_otp FROM orders WHERE id = $1', [id])).rows[0].delivery_otp;
const chat = (id, token) => api('GET', `/api/orders/${id}/messages`, undefined, token);
const say = (id, body, token) => api('POST', `/api/orders/${id}/messages`, { body }, token);

before(async () => {
  await resetDatabase();
  srv = await startServer();
  api = apiClient(srv.baseUrl);
  tokens.admin = await login('admin@vendra.pk', 'admin');
  tokens.usman = await login('usman@vendor.pk', 'vendor');
  tokens.ahmed = await login('ahmed@customer.pk', 'customer');
  tokens.fatima = await login('fatima@customer.pk', 'customer');
  tokens.bilal = await login('bilal@rider.pk', 'rider');
  tokens.hamza = await login('hamza@rider.pk', 'rider');
  const topup = await api('POST', '/api/payments/topup', { amount: 500000, token: await cardToken(srv.gatewayUrl) }, tokens.ahmed);
  assert.equal(topup.status, 200, JSON.stringify(topup.body));
  await api('PUT', '/api/rider/status', { isOnline: true, ...SADDAR }, tokens.bilal);
});

after(() => srv.stop());

describe('§2.2 Delivery note and order chat', () => {
  test('a note for the rider is saved at checkout; an overlong one is refused', async () => {
    const body = {
      items: [{ productId: 4, quantity: 1 }], deliveryType: 'delivery',
      deliveryAddress: 'House 21, Clifton', customerLat: CLIFTON.lat, customerLng: CLIFTON.lng,
    };
    const tooLong = await api('POST', '/api/customer/checkout', { ...body, deliveryNote: 'x'.repeat(201) }, tokens.ahmed);
    assert.equal(tooLong.status, 400);

    const placed = await api('POST', '/api/customer/checkout', { ...body, deliveryNote: '  Gate code 402, ring twice  ' }, tokens.ahmed);
    assert.equal(placed.status, 201, JSON.stringify(placed.body));
    orderId = placed.body.data.id;
    const mine = await api('GET', `/api/customer/orders/${orderId}`, undefined, tokens.ahmed);
    assert.equal(mine.body.data.deliveryNote, 'Gate code 402, ring twice');
  });

  test('before a rider accepts there is no one to chat with, and the task hides the note', async () => {
    assert.equal((await api('PUT', `/api/vendor/orders/${orderId}/approve`, undefined, tokens.usman)).status, 200);
    const o = await api('GET', `/api/vendor/orders/${orderId}`, undefined, tokens.usman);
    for (const item of o.body.data.items) await api('PUT', `/api/vendor/orders/${orderId}/items/${item.id}/pack`, { packed: true }, tokens.usman);
    for (const step of ['prepare', 'ready-for-pickup']) await api('PUT', `/api/vendor/orders/${orderId}/${step}`, undefined, tokens.usman);

    const early = await say(orderId, 'Hello?', tokens.ahmed);
    assert.equal(early.status, 409);
    assert.equal(early.body.code, 'CHAT_CLOSED');

    const tasks = await api('GET', '/api/rider/tasks', undefined, tokens.bilal);
    assert.equal(tasks.body.data.tasks.find((t) => t.id === orderId).deliveryNote, null);
  });

  test('the customer and the assigned rider talk; nobody else can read it', async () => {
    const accepted = await api('POST', `/api/rider/tasks/${orderId}/accept`, undefined, tokens.bilal);
    assert.equal(accepted.status, 200, JSON.stringify(accepted.body));
    assert.equal(accepted.body.data.deliveryNote, 'Gate code 402, ring twice');

    assert.equal((await say(orderId, 'I am outside the main gate', tokens.ahmed)).status, 201);
    const reply = await say(orderId, '  On my way, 5 minutes  ', tokens.bilal);
    assert.equal(reply.status, 201);
    assert.deepEqual([reply.body.data.senderRole, reply.body.data.body], ['rider', 'On my way, 5 minutes']);

    const thread = await chat(orderId, tokens.bilal);
    assert.equal(thread.body.data.open, true);
    assert.deepEqual(thread.body.data.messages.map((m) => m.senderRole), ['customer', 'rider']);

    assert.equal((await chat(orderId, tokens.hamza)).status, 404, 'another rider');
    assert.equal((await chat(orderId, tokens.fatima)).status, 404, 'another customer');
    assert.equal((await chat(orderId, tokens.usman)).status, 404, 'the store');
    assert.equal((await say(orderId, '   ', tokens.ahmed)).status, 400);
    assert.equal((await say(orderId, 'x'.repeat(501), tokens.ahmed)).status, 400);
  });

  test('after delivery the thread is read-only evidence', async () => {
    await api('POST', `/api/rider/orders/${orderId}/picked`, SADDAR, tokens.bilal);
    await api('POST', `/api/rider/orders/${orderId}/on-the-way`, undefined, tokens.bilal);
    const done = await api('POST', `/api/rider/orders/${orderId}/deliver`, { ...CLIFTON, otp: await otpOf(orderId) }, tokens.bilal);
    assert.equal(done.status, 200, JSON.stringify(done.body));

    const closed = await say(orderId, 'Thanks!', tokens.ahmed);
    assert.equal(closed.body.code, 'CHAT_CLOSED');
    const thread = await chat(orderId, tokens.ahmed);
    assert.equal(thread.body.data.open, false);
    assert.equal(thread.body.data.messages.length, 2);

    const admin = await api('GET', `/api/admin/orders/${orderId}`, undefined, tokens.admin);
    assert.equal(admin.body.data.deliveryNote, 'Gate code 402, ring twice');
    assert.equal(admin.body.data.messages.length, 2);
    await assert.rejects(query('UPDATE order_messages SET body = $1', ['edited']), /append-only/);
  });
});

describe('§4.2 Demand map and §5.1 fleet map', () => {
  test('idle riders see which nearby stores are busy (counts only)', async () => {
    const r = await api('GET', '/api/rider/demand', undefined, tokens.bilal);
    assert.equal(r.status, 200);
    const zone = r.body.data.zones.find((z) => z.storeName === 'Karachi Electronics Hub');
    assert.ok(zone, JSON.stringify(r.body.data));
    assert.ok(zone.ordersLastHour >= 1);
    assert.ok(['high', 'medium', 'low'].includes(zone.level));
    assert.equal(zone.customerName, undefined);
  });

  test('the fleet view carries positions for the live map', async () => {
    const r = await api('GET', '/api/admin/fleet', undefined, tokens.admin);
    assert.equal(r.status, 200);
    const bilal = r.body.data.riders.find((x) => x.name === 'Bilal Hussain');
    assert.deepEqual([bilal.lat, bilal.lng], [SADDAR.lat, SADDAR.lng], 'last location ping (sent when going online)');
    const hamza = r.body.data.riders.find((x) => x.name === 'Hamza Sheikh');
    assert.equal(hamza.lat, null, 'offline riders are not placed on the map');
    const store = r.body.data.stores.find((s) => s.name === 'Karachi Electronics Hub');
    assert.deepEqual([store.lat, store.lng], [SADDAR.lat, SADDAR.lng]);
    const today = r.body.data.deliveries.find((d) => d.id === orderId);
    assert.deepEqual(today.customer, CLIFTON);
  });
});

describe('§5.2 Escrow settlement and §5.3 audit trail', () => {
  test('the settlement preview shows what is due, and a manual run releases it (audited)', async () => {
    await query(`UPDATE orders SET escrow_release_due_at = NOW() - INTERVAL '1 minute' WHERE id = $1`, [orderId]);
    const preview = await api('GET', '/api/admin/settlement', undefined, tokens.admin);
    assert.equal(preview.status, 200);
    assert.ok(preview.body.data.dueNow.orders >= 1);

    const run = await api('POST', '/api/admin/settlement/run', undefined, tokens.admin);
    assert.equal(run.status, 200);
    assert.ok(run.body.data.released >= 1);
    assert.equal((await query('SELECT escrow_status FROM orders WHERE id = $1', [orderId])).rows[0].escrow_status, 'released');

    const again = await api('POST', '/api/admin/settlement/run', undefined, tokens.admin);
    assert.equal(again.body.data.released, 0);
    assert.equal((await api('POST', '/api/admin/settlement/run', undefined, tokens.usman)).status, 403);
  });

  test('admin actions are recorded with who, what and the before/after values', async () => {
    await api('PUT', '/api/admin/products/2/hide', undefined, tokens.admin);
    await api('PUT', '/api/admin/policies', { values: { commission_pct: 12, delivery_fee: 150 } }, tokens.admin);

    const log = await api('GET', '/api/admin/audit-log', undefined, tokens.admin);
    assert.equal(log.status, 200);
    const [policy, hidden, settled] = log.body.data;
    assert.equal(policy.action, 'policy_changed');
    assert.equal(policy.adminName, 'Vendra Admin');
    assert.deepEqual(policy.details.changes.map((c) => [c.key, c.from, c.to]), [['commission_pct', 10, 12]], 'unchanged values are not logged');
    assert.equal(hidden.action, 'product_hidden');
    assert.equal(hidden.targetId, 2);
    assert.equal(settled.action, 'escrow_settled');

    const filtered = await api('GET', '/api/admin/audit-log?action=product_hidden', undefined, tokens.admin);
    assert.deepEqual(filtered.body.data.map((a) => a.action), ['product_hidden']);
    await assert.rejects(query('DELETE FROM admin_audit_log'), /append-only/);
  });

  test('a password reset is logged without the temporary password', async () => {
    const r = await api('PUT', '/api/admin/users/5/reset-password', undefined, tokens.admin);
    assert.equal(r.status, 200);
    const entry = (await api('GET', '/api/admin/audit-log?action=password_reset', undefined, tokens.admin)).body.data[0];
    assert.match(entry.summary, /Fatima Ali/);
    assert.ok(!JSON.stringify(entry).includes(r.body.data.temporaryPassword));
  });
});
