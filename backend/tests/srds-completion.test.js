// ══════════════════════════════════════════════════════════════
// SRDS items closed in this round:
//   FR01        goods received by scanning: lookup by barcode, then stock-in
//   SSR 03      the ledgers are append-only at the database level
//   Fig 2.11    restock alert when free shelf units reach low_stock_units
//   §1.3 / 2.3  policy-driven late cancellation fee (cancel_penalty_pct)
//   Fig 2.9     admin dashboard: recent disputes and platform health
// Run: TEST_DATABASE_URL=postgresql://... npm test
// ══════════════════════════════════════════════════════════════

const { test, before, after, describe } = require('node:test');
const assert = require('node:assert/strict');
const { resetDatabase, startServer, cardToken, apiClient, query, moneyInvariant } = require('./helpers');

const CLIFTON = { lat: 24.8138, lng: 67.0300 };

let srv;
let api;
const tokens = {};

async function login(email, role) {
  const r = await api('POST', '/api/auth/login', { email, password: 'password123', role });
  assert.equal(r.status, 200, JSON.stringify(r.body));
  return r.body.data.token;
}

const productRow = async (id) => (await query('SELECT * FROM products WHERE id = $1', [id])).rows[0];
const walletOf = async (userId) => Number((await query('SELECT wallet_balance FROM users WHERE id = $1', [userId])).rows[0].wallet_balance);

async function assertMoneyBalanced() {
  const m = await moneyInvariant();
  assert.equal(m.accounted.toFixed(2), m.deposits.toFixed(2), 'every rupee accounted for');
  assert.equal(m.pool.toFixed(2), m.held.toFixed(2), 'escrow pool matches what orders hold');
}

async function placeOrder(items) {
  const r = await api('POST', '/api/customer/checkout', {
    items, deliveryType: 'delivery', deliveryAddress: 'House 21, Clifton', customerLat: CLIFTON.lat, customerLng: CLIFTON.lng,
  }, tokens.ahmed);
  assert.equal(r.status, 201, JSON.stringify(r.body));
  return r.body.data;
}

before(async () => {
  await resetDatabase();
  srv = await startServer();
  api = apiClient(srv.baseUrl);
  tokens.admin = await login('admin@vendra.pk', 'admin');
  tokens.usman = await login('usman@vendor.pk', 'vendor');
  tokens.ayesha = await login('ayesha@vendor.pk', 'vendor');
  tokens.ahmed = await login('ahmed@customer.pk', 'customer');
  const topup = await api('POST', '/api/payments/topup', { amount: 500000, token: await cardToken(srv.gatewayUrl) }, tokens.ahmed);
  assert.equal(topup.status, 200, JSON.stringify(topup.body));
});

after(() => srv.stop());

describe('FR01: goods received by scanning the barcode', () => {
  test('scan finds the product, stock-in adds to the shelf and online stock follows', async () => {
    const found = await api('GET', '/api/vendor/products/barcode/6925281985642', undefined, tokens.usman);
    assert.equal(found.status, 200);
    assert.equal(found.body.data.id, 3);

    const before = await productRow(3);
    const r = await api('POST', '/api/vendor/products/3/stock-in', { quantity: 12, note: 'Supplier delivery' }, tokens.usman);
    assert.equal(r.status, 200, JSON.stringify(r.body));
    assert.equal(r.body.data.private_stock, before.private_stock + 12);
    assert.equal(r.body.data.public_stock, before.private_stock + 12 - before.buffer - before.reserved_quantity);

    const ledger = (await query(
      `SELECT change_type, quantity_change, notes FROM inventory_ledger WHERE product_id = 3 ORDER BY id DESC LIMIT 1`
    )).rows[0];
    assert.deepEqual(ledger, { change_type: 'stock_in', quantity_change: 12, notes: 'Supplier delivery' });
  });

  test('bad quantities and other stores\' products are refused', async () => {
    assert.equal((await api('POST', '/api/vendor/products/3/stock-in', { quantity: 0 }, tokens.usman)).status, 400);
    assert.equal((await api('POST', '/api/vendor/products/3/stock-in', { quantity: 2.5 }, tokens.usman)).status, 400);
    assert.equal((await api('POST', '/api/vendor/products/3/stock-in', { quantity: 5 }, tokens.ayesha)).status, 404);
    assert.equal((await api('GET', '/api/vendor/products/barcode/0000000000000', undefined, tokens.usman)).status, 404);
  });
});

