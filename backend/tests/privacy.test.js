// ══════════════════════════════════════════════════════════════
// Privacy vs transparency (VENDRA_SECURITY_AUDIT_UIUX_ENHANCEMENTS §4):
//   - an open task shows nearby riders no customer identity
//   - the rider, store and customer see each other by short name, and get
//     a phone number only while the order is in progress
//   - the customer sees the rider's live position only during the delivery
//   - the admin's inspection view has the full record: names, handover
//     proof against the pin, and the money split (estimate, then ledger)
//   - the store's wallet line shows items − commission = payout
// Run: TEST_DATABASE_URL=postgresql://... npm test
// ══════════════════════════════════════════════════════════════

const { test, before, after, describe } = require('node:test');
const assert = require('node:assert/strict');
const { resetDatabase, startServer, cardToken, apiClient, query } = require('./helpers');

const CLIFTON = { lat: 24.8138, lng: 67.0300 }; // Ahmed's pin
const SADDAR = { lat: 24.8556, lng: 67.0224 };  // Karachi Electronics Hub
const AHMED_PHONE = '0312-4445566';
const BILAL_PHONE = '0301-2223344';

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
const vendorOrder = async (id) => (await api('GET', `/api/vendor/orders/${id}`, undefined, tokens.usman)).body.data;
const tracking = async (id) => (await api('GET', `/api/customer/orders/${id}/tracking`, undefined, tokens.ahmed)).body.data;
const adminOrder = async (id) => (await api('GET', `/api/admin/orders/${id}`, undefined, tokens.admin)).body.data;

before(async () => {
  await resetDatabase();
  srv = await startServer();
  api = apiClient(srv.baseUrl);
  tokens.admin = await login('admin@vendra.pk', 'admin');
  tokens.usman = await login('usman@vendor.pk', 'vendor');
  tokens.ahmed = await login('ahmed@customer.pk', 'customer');
  tokens.bilal = await login('bilal@rider.pk', 'rider');
  const topup = await api('POST', '/api/payments/topup', { amount: 500000, token: await cardToken(srv.gatewayUrl) }, tokens.ahmed);
  assert.equal(topup.status, 200, JSON.stringify(topup.body));
  await api('PUT', '/api/rider/status', { isOnline: true, ...SADDAR }, tokens.bilal);

  // A delivery order, accepted by the store, packed and waiting for a rider
  const placed = await api('POST', '/api/customer/checkout', {
    items: [{ productId: 4, quantity: 1 }], deliveryType: 'delivery',
    deliveryAddress: 'House 21, Clifton', customerLat: CLIFTON.lat, customerLng: CLIFTON.lng,
  }, tokens.ahmed);
  assert.equal(placed.status, 201, JSON.stringify(placed.body));
  orderId = placed.body.data.id;
  assert.equal((await api('PUT', `/api/vendor/orders/${orderId}/approve`, undefined, tokens.usman)).status, 200);
  for (const item of (await vendorOrder(orderId)).items) {
    await api('PUT', `/api/vendor/orders/${orderId}/items/${item.id}/pack`, { packed: true }, tokens.usman);
  }
  for (const step of ['prepare', 'ready-for-pickup']) {
    const r = await api('PUT', `/api/vendor/orders/${orderId}/${step}`, undefined, tokens.usman);
    assert.equal(r.status, 200, `${step}: ${JSON.stringify(r.body)}`);
  }
});

after(() => srv.stop());

