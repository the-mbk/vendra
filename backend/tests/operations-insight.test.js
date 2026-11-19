// ══════════════════════════════════════════════════════════════
// End-to-end tests for migration 014 and the UI/UX spec features:
// POS walk-in vs online reservation conflict (override), revenue split,
// parcel weight on rider tasks, "customer unavailable" GPS photo
// reports, split dispute outcome, the admin dossier / fleet / channel
// GMV endpoints and the rider wait-pay policy in public config.
// Run: TEST_DATABASE_URL=postgresql://... npm test
// ══════════════════════════════════════════════════════════════

const { test, before, after, describe } = require('node:test');
const assert = require('node:assert/strict');
const { resetDatabase, startServer, cardToken, apiClient, query, moneyInvariant } = require('./helpers');

const CLIFTON = { lat: 24.8138, lng: 67.0300 }; // Ahmed's pin
const SADDAR = { lat: 24.8556, lng: 67.0224 };  // Karachi Electronics Hub
const PNG = Buffer.from('89504e470d0a1a0a0000000d4948445200000001000000010806000000'
  + '1f15c4890000000d49444154789c6360000002000154a24f5d0000000049454e44ae426082', 'hex');

let srv;
let api;
const tokens = {};

async function login(email, role) {
  const r = await api('POST', '/api/auth/login', { email, password: 'password123', role });
  assert.equal(r.status, 200, JSON.stringify(r.body));
  return r.body.data.token;
}

const otpOf = async (id) => (await query('SELECT delivery_otp FROM orders WHERE id = $1', [id])).rows[0].delivery_otp;
const walletOf = async (userId) => Number((await query('SELECT wallet_balance FROM users WHERE id = $1', [userId])).rows[0].wallet_balance);
const userId = async (email) => (await query('SELECT id FROM users WHERE email = $1', [email])).rows[0].id;

async function placeDelivery(items) {
  const r = await api('POST', '/api/customer/checkout', {
    items, deliveryType: 'delivery', deliveryAddress: 'House 21, Clifton', customerLat: CLIFTON.lat, customerLng: CLIFTON.lng,
  }, tokens.ahmed);
  assert.equal(r.status, 201, JSON.stringify(r.body));
  return r.body.data.id;
}