describe('SSR 03: append-only ledgers', () => {
  test('stock and platform ledger rows can be neither edited nor deleted', async () => {
    await assert.rejects(query('UPDATE inventory_ledger SET quantity_change = 999 WHERE id = (SELECT MIN(id) FROM inventory_ledger)'), /append-only/);
    await assert.rejects(query('DELETE FROM inventory_ledger WHERE id = (SELECT MIN(id) FROM inventory_ledger)'), /append-only/);
    await assert.rejects(query('UPDATE platform_ledger SET amount = 0'), /append-only/); // the fixture's commission entry
    await assert.rejects(query('DELETE FROM platform_ledger'), /append-only/);
  });

  test('wallet entries are fixed, except a payout reference being filled in', async () => {
    const id = (await query('SELECT MIN(id) AS id FROM wallet_ledger')).rows[0].id;
    await assert.rejects(query('UPDATE wallet_ledger SET amount = amount + 1 WHERE id = $1', [id]), /append-only/);
    await assert.rejects(query('DELETE FROM wallet_ledger WHERE id = $1', [id]), /append-only/);
    await query(`UPDATE wallet_ledger SET reference = 'po_test', description = 'Payout sent' WHERE id = $1`, [id]);
    assert.equal((await query('SELECT reference FROM wallet_ledger WHERE id = $1', [id])).rows[0].reference, 'po_test');
  });
});

describe('Restock alerts (SRDS Fig 2.11, FR09)', () => {
  test('the store is told once when free shelf units fall to the threshold', async () => {
    // 8 on the shelf, 1 reserved by a fixture order: 7 free. The policy alerts at 5 or fewer
    await api('PUT', '/api/vendor/products/1', { private_stock: 8, buffer: 0 }, tokens.usman);
    assert.equal((await productRow(1)).reserved_quantity, 1);
    const alerts = async () => (await query(`SELECT title FROM notifications WHERE type = 'low_stock' AND user_id = 2 ORDER BY id`)).rows;
    const sell = (quantity) => api('POST', '/api/vendor/pos/sales', { items: [{ productId: 1, quantity }] }, tokens.usman);

    assert.equal((await sell(1)).status, 201); // 6 left: still above
    assert.deepEqual(await alerts(), []);
    assert.equal((await sell(1)).status, 201); // 5 left: alert
    assert.deepEqual(await alerts(), [{ title: 'Running low: Samsung Galaxy A54 5G' }]);
    assert.equal((await sell(1)).status, 201); // 4 left: already told
    assert.equal((await alerts()).length, 1);

    // Restocking re-arms it
    await api('POST', '/api/vendor/products/1/stock-in', { quantity: 20 }, tokens.usman);
    assert.equal((await sell(19)).status, 201);
    assert.equal((await alerts()).length, 2);
  });

  test('stores and apps read the threshold and the cancellation fee from public config', async () => {
    const r = await api('GET', '/api/public-config');
    assert.equal(r.body.data.lowStockUnits, 5);
    assert.equal(r.body.data.cancelPenaltyPct, 10);
  });
});