describe('Privacy: each party gets the least it needs', () => {
  test('an open task shows nearby riders where to go, not who the customer is', async () => {
    const r = await api('GET', '/api/rider/tasks', undefined, tokens.bilal);
    const task = r.body.data.tasks.find((t) => t.id === orderId);
    assert.ok(task, 'the task is offered');
    assert.equal(task.customerName, null);
    assert.equal(task.customerPhone, null);
    assert.equal(task.deliveryAddress, 'House 21, Clifton', 'the drop-off is still shown');
  });

  test('during the delivery each party sees a short name and can call', async () => {
    const accepted = await api('POST', `/api/rider/tasks/${orderId}/accept`, undefined, tokens.bilal);
    assert.equal(accepted.status, 200, JSON.stringify(accepted.body));
    assert.equal(accepted.body.data.customerName, 'Ahmed R.');
    assert.equal(accepted.body.data.customerPhone, AHMED_PHONE);

    const store = await vendorOrder(orderId);
    assert.equal(store.customer_name, 'Ahmed R.');
    assert.equal(store.customer_phone, AHMED_PHONE);
    assert.equal(store.rider_phone, BILAL_PHONE);
    assert.equal(store.delivery_otp, undefined, 'the handover code never reaches the store');

    await api('POST', `/api/rider/orders/${orderId}/picked`, SADDAR, tokens.bilal);
    const t = await tracking(orderId);
    assert.equal(t.order.rider.name, 'Bilal H.');
    assert.equal(t.order.rider.phone, BILAL_PHONE);
    assert.ok(t.riderLocation, 'live position while the rider is on this delivery');
  });

  test('once delivered, numbers and the live position are no longer shared', async () => {
    await api('POST', `/api/rider/orders/${orderId}/on-the-way`, undefined, tokens.bilal);
    const done = await api('POST', `/api/rider/orders/${orderId}/deliver`, { ...CLIFTON, otp: await otpOf(orderId) }, tokens.bilal);
    assert.equal(done.status, 200, JSON.stringify(done.body));

    const history = await api('GET', '/api/rider/orders?scope=history', undefined, tokens.bilal);
    const past = history.body.data.find((o) => o.id === orderId);
    assert.equal(past.customerName, 'Ahmed R.');
    assert.equal(past.customerPhone, null);

    const store = await vendorOrder(orderId);
    assert.equal(store.customer_phone, null);
    assert.equal(store.rider_phone, null);

    const t = await tracking(orderId);
    assert.equal(t.order.rider.phone, null);
    assert.equal(t.riderLocation, null);
    assert.ok(Array.isArray(t.path), 'the trip path stays: it is the customer\'s own record');
  });
});

describe('Transparency: the admin record and the store ledger', () => {
  test('the admin inspection view has the full record and the handover proof', async () => {
    const d = await adminOrder(orderId);
    assert.equal(d.customerName, 'Ahmed Raza');
    assert.equal(d.customerPhone, AHMED_PHONE);
    assert.equal(d.riderName, 'Bilal Hussain');
    assert.ok(d.handover.codeVerifiedAt, 'code entry time');
    assert.equal(d.handover.failedAttempts, 0);
    assert.equal(d.handover.distanceFromPinMeters, 0, 'handed over at the pin');
    assert.ok(d.handover.geofenceMeters > 0);
    assert.ok(d.arrivedAt === null || typeof d.arrivedAt === 'string');

    // Still in escrow: an estimate at today's commission
    assert.equal(d.settlement.state, 'estimate');
    assert.equal(d.settlement.commission, Math.round(d.subtotal * d.settlement.commissionPct) / 100);
    assert.equal(d.settlement.storeNet, Math.round((d.subtotal - d.settlement.commission) * 100) / 100);
  });

  test('after release the figures come from the ledgers and the store sees the breakdown', async () => {
    await query(`UPDATE orders SET escrow_release_due_at = NOW() - INTERVAL '1 minute' WHERE id = $1`, [orderId]);
    const { releaseDueEscrows } = require('../src/services/orderSettlement.service');
    assert.equal(await releaseDueEscrows(), 1);

    const d = await adminOrder(orderId);
    assert.equal(d.settlement.state, 'released');
    const credit = (await query(
      `SELECT amount, description FROM wallet_ledger WHERE order_id = $1 AND transaction_type = 'escrow_release'`, [orderId]
    )).rows[0];
    assert.equal(d.settlement.storeNet, Number(credit.amount));
    assert.equal(d.settlement.deliveryMargin, Math.round((d.deliveryFee - d.riderPayout) * 100) / 100);
    assert.match(credit.description, /^Escrow released for Order #\d+: items Rs\. [\d,.]+ − 10% commission Rs\. [\d,.]+ = Rs\. [\d,.]+$/);
  });

  test('an unknown order is a 404', async () => {
    const r = await api('GET', '/api/admin/orders/999999', undefined, tokens.admin);
    assert.equal(r.status, 404);
  });
});