async function readyOrder(items) {
  const id = await placeDelivery(items);
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

async function pickedOrder(items) {
  const id = await readyOrder(items);
  await api('PUT', '/api/rider/status', { isOnline: true, ...SADDAR }, tokens.bilal);
  assert.equal((await api('POST', `/api/rider/tasks/${id}/accept`, undefined, tokens.bilal)).status, 200);
  assert.equal((await api('POST', `/api/rider/orders/${id}/picked`, SADDAR, tokens.bilal)).status, 200);
  return id;
}

function photoForm(fields) {
  const form = new FormData();
  for (const [k, v] of Object.entries(fields)) form.append(k, String(v));
  form.append('evidence', new Blob([PNG], { type: 'image/png' }), 'door.png');
  return form;
}

before(async () => {
  await resetDatabase();
  srv = await startServer();
  api = apiClient(srv.baseUrl);
  tokens.admin = await login('admin@vendra.pk', 'admin');
  tokens.usman = await login('usman@vendor.pk', 'vendor');
  tokens.ahmed = await login('ahmed@customer.pk', 'customer');
  tokens.bilal = await login('bilal@rider.pk', 'rider');
  for (let i = 0; i < 2; i++) {
    const r = await api('POST', '/api/payments/topup', { amount: 500000, token: await cardToken(srv.gatewayUrl) }, tokens.ahmed);
    assert.equal(r.status, 200, JSON.stringify(r.body));
  }
});

after(() => srv.stop());

describe('POS walk-in vs online reservation (FR02)', () => {
  test('a walk-in sale can override a not-yet-packed online order, which is cancelled and refunded', async () => {
    const ahmedId = await userId('ahmed@customer.pk');
    const orderId = await placeDelivery([{ productId: 3, quantity: 2 }]);
    // Only the 2 reserved units remain on the shelf
    const upd = await api('PUT', '/api/vendor/products/3', { private_stock: 2 }, tokens.usman);
    assert.equal(upd.status, 200, JSON.stringify(upd.body));

    const refused = await api('POST', '/api/vendor/pos/sales', { items: [{ productId: 3, quantity: 1 }] }, tokens.usman);
    assert.equal(refused.status, 409);
    assert.equal(refused.body.code, 'RESERVED_STOCK');

    const res = await api('GET', '/api/vendor/products/3/reservations', undefined, tokens.usman);
    assert.equal(res.status, 200);
    assert.deepEqual(res.body.data.map((r) => [r.orderId, r.quantity, r.overridable]), [[orderId, 2, true]]);

    const before = await walletOf(ahmedId);
    const sale = await api('POST', '/api/vendor/pos/sales',
      { items: [{ productId: 3, quantity: 1, overrideReservation: true }] }, tokens.usman);
    assert.equal(sale.status, 201, JSON.stringify(sale.body));
    assert.deepEqual(sale.body.data.cancelled_orders, [orderId]);
    assert.match(sale.body.message, new RegExp(`#${orderId}`));

    const o = (await query('SELECT status, escrow_status, cancellation_reason FROM orders WHERE id = $1', [orderId])).rows[0];
    assert.deepEqual([o.status, o.escrow_status, o.cancellation_reason], ['cancelled', 'refunded', 'Sold out at the store']);
    assert.ok(await walletOf(ahmedId) > before, 'customer refunded');
    const p = (await query('SELECT private_stock, reserved_quantity, public_stock FROM products WHERE id = 3')).rows[0];
    assert.deepEqual([p.private_stock, p.reserved_quantity, p.public_stock], [1, 0, 0]);
  });

  test('packed orders are not overridable: the sale is still refused', async () => {
    await api('PUT', '/api/vendor/products/3', { private_stock: 20 }, tokens.usman);
    const id = await readyOrder([{ productId: 3, quantity: 1 }]);
    await api('PUT', '/api/vendor/products/3', { private_stock: 1 }, tokens.usman);
    const res = await api('GET', '/api/vendor/products/3/reservations', undefined, tokens.usman);
    assert.deepEqual(res.body.data.map((r) => [r.orderId, r.overridable]), [[id, false]]);
    const sale = await api('POST', '/api/vendor/pos/sales',
      { items: [{ productId: 3, quantity: 1, overrideReservation: true }] }, tokens.usman);
    assert.equal(sale.status, 409);
    assert.equal((await query('SELECT status FROM orders WHERE id = $1', [id])).rows[0].status, 'ready_for_pickup');
    await api('PUT', '/api/vendor/products/3', { private_stock: 20 }, tokens.usman);
  });

  test('the owner sees walk-in and online revenue separately', async () => {
    const r = await api('GET', '/api/vendor/revenue', undefined, tokens.usman);
    assert.equal(r.status, 200, JSON.stringify(r.body));
    assert.equal(r.body.data.today.walkInCount, 1);
    assert.equal(r.body.data.today.walkIn, 8499);
    assert.ok(r.body.data.inEscrow.orders >= 1);
    assert.ok('nextReleaseAt' in r.body.data.inEscrow, 'the ledger shows when held money is paid out');
  });
});

describe('Parcel weight on rider tasks (PR 03)', () => {
  test('tasks carry the parcel weight from listed product weights', async () => {
    const bad = await api('PUT', '/api/vendor/products/2', { weight_grams: -5 }, tokens.usman);
    assert.equal(bad.status, 400);
    const ok = await api('PUT', '/api/vendor/products/2', { weight_grams: 250 }, tokens.usman);
    assert.equal(ok.status, 200);
    assert.equal(ok.body.data.weight_grams, 250);

    const id = await readyOrder([{ productId: 2, quantity: 2 }]);
    await api('PUT', '/api/rider/status', { isOnline: true, ...SADDAR }, tokens.bilal);
    const tasks = await api('GET', '/api/rider/tasks', undefined, tokens.bilal);
    const task = tasks.body.data.tasks.find((t) => t.id === id);
    assert.ok(task, JSON.stringify(tasks.body));
    assert.equal(task.parcelWeightGrams, 500);
    assert.equal(task.parcelWeightComplete, true);
    assert.equal((await api('POST', `/api/rider/tasks/${id}/accept`, undefined, tokens.bilal)).status, 200);
    assert.equal((await api('POST', `/api/rider/orders/${id}/picked`, SADDAR, tokens.bilal)).status, 200);
    const d = await api('POST', `/api/rider/orders/${id}/deliver`, { ...CLIFTON, otp: await otpOf(id) }, tokens.bilal);
    assert.equal(d.status, 200, JSON.stringify(d.body));
  });
});

describe('Customer unavailable at handover (FR08)', () => {
  test('the rider files a GPS-tagged photo report from the door; escrow freezes; admin sees the dossier', async () => {
    const id = await pickedOrder([{ productId: 4, quantity: 1 }]);

    const noPhoto = new FormData();
    for (const [k, v] of Object.entries({ orderId: id, issueType: 'customer_unavailable', description: 'Nobody answered the door.', ...CLIFTON })) {
      noPhoto.append(k, String(v));
    }
    assert.equal((await api('POST', '/api/disputes', noPhoto, tokens.bilal)).status, 400);

    const far = await api('POST', '/api/disputes',
      photoForm({ orderId: id, issueType: 'customer_unavailable', description: 'Nobody answered the door.', ...SADDAR }), tokens.bilal);
    assert.equal(far.status, 422, JSON.stringify(far.body));

    const customer = await api('POST', '/api/disputes',
      photoForm({ orderId: id, issueType: 'customer_unavailable', description: 'Nobody answered the door.', ...CLIFTON }), tokens.ahmed);
    assert.equal(customer.status, 403, 'only the rider can report the customer unavailable');

    const filed = await api('POST', '/api/disputes',
      photoForm({ orderId: id, issueType: 'customer_unavailable', description: 'Nobody answered the door.', ...CLIFTON }), tokens.bilal);
    assert.equal(filed.status, 201, JSON.stringify(filed.body));
    assert.equal(filed.body.data.order.escrowStatus, 'disputed');
    assert.equal(filed.body.data.reporterLat, CLIFTON.lat);

    const dossier = await api('GET', `/api/admin/disputes/${filed.body.data.id}/dossier`, undefined, tokens.admin);
    assert.equal(dossier.status, 200, JSON.stringify(dossier.body));
    const { claim, store, delivery } = dossier.body.data;
    assert.equal(claim.role, 'rider');
    assert.equal(claim.reporterDistanceFromPinMeters, 0);
    assert.equal(claim.evidence.length, 1);
    assert.equal(store.fullyPacked, true);
    assert.ok(store.packedAt, 'packing completion time recorded');
    assert.equal(delivery.status, 'picked');
    assert.ok(delivery.pickedAt && delivery.arrivedAt);

    const resolved = await api('PUT', `/api/admin/disputes/${filed.body.data.id}/resolve`, { resolution: 'refund' }, tokens.admin);
    assert.equal(resolved.status, 200, JSON.stringify(resolved.body));
    const o = (await query('SELECT status, escrow_status FROM orders WHERE id = $1', [id])).rows[0];
    assert.deepEqual([o.status, o.escrow_status], ['cancelled', 'refunded']);
  });
});

describe('Split dispute outcome (FR08)', () => {
  test('part of the item subtotal goes back to the customer, the rest to the store less commission', async () => {
    const id = await pickedOrder([{ productId: 4, quantity: 2 }]);
    assert.equal((await api('POST', `/api/rider/orders/${id}/deliver`, { ...CLIFTON, otp: await otpOf(id) }, tokens.bilal)).status, 200);
    const d = await api('POST', '/api/disputes',
      photoForm({ orderId: id, issueType: 'damaged_item', description: 'One of the two cases arrived cracked.' }), tokens.ahmed);
    assert.equal(d.status, 201, JSON.stringify(d.body));

    const bad = await api('PUT', `/api/admin/disputes/${d.body.data.id}/resolve`, { resolution: 'split', refundPct: 100 }, tokens.admin);
    assert.equal(bad.status, 400);

    const ahmed = await userId('ahmed@customer.pk');
    const usman = await userId('usman@vendor.pk');
    const [customerBefore, vendorBefore] = [await walletOf(ahmed), await walletOf(usman)];
    const r = await api('PUT', `/api/admin/disputes/${d.body.data.id}/resolve`, { resolution: 'split', refundPct: 50, note: 'One case damaged' }, tokens.admin);
    assert.equal(r.status, 200, JSON.stringify(r.body));

    const commission = Number((await query(`SELECT value FROM policies WHERE key = 'commission_pct'`)).rows[0].value);
    const subtotal = 2 * 2499;
    const refund = subtotal * 0.5;
    const vendorShare = (subtotal - refund) * (1 - commission / 100);
    assert.equal((await walletOf(ahmed) - customerBefore).toFixed(2), refund.toFixed(2));
    assert.equal((await walletOf(usman) - vendorBefore).toFixed(2), vendorShare.toFixed(2));
    const row = (await query('SELECT resolution, refund_pct FROM disputes WHERE id = $1', [d.body.data.id])).rows[0];
    assert.deepEqual([row.resolution, Number(row.refund_pct)], ['split', 50]);
  });
});

describe('Admin fleet and channel GMV', () => {
  test('fleet board, channel breakdown and wait-pay policy are exposed', async () => {
    const fleet = await api('GET', '/api/admin/fleet', undefined, tokens.admin);
    assert.equal(fleet.status, 200, JSON.stringify(fleet.body));
    assert.ok(fleet.body.data.counts.online >= 1);
    assert.ok(fleet.body.data.deliveries.some((x) => x.stage === 'delivered'));

    const stats = await api('GET', '/api/admin/stats', undefined, tokens.admin);
    const ch = stats.body.data.channels;
    assert.equal(ch.walkIn.commission, 0);
    assert.equal(ch.totalGmv, ch.walkIn.gmv + ch.online.gmv);
    assert.equal(ch.series.length, 14);
    const today = (await query(`SELECT to_char(CURRENT_DATE, 'YYYY-MM-DD') AS d`)).rows[0].d;
    assert.equal(ch.series.at(-1).day, today);
    assert.equal(ch.series.at(-1).walkIn, ch.walkIn.today);

    const finance = await api('GET', '/api/admin/finance', undefined, tokens.admin);
    assert.equal(finance.body.data.channels.series.length, 30);

    const config = await api('GET', '/api/public-config');
    assert.equal(typeof config.body.data.riderFreeWaitMinutes, 'number');
    assert.equal(typeof config.body.data.riderPerWaitMin, 'number');
  });

  test('money still balances after all of the above', async () => {
    const m = await moneyInvariant();
    assert.equal(m.accounted.toFixed(2), m.deposits.toFixed(2));
    assert.equal(m.pool.toFixed(2), m.held.toFixed(2));
  });
});