describe('Late cancellation fee (policy engine, SRDS §1.3)', () => {
  test('a pending order cancels free', async () => {
    const before = await walletOf(4);
    const order = await placeOrder([{ productId: 4, quantity: 2 }]);
    const r = await api('POST', `/api/customer/orders/${order.id}/cancel`, undefined, tokens.ahmed);
    assert.equal(r.status, 200, JSON.stringify(r.body));
    assert.equal(r.body.data.storeFee, 0);
    assert.equal((await walletOf(4)).toFixed(2), before.toFixed(2));
    await assertMoneyBalanced();
  });

  test('after the store accepts, the store keeps the fee and the rest is refunded', async () => {
    const customerBefore = await walletOf(4);
    const storeBefore = await walletOf(2);
    const order = await placeOrder([{ productId: 4, quantity: 2 }]); // items 4,998
    assert.equal((await api('PUT', `/api/vendor/orders/${order.id}/approve`, undefined, tokens.usman)).status, 200);
    const reservedBefore = (await productRow(4)).reserved_quantity;

    const r = await api('POST', `/api/customer/orders/${order.id}/cancel`, undefined, tokens.ahmed);
    assert.equal(r.status, 200, JSON.stringify(r.body));
    assert.equal(r.body.data.storeFee, 499.8);
    assert.equal((customerBefore - await walletOf(4)).toFixed(2), '499.80', 'the customer pays only the fee');
    assert.equal((await walletOf(2) - storeBefore).toFixed(2), '499.80');
    assert.equal((await productRow(4)).reserved_quantity, reservedBefore - 2, 'units back on sale');

    const o = (await query('SELECT status, escrow_status, cancellation_reason FROM orders WHERE id = $1', [order.id])).rows[0];
    assert.equal(o.status, 'cancelled');
    assert.equal(o.escrow_status, 'refunded');
    assert.match(o.cancellation_reason, /10% fee/);

    const admin = await api('GET', `/api/admin/orders/${order.id}`, undefined, tokens.admin);
    assert.deepEqual(admin.body.data.settlement, { state: 'refunded', refunded: Math.round((order.totalAmount - 499.8) * 100) / 100, storeFee: 499.8 });

    // The customer's receipt shows what came back to the wallet and how it was paid
    const mine = await api('GET', `/api/customer/orders/${order.id}`, undefined, tokens.ahmed);
    assert.equal(mine.body.data.refundedAmount, Math.round((order.totalAmount - 499.8) * 100) / 100);
    assert.equal(mine.body.data.paymentMethod, 'wallet');
    assert.equal(mine.body.data.cardLabel, null);
    await assertMoneyBalanced();
  });

  test('a packed order can no longer be cancelled', async () => {
    const order = await placeOrder([{ productId: 4, quantity: 1 }]);
    await api('PUT', `/api/vendor/orders/${order.id}/approve`, undefined, tokens.usman);
    const o = await api('GET', `/api/vendor/orders/${order.id}`, undefined, tokens.usman);
    for (const item of o.body.data.items) {
      await api('PUT', `/api/vendor/orders/${order.id}/items/${item.id}/pack`, { packed: true }, tokens.usman);
    }
    assert.equal((await api('PUT', `/api/vendor/orders/${order.id}/prepare`, undefined, tokens.usman)).status, 200);
    const r = await api('POST', `/api/customer/orders/${order.id}/cancel`, undefined, tokens.ahmed);
    assert.equal(r.status, 409);
    assert.equal(r.body.code, 'TOO_LATE_TO_CANCEL');
  });
});

describe('Admin dashboard: recent disputes and platform health (SRDS Fig 2.9)', () => {
  test('health checks the database and reconciles escrow against open orders', async () => {
    const r = await api('GET', '/api/admin/stats', undefined, tokens.admin);
    assert.equal(r.status, 200, JSON.stringify(r.body));
    const { health, recentDisputes } = r.body.data;
    assert.equal(health.database.ok, true);
    assert.ok(health.database.latencyMs >= 0);
    assert.equal(health.escrow.balanced, true);
    assert.equal(health.escrow.pool, health.escrow.heldByOrders);
    assert.equal(health.sweep.intervalSeconds, 30);
    assert.ok(Array.isArray(recentDisputes));
  });
});
