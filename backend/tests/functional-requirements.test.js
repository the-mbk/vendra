// ══════════════════════════════════════════════════════════════
// End-to-end tests for SRDS FR01–FR09 against a real Postgres.
// Run: TEST_DATABASE_URL=postgresql://... npm test
// ══════════════════════════════════════════════════════════════

const { test, before, after, describe } = require('node:test');
const assert = require('node:assert/strict');
const { io } = require('socket.io-client');
const { resetDatabase, startServer, apiClient, query, moneyInvariant } = require('./helpers');

// Seed locations
const CLIFTON = { lat: 24.8138, lng: 67.0300 };      // Ahmed's pin
const SADDAR = { lat: 24.8556, lng: 67.0224 };       // Karachi Electronics Hub
const ONE_KM_AWAY = { lat: 24.8228, lng: 67.0300 };  // ~1 km north of the pin

let srv;
let api;
const tokens = {};

async function login(email, role) {
  const r = await api('POST', '/api/auth/login', { email, password: 'password123', role });
  assert.equal(r.status, 200, JSON.stringify(r.body));
  return r.body.data.token;
}

async function product(id) {
  return (await query('SELECT * FROM products WHERE id = $1', [id])).rows[0];
}

async function assertMoneyBalanced() {
  const m = await moneyInvariant();
  assert.equal(m.accounted.toFixed(2), m.deposits.toFixed(2), 'wallets + pool + platform must equal deposits');
  assert.equal(m.pool.toFixed(2), m.held.toFixed(2), 'escrow pool must equal money held on open orders');
}

async function setPolicies(values) {
  const r = await api('PUT', '/api/admin/policies', { values }, tokens.admin);
  assert.equal(r.status, 200, JSON.stringify(r.body));
}

/** Customer places an order and the vendor walks it to ready_for_pickup */
async function readyDeliveryOrder(items) {
  const co = await api('POST', '/api/customer/checkout', {
    items, deliveryType: 'delivery', deliveryAddress: 'House 21, Clifton', customerLat: CLIFTON.lat, customerLng: CLIFTON.lng,
  }, tokens.ahmed);
  assert.equal(co.status, 201, JSON.stringify(co.body));
  const id = co.body.data.id;
  for (const step of ['approve', 'prepare', 'ready-for-pickup']) {
    const r = await api('PUT', `/api/vendor/orders/${id}/${step}`, undefined, tokens.usman);
    assert.equal(r.status, 200, `${step}: ${JSON.stringify(r.body)}`);
  }
  return co.body.data;
}

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

  for (const t of [tokens.ahmed, tokens.fatima]) {
    const r = await api('POST', '/api/customer/wallet/topup', { amount: 1000000 }, t);
    assert.equal(r.status, 200, JSON.stringify(r.body));
  }
});

after(async () => {
  await srv?.stop();
});

describe('FR05 — role-based login', () => {
  test('an account cannot sign in to another role\'s app', async () => {
    const r = await api('POST', '/api/auth/login', { email: 'usman@vendor.pk', password: 'password123', role: 'rider' });
    assert.equal(r.status, 403);
    assert.equal(r.body.code, 'WRONG_APP');
  });

  test('role-protected routes reject other roles', async () => {
    assert.equal((await api('GET', '/api/rider/tasks', undefined, tokens.ahmed)).status, 403);
    assert.equal((await api('GET', '/api/admin/stats', undefined, tokens.usman)).status, 403);
    assert.equal((await api('GET', '/api/vendor/products')).status, 401);
  });

  test('riders can sign up', async () => {
    const r = await api('POST', '/api/auth/signup', {
      fullName: 'Test Rider', email: 'new@rider.pk', password: 'secret123', role: 'rider', vehicleType: 'bicycle',
    });
    assert.equal(r.status, 201, JSON.stringify(r.body));
    const me = await api('GET', '/api/auth/me', undefined, r.body.data.token);
    assert.equal(me.body.data.vehicleType, 'bicycle');
  });
});

describe('FR01 + FR06 — dual inventory, policy buffer, categories, approval', () => {
  test('new products take the policy buffer and wait for admin approval', async () => {
    const r = await api('POST', '/api/vendor/products', {
      name: 'Baseus 65W Charger', price: 5499, private_stock: 40, barcode: '6932172600001',
      category_id: (await query(`SELECT id FROM categories WHERE name = 'Mobile Accessories'`)).rows[0].id,
    }, tokens.usman);
    assert.equal(r.status, 201, JSON.stringify(r.body));
    assert.equal(r.body.data.buffer, 5);
    assert.equal(r.body.data.public_stock, 35);
    assert.equal(r.body.data.is_approved, false);
    assert.equal(r.body.data.category_name, 'Mobile Accessories');

    const listed = await api('GET', '/api/products?search=Baseus');
    assert.equal(listed.body.data.length, 0, 'unapproved products are hidden');

    const approve = await api('PUT', `/api/admin/products/${r.body.data.id}/approve`, undefined, tokens.admin);
    assert.equal(approve.status, 200);
    const after = await api('GET', '/api/products?search=Baseus');
    assert.equal(after.body.data.length, 1);
    assert.equal(after.body.data[0].categoryName, 'Mobile Accessories');
  });

  test('products filter by category', async () => {
    const cats = await api('GET', '/api/categories');
    const fashion = cats.body.data.find((c) => c.name === 'Fashion');
    const r = await api('GET', `/api/products?category_id=${fashion.id}`);
    assert.ok(r.body.data.length >= 4);
    assert.ok(r.body.data.every((p) => p.categoryName === 'Fashion'));
  });

  test('barcode lookup finds the vendor\'s product', async () => {
    const r = await api('GET', '/api/vendor/products/barcode/6925281985642', undefined, tokens.usman);
    assert.equal(r.status, 200);
    assert.equal(r.body.data.name, 'JBL Tune 510BT Headphones');
  });

  test('stock edits cannot drop below reserved units', async () => {
    // Product 1 has 1 unit reserved by seed order #1
    const r = await api('PUT', '/api/vendor/products/1', { private_stock: 0 }, tokens.usman);
    assert.equal(r.status, 409);
    assert.equal(r.body.code, 'BELOW_RESERVED');
  });

  test('stock edit recomputes public stock from the reserved column', async () => {
    const r = await api('PUT', '/api/vendor/products/1', { private_stock: 60 }, tokens.usman);
    assert.equal(r.status, 200);
    assert.equal(r.body.data.public_stock, 60 - 5 - 1);
    const ledger = await query(`SELECT * FROM inventory_ledger WHERE product_id = 1 ORDER BY id DESC LIMIT 1`);
    assert.equal(ledger.rows[0].change_type, 'stock_in');
    assert.equal(ledger.rows[0].quantity_change, 10);
  });
});

describe('FR02 — reservation blocks walk-in sales of the same units', () => {
  test('POS can sell the buffer but never reserved units', async () => {
    // JBL (product 3): private 29, buffer 3, public 26
    const co = await api('POST', '/api/customer/checkout', {
      items: [{ productId: 3, quantity: 26 }], deliveryType: 'self_pickup',
    }, tokens.ahmed);
    assert.equal(co.status, 201, JSON.stringify(co.body));
    let p = await product(3);
    assert.equal(p.reserved_quantity, 26);
    assert.equal(p.public_stock, 0);

    const tooMany = await api('POST', '/api/vendor/pos/sales', { items: [{ productId: 3, quantity: 4 }] }, tokens.usman);
    assert.equal(tooMany.status, 409);
    assert.equal(tooMany.body.code, 'RESERVED_STOCK');
    assert.equal(tooMany.body.sellable, 3);

    const ok = await api('POST', '/api/vendor/pos/sales', { items: [{ productId: 3, quantity: 3 }] }, tokens.usman);
    assert.equal(ok.status, 201, JSON.stringify(ok.body));
    assert.equal(ok.body.data.total_amount, 3 * 8499);
    p = await product(3);
    assert.equal(p.private_stock, 26);
    assert.equal(p.reserved_quantity, 26);

    const none = await api('POST', '/api/vendor/pos/sales', { items: [{ productId: 3, quantity: 1 }] }, tokens.usman);
    assert.equal(none.status, 409);

    const today = await api('GET', '/api/vendor/pos/sales', undefined, tokens.usman);
    assert.equal(today.body.data.today_count, 1);

    // Tidy up: cancel the big order so its units go back on sale
    const cancel = await api('POST', `/api/customer/orders/${co.body.data.id}/cancel`, undefined, tokens.ahmed);
    assert.equal(cancel.status, 200, JSON.stringify(cancel.body));
    p = await product(3);
    assert.equal(p.reserved_quantity, 0);
    assert.equal(p.public_stock, 23);
    await assertMoneyBalanced();
  });

  test('concurrent checkouts never oversell', async () => {
    // Bridal Dupatta (product 7): public 13. 25 simultaneous single-unit orders.
    const attempts = Array.from({ length: 25 }, (_, i) =>
      api('POST', '/api/customer/checkout', {
        items: [{ productId: 7, quantity: 1 }], deliveryType: 'self_pickup',
      }, i % 2 ? tokens.ahmed : tokens.fatima));
    const results = await Promise.all(attempts);
    const ok = results.filter((r) => r.status === 201).length;
    const sold = results.filter((r) => r.status === 409 && r.body.code === 'INSUFFICIENT_STOCK').length;
    assert.equal(ok, 13, `expected 13 successes, got ${ok}`);
    assert.equal(sold, 12);
    const p = await product(7);
    assert.equal(p.public_stock, 0);
    assert.equal(p.reserved_quantity, 13);
    const locks = await query(`SELECT COALESCE(SUM(quantity), 0) AS n FROM inventory_locks WHERE product_id = 7 AND status = 'active'`);
    assert.equal(Number(locks.rows[0].n), 13);
    await assertMoneyBalanced();
  });

  test('cancelling and checking out at the same time never deadlocks', async () => {
    const place = () => api('POST', '/api/customer/checkout', {
      items: [{ productId: 4, quantity: 1 }], deliveryType: 'self_pickup',
    }, tokens.ahmed);
    const pending = await Promise.all(Array.from({ length: 10 }, place));
    assert.ok(pending.every((r) => r.status === 201));
    const mixed = await Promise.all([
      ...pending.map((r) => api('POST', `/api/customer/orders/${r.body.data.id}/cancel`, undefined, tokens.ahmed)),
      ...Array.from({ length: 10 }, place),
    ]);
    const failures = mixed.filter((r) => r.status >= 500);
    assert.equal(failures.length, 0, JSON.stringify(failures.map((f) => f.body)));
    // Leave nothing reserved for later tests
    for (const r of mixed.slice(10)) {
      await api('POST', `/api/customer/orders/${r.body.data.id}/cancel`, undefined, tokens.ahmed);
    }
    await assertMoneyBalanced();
  });

  test('delivery orders need a customer location', async () => {
    const r = await api('POST', '/api/customer/checkout', { items: [{ productId: 4, quantity: 1 }], deliveryType: 'delivery' }, tokens.ahmed);
    assert.equal(r.status, 400);
  });
});

describe('FR03 + FR04 + FR07 — rider delivery, geofence, payout, escrow', () => {
  let order;

  test('ready orders reach online riders nearby, first accept wins', async () => {
    await api('PUT', '/api/rider/status', { isOnline: true, ...SADDAR }, tokens.bilal);
    await api('PUT', '/api/rider/status', { isOnline: true, lat: 31.51, lng: 74.345 }, tokens.hamza);

    order = await readyDeliveryOrder([{ productId: 2, quantity: 2 }]);

    const bilalTasks = await api('GET', '/api/rider/tasks', undefined, tokens.bilal);
    assert.ok(bilalTasks.body.data.tasks.some((t) => t.id === order.id), 'Karachi rider sees the Karachi task');
    const task = bilalTasks.body.data.tasks.find((t) => t.id === order.id);
    assert.ok(task.estimatedPayout > 60);

    const hamzaTasks = await api('GET', '/api/rider/tasks', undefined, tokens.hamza);
    assert.ok(!hamzaTasks.body.data.tasks.some((t) => t.id === order.id), 'Lahore rider is outside the 5 km radius');

    const notif = await query(`SELECT * FROM notifications WHERE user_id = 6 AND type = 'task_available' AND order_id = $1`, [order.id]);
    assert.equal(notif.rows.length, 1, 'nearby rider was notified');

    const first = await api('POST', `/api/rider/tasks/${order.id}/accept`, undefined, tokens.bilal);
    assert.equal(first.status, 200, JSON.stringify(first.body));
    const second = await api('POST', `/api/rider/tasks/${order.id}/accept`, undefined, tokens.hamza);
    assert.equal(second.status, 409);
    assert.equal(second.body.code, 'TASK_TAKEN');
  });

  test('two riders racing for one task: exactly one wins', async () => {
    const race = await readyDeliveryOrder([{ productId: 4, quantity: 1 }]);
    const extra = await api('POST', '/api/auth/signup', {
      fullName: 'Race Rider', email: 'race@rider.pk', password: 'secret123', role: 'rider',
    });
    const raceToken = extra.body.data.token;
    await api('PUT', '/api/rider/status', { isOnline: true, ...SADDAR }, raceToken);
    await api('PUT', '/api/rider/status', { isOnline: true, ...SADDAR }, tokens.hamza);
    const results = await Promise.all([
      api('POST', `/api/rider/tasks/${race.id}/accept`, undefined, raceToken),
      api('POST', `/api/rider/tasks/${race.id}/accept`, undefined, tokens.hamza),
    ]);
    assert.deepEqual(results.map((r) => r.status).sort(), [200, 409]);
    // Winner cancels out of the test by delivering nothing; free the rider for later tests
    const winner = results[0].status === 200 ? raceToken : tokens.hamza;
    await api('POST', `/api/rider/orders/${race.id}/picked`, undefined, winner);
    const done = await api('POST', `/api/rider/orders/${race.id}/deliver`, CLIFTON, winner);
    assert.equal(done.status, 200, JSON.stringify(done.body));
  });

  test('rider cannot go offline mid-delivery', async () => {
    const r = await api('PUT', '/api/rider/status', { isOnline: false }, tokens.bilal);
    assert.equal(r.status, 409);
  });

  test('delivery outside the 200 m geofence is refused', async () => {
    assert.equal((await api('POST', `/api/rider/orders/${order.id}/arrived`, undefined, tokens.bilal)).status, 200);
    assert.equal((await api('POST', `/api/rider/orders/${order.id}/picked`, undefined, tokens.bilal)).status, 200);
    assert.equal((await api('POST', `/api/rider/orders/${order.id}/on-the-way`, undefined, tokens.bilal)).status, 200);

    // GPS pings from store to customer (PR 03)
    const path = [SADDAR, { lat: 24.8420, lng: 67.0260 }, { lat: 24.8280, lng: 67.0290 }, ONE_KM_AWAY];
    for (const pt of path) {
      const r = await api('POST', '/api/rider/location', pt, tokens.bilal);
      assert.equal(r.body.data.orderId, order.id);
    }

    const far = await api('POST', `/api/rider/orders/${order.id}/deliver`, ONE_KM_AWAY, tokens.bilal);
    assert.equal(far.status, 422);
    assert.equal(far.body.code, 'OUTSIDE_GEOFENCE');
    assert.ok(far.body.distanceMeters > 900);
  });

  test('delivery at the door deducts stock, pays the rider, holds the rest', async () => {
    const before = await product(2);
    const r = await api('POST', `/api/rider/orders/${order.id}/deliver`, CLIFTON, tokens.bilal);
    assert.equal(r.status, 200, JSON.stringify(r.body));
    assert.equal(r.body.data.distanceSource, 'gps');
    assert.ok(r.body.data.distanceKm > 4 && r.body.data.distanceKm < 6, `distance ${r.body.data.distanceKm}`);

    // payout = 60 + 25 × km (no paid waiting)
    const expected = Math.round((60 + 25 * r.body.data.distanceKm) * 100) / 100;
    assert.ok(Math.abs(r.body.data.payout - expected) <= 0.01, `payout ${r.body.data.payout} vs ${expected}`);

    const after = await product(2);
    assert.equal(after.private_stock, before.private_stock - 2);
    assert.equal(after.reserved_quantity, before.reserved_quantity - 2);
    const sale = await query(`SELECT * FROM inventory_ledger WHERE reference_id = $1 AND change_type = 'sale'`, [order.id]);
    assert.equal(sale.rows.length, 1);

    const o = (await query('SELECT * FROM orders WHERE id = $1', [order.id])).rows[0];
    assert.equal(o.status, 'delivered');
    assert.equal(o.escrow_status, 'held', 'held during the dispute window');
    assert.equal(Number(o.rider_payout), r.body.data.payout);

    const earnings = await api('GET', '/api/rider/earnings', undefined, tokens.bilal);
    assert.equal(earnings.body.data.todayCount, 1);
    assert.equal(earnings.body.data.walletBalance, r.body.data.payout);
    await assertMoneyBalanced();
  });

  test('customer can track the trip path', async () => {
    const r = await api('GET', `/api/customer/orders/${order.id}/tracking`, undefined, tokens.ahmed);
    assert.equal(r.status, 200);
    assert.ok(r.body.data.path.length >= 5);
    assert.equal(r.body.data.order.rider.name, 'Bilal Hussain');
  });

  test('escrow is released to the vendor after the window, minus commission', async () => {
    await query(`UPDATE orders SET escrow_release_due_at = NOW() - INTERVAL '1 minute' WHERE id = $1`, [order.id]);
    const vendorBefore = Number((await query('SELECT wallet_balance FROM users WHERE id = 2')).rows[0].wallet_balance);

    const { releaseDueEscrows } = require('../src/services/orderSettlement.service');
    assert.equal(await releaseDueEscrows(), 1);

    const vendorAfter = Number((await query('SELECT wallet_balance FROM users WHERE id = 2')).rows[0].wallet_balance);
    const subtotal = 2 * 4999;
    assert.equal((vendorAfter - vendorBefore).toFixed(2), (subtotal * 0.9).toFixed(2));
    const o = (await query('SELECT escrow_status FROM orders WHERE id = $1', [order.id])).rows[0];
    assert.equal(o.escrow_status, 'released');
    await assertMoneyBalanced();
  });
});

describe('FR08 — disputes freeze escrow until an admin decides', () => {
  test('customer disputes a delivered order with photo evidence; admin refunds', async () => {
    const order = await readyDeliveryOrder([{ productId: 4, quantity: 1 }]);
    await api('POST', `/api/rider/tasks/${order.id}/accept`, undefined, tokens.bilal);
    await api('POST', `/api/rider/orders/${order.id}/picked`, undefined, tokens.bilal);
    const delivered = await api('POST', `/api/rider/orders/${order.id}/deliver`, CLIFTON, tokens.bilal);
    assert.equal(delivered.status, 200, JSON.stringify(delivered.body));
    assert.equal(delivered.body.data.distanceSource, 'straight_line', 'no GPS pings → straight-line fallback');

    const form = new FormData();
    form.append('orderId', String(order.id));
    form.append('issueType', 'damaged_item');
    form.append('description', 'The case arrived cracked along one side.');
    const png = Buffer.from('89504e470d0a1a0a0000000d4948445200000001000000010806000000' +
      '1f15c4890000000d49444154789c6360000002000154a24f5d0000000049454e44ae426082', 'hex');
    form.append('evidence', new Blob([png], { type: 'image/png' }), 'crack.png');

    const d = await api('POST', '/api/disputes', form, tokens.ahmed);
    assert.equal(d.status, 201, JSON.stringify(d.body));
    assert.equal(d.body.data.evidence.length, 1);
    assert.equal(d.body.data.order.escrowStatus, 'disputed');

    const img = await fetch(`${srv.baseUrl}${d.body.data.evidence[0].url}`);
    assert.equal(img.status, 200, 'evidence photo is served');

    const again = await api('POST', '/api/disputes', (() => {
      const f = new FormData();
      f.append('orderId', String(order.id)); f.append('issueType', 'other'); f.append('description', 'Second complaint here.');
      return f;
    })(), tokens.ahmed);
    assert.equal(again.status, 409);

    // Frozen: the sweeper skips it even when due
    await query(`UPDATE orders SET escrow_release_due_at = NOW() - INTERVAL '1 minute' WHERE id = $1`, [order.id]);
    const { releaseDueEscrows } = require('../src/services/orderSettlement.service');
    assert.equal(await releaseDueEscrows(), 0);

    const list = await api('GET', '/api/admin/disputes?status=open', undefined, tokens.admin);
    assert.ok(list.body.data.some((x) => x.id === d.body.data.id));

    const walletBefore = Number((await query('SELECT wallet_balance FROM users WHERE id = 4')).rows[0].wallet_balance);
    const resolve = await api('PUT', `/api/admin/disputes/${d.body.data.id}/resolve`,
      { resolution: 'refund', note: 'Photo shows damage in transit.' }, tokens.admin);
    assert.equal(resolve.status, 200, JSON.stringify(resolve.body));
    const walletAfter = Number((await query('SELECT wallet_balance FROM users WHERE id = 4')).rows[0].wallet_balance);
    const expectedRefund = order.totalAmount - delivered.body.data.payout;
    assert.equal((walletAfter - walletBefore).toFixed(2), expectedRefund.toFixed(2));

    const o = (await query('SELECT escrow_status FROM orders WHERE id = $1', [order.id])).rows[0];
    assert.equal(o.escrow_status, 'refunded');
    await assertMoneyBalanced();
  });

  test('outsiders cannot dispute someone else\'s order', async () => {
    const form = new FormData();
    form.append('orderId', '1'); form.append('issueType', 'other'); form.append('description', 'Not my order at all.');
    const r = await api('POST', '/api/disputes', form, tokens.fatima);
    assert.equal(r.status, 403);
  });
});

describe('Policy engine — rules change without a redeploy', () => {
  test('a zero dispute window releases self-pickup escrow at once', async () => {
    await setPolicies({ dispute_window_min: 0, commission_pct: 5 });
    const co = await api('POST', '/api/customer/checkout', { items: [{ productId: 4, quantity: 2 }], deliveryType: 'self_pickup' }, tokens.fatima);
    assert.equal(co.status, 201);
    const id = co.body.data.id;
    for (const step of ['approve', 'prepare', 'ready-for-pickup', 'deliver']) {
      const r = await api('PUT', `/api/vendor/orders/${id}/${step}`, undefined, tokens.usman);
      assert.equal(r.status, 200, `${step}: ${JSON.stringify(r.body)}`);
    }
    const o = (await query('SELECT escrow_status FROM orders WHERE id = $1', [id])).rows[0];
    assert.equal(o.escrow_status, 'released');
    const commission = await query(`SELECT amount FROM platform_ledger WHERE order_id = $1 AND entry_type = 'commission'`, [id]);
    assert.equal(Number(commission.rows[0].amount), Math.round(2 * 2499 * 5) / 100);
    await assertMoneyBalanced();
    await setPolicies({ dispute_window_min: 1440, commission_pct: 10 });
  });

  test('invalid policy values are rejected', async () => {
    const r = await api('PUT', '/api/admin/policies', { values: { commission_pct: 150 } }, tokens.admin);
    assert.equal(r.status, 400);
    const unknown = await api('PUT', '/api/admin/policies', { values: { nope: 1 } }, tokens.admin);
    assert.equal(unknown.status, 400);
  });

  test('delivery fee follows the policy', async () => {
    await setPolicies({ delivery_fee: 99 });
    const co = await api('POST', '/api/customer/checkout', {
      items: [{ productId: 4, quantity: 1 }], deliveryType: 'delivery', customerLat: CLIFTON.lat, customerLng: CLIFTON.lng,
    }, tokens.ahmed);
    assert.equal(co.status, 201);
    assert.equal(co.body.data.deliveryFee, 99);
    assert.equal(co.body.data.totalAmount, 2499 + 99);
    await api('POST', `/api/customer/orders/${co.body.data.id}/cancel`, undefined, tokens.ahmed);
    await setPolicies({ delivery_fee: 150 });
    await assertMoneyBalanced();
  });
});

describe('FR09 — notifications and live updates', () => {
  test('status changes create notifications and push socket events', async () => {
    const customerSocket = io(srv.baseUrl, { auth: { token: tokens.ahmed }, transports: ['websocket'] });
    const publicSocket = io(srv.baseUrl, { transports: ['websocket'] });
    await Promise.all([customerSocket, publicSocket].map((s) => new Promise((res, rej) => {
      s.on('connect', res); s.on('connect_error', rej);
    })));

    try {
      const events = { notification: [], order: [], stock: [] };
      customerSocket.on('notification', (n) => events.notification.push(n));
      customerSocket.on('order:update', (o) => events.order.push(o));
      publicSocket.on('stock:update', (s) => events.stock.push(s));

      const co = await api('POST', '/api/customer/checkout', { items: [{ productId: 6, quantity: 1 }], deliveryType: 'self_pickup' }, tokens.ahmed);
      assert.equal(co.status, 201);
      const approve = await api('PUT', `/api/vendor/orders/${co.body.data.id}/approve`, undefined, (await login('ayesha@vendor.pk', 'vendor')));
      assert.equal(approve.status, 200);

      await new Promise((r) => setTimeout(r, 300));
      assert.ok(events.stock.some((s) => s.productId === 6), 'anonymous clients see stock changes');
      assert.ok(events.order.some((o) => o.orderId === co.body.data.id && o.status === 'confirmed'));
      assert.ok(events.notification.some((n) => n.orderId === co.body.data.id && n.type === 'order_confirmed'));
    } finally {
      customerSocket.close();
      publicSocket.close();
    }

    const inbox = await api('GET', '/api/notifications', undefined, tokens.ahmed);
    assert.ok(inbox.body.data.unreadCount > 0);
    await api('PUT', '/api/notifications/read-all', undefined, tokens.ahmed);
    const after = await api('GET', '/api/notifications', undefined, tokens.ahmed);
    assert.equal(after.body.data.unreadCount, 0);
  });

  test('wallet history lists holds and refunds', async () => {
    const r = await api('GET', '/api/wallet?limit=200', undefined, tokens.ahmed);
    const types = new Set(r.body.data.transactions.map((t) => t.type));
    assert.ok(types.has('escrow_hold') && types.has('escrow_refund') && types.has('deposit'));
  });
});

describe('Admin overview', () => {
  test('stats and finance reflect the platform', async () => {
    const stats = await api('GET', '/api/admin/stats', undefined, tokens.admin);
    assert.equal(stats.status, 200);
    assert.ok(stats.body.data.platformRevenue > 0);
    assert.equal(stats.body.data.pendingProducts, 1, 'seed product #9 still awaits approval');

    const finance = await api('GET', '/api/admin/finance', undefined, tokens.admin);
    assert.equal(finance.body.data.escrowPool.toFixed(2), (finance.body.data.held.amount + finance.body.data.disputed.amount).toFixed(2));
    assert.ok(finance.body.data.riderPayouts > 0);

    const riders = await api('GET', '/api/admin/riders', undefined, tokens.admin);
    assert.ok(riders.body.data.find((r) => r.email === 'bilal@rider.pk').deliveries >= 2);
    await assertMoneyBalanced();
  });
});

describe('Public config', () => {
  test('apps can read the delivery fee before checkout', async () => {
    const r = await api('GET', '/api/public-config');
    assert.equal(r.status, 200);
    assert.equal(r.body.data.deliveryFee, 150);
    assert.equal(r.body.data.geofenceMeters, 200);
  });
});

// ──────────────────────────────────────
// Round 2: time zones, private evidence, pagination, accounts, product photos
// ──────────────────────────────────────

const PNG_1PX = Buffer.from('89504e470d0a1a0a0000000d4948445200000001000000010806000000' +
  '1f15c4890000000d49444154789c6360000002000154a24f5d0000000049454e44ae426082', 'hex');

function photoForm(field, name) {
  const form = new FormData();
  form.append(field, new Blob([PNG_1PX], { type: 'image/png' }), name);
  return form;
}

describe('Time zones', () => {
  test('every time column stores an absolute instant', async () => {
    const r = await query(`SELECT table_name, column_name FROM information_schema.columns
                           WHERE table_schema = 'public' AND data_type = 'timestamp without time zone'`);
    assert.deepEqual(r.rows, []);
  });

  test('"today" is counted in Pakistan time', async () => {
    const r = await query('SHOW timezone');
    assert.equal(r.rows[0].TimeZone, 'Asia/Karachi');
  });
});

describe('Dispute evidence is private (SSR 03)', () => {
  test('evidence is only reachable through a valid signed link', async () => {
    const list = await api('GET', '/api/admin/disputes', undefined, tokens.admin);
    const evidenceUrl = list.body.data.find((d) => d.evidence.length > 0).evidence[0].url;
    assert.match(evidenceUrl, /^\/api\/files\/evidence\/[\w.-]+\?exp=\d+&sig=[\w-]+$/);

    assert.equal((await fetch(`${srv.baseUrl}${evidenceUrl}`)).status, 200);

    const name = evidenceUrl.split('/').pop().split('?')[0];
    const past = Math.floor(Date.now() / 1000) - 60;
    assert.equal((await fetch(`${srv.baseUrl}/api/files/evidence/${name}`)).status, 403, 'unsigned');
    assert.equal((await fetch(`${srv.baseUrl}${evidenceUrl.replace(/sig=[\w-]+/, 'sig=forged')}`)).status, 403, 'forged');
    assert.equal((await fetch(`${srv.baseUrl}${evidenceUrl.replace(/exp=\d+/, `exp=${past}`)}`)).status, 403, 'expired');
    assert.equal((await fetch(`${srv.baseUrl}/uploads/evidence/${name}`)).status, 404, 'no public folder');
  });
});

describe('Pagination', () => {
  test('products come in pages', async () => {
    const first = await api('GET', '/api/products?limit=3');
    assert.equal(first.body.data.length, 3);
    assert.equal(first.body.meta.hasMore, true);
    assert.equal(first.body.meta.nextOffset, 3);
    const second = await api('GET', `/api/products?limit=3&offset=${first.body.meta.nextOffset}`);
    const ids = new Set(first.body.data.map((p) => p.id));
    assert.ok(second.body.data.every((p) => !ids.has(p.id)), 'pages do not overlap');
    const capped = await api('GET', '/api/products?limit=5000');
    assert.equal(capped.body.meta.limit, 100);
  });

  test('customer orders page and single-order refresh', async () => {
    const page = await api('GET', '/api/customer/orders?limit=5', undefined, tokens.ahmed);
    assert.equal(page.body.data.length, 5);
    assert.equal(page.body.meta.hasMore, true);
    const one = await api('GET', `/api/customer/orders/${page.body.data[0].id}`, undefined, tokens.ahmed);
    assert.equal(one.body.data.id, page.body.data[0].id);
    const notMine = await api('GET', `/api/customer/orders/${page.body.data[0].id}`, undefined, tokens.fatima);
    assert.equal(notMine.status, 404);
  });

  test('vendor orders split into active (all) and history (paged)', async () => {
    const active = await api('GET', '/api/vendor/orders?scope=active', undefined, tokens.usman);
    assert.ok(active.body.data.every((o) => !['delivered', 'cancelled'].includes(o.status)));
    const history = await api('GET', '/api/vendor/orders?scope=history&limit=4', undefined, tokens.usman);
    assert.equal(history.body.data.length, 4);
    assert.ok(history.body.data.every((o) => ['delivered', 'cancelled'].includes(o.status)));
    assert.equal(history.body.meta.hasMore, true);
    const one = await api('GET', `/api/vendor/orders/${history.body.data[0].id}`, undefined, tokens.usman);
    assert.equal(one.body.data.id, history.body.data[0].id);
  });

  test('rider history is paged', async () => {
    const r = await api('GET', '/api/rider/orders?scope=history&limit=1', undefined, tokens.bilal);
    assert.equal(r.body.data.length, 1);
    assert.equal(r.body.meta.hasMore, true);
  });

  test('settled orders drop their GPS trail but keep the distance', async () => {
    const settled = await query(
      `SELECT id, distance_km FROM orders WHERE escrow_status IN ('released', 'refunded') AND distance_km IS NOT NULL`
    );
    assert.ok(settled.rows.length >= 1);
    const pings = await query('SELECT COUNT(*) FROM rider_locations WHERE order_id = ANY($1)', [settled.rows.map((o) => o.id)]);
    assert.equal(Number(pings.rows[0].count), 0);
    assert.ok(settled.rows.every((o) => Number(o.distance_km) > 0));
  });
});

describe('Accounts — change and reset passwords', () => {
  test('a user changes their password', async () => {
    const wrong = await api('POST', '/api/auth/change-password', { currentPassword: 'nope', newPassword: 'newpass123' }, tokens.fatima);
    assert.equal(wrong.status, 401);
    const short = await api('POST', '/api/auth/change-password', { currentPassword: 'password123', newPassword: 'short' }, tokens.fatima);
    assert.equal(short.status, 400);
    const ok = await api('POST', '/api/auth/change-password', { currentPassword: 'password123', newPassword: 'newpass123' }, tokens.fatima);
    assert.equal(ok.status, 200);
    const login = await api('POST', '/api/auth/login', { email: 'fatima@customer.pk', password: 'newpass123', role: 'customer' });
    assert.equal(login.status, 200);
  });

  test('an admin issues a temporary password that must be changed', async () => {
    const users = await api('GET', '/api/admin/users', undefined, tokens.admin);
    const fatima = users.body.data.find((u) => u.email === 'fatima@customer.pk');
    const reset = await api('PUT', `/api/admin/users/${fatima.id}/reset-password`, undefined, tokens.admin);
    assert.equal(reset.status, 200);
    const temp = reset.body.data.temporaryPassword;
    assert.equal(temp.length, 10);

    const login = await api('POST', '/api/auth/login', { email: 'fatima@customer.pk', password: temp, role: 'customer' });
    assert.equal(login.status, 200);
    assert.equal(login.body.data.user.mustChangePassword, true);
    const t = login.body.data.token;
    await api('POST', '/api/auth/change-password', { currentPassword: temp, newPassword: 'password123' }, t);
    const me = await api('GET', '/api/auth/me', undefined, t);
    assert.equal(me.body.data.mustChangePassword, false);

    const adminReset = await api('PUT', '/api/admin/users/1/reset-password', undefined, tokens.admin);
    assert.equal(adminReset.status, 404, 'admin accounts cannot be reset');
  });
});

describe('Product photos', () => {
  test('vendor uploads, replaces and removes a product photo', async () => {
    const first = await api('POST', '/api/vendor/products/1/image', photoForm('image', 'phone.png'), tokens.usman);
    assert.equal(first.status, 200, JSON.stringify(first.body));
    const url1 = first.body.data.image_url;
    assert.match(url1, /^\/uploads\/products\//);
    assert.equal((await fetch(`${srv.baseUrl}${url1}`)).status, 200, 'photos are public');

    const listed = await api('GET', '/api/products?search=Galaxy');
    assert.equal(listed.body.data[0].imageUrl, url1);

    const second = await api('POST', '/api/vendor/products/1/image', photoForm('image', 'phone2.png'), tokens.usman);
    const url2 = second.body.data.image_url;
    assert.notEqual(url2, url1);
    await new Promise((r) => setTimeout(r, 100));
    assert.equal((await fetch(`${srv.baseUrl}${url1}`)).status, 404, 'old photo deleted');

    const other = await api('POST', '/api/vendor/products/5/image', photoForm('image', 'x.png'), tokens.usman);
    assert.equal(other.status, 404, 'cannot change another store product');

    const del = await api('DELETE', '/api/vendor/products/1/image', undefined, tokens.usman);
    assert.equal(del.status, 200);
    assert.equal((await product(1)).image_url, null);
  });
});

describe('Session errors', () => {
  test('expired and invalid tokens return codes the apps can act on', async () => {
    const jwt = require('jsonwebtoken');
    const expired = jwt.sign({ userId: 4, role: 'customer', exp: Math.floor(Date.now() / 1000) - 10 }, process.env.JWT_SECRET);
    const r1 = await api('GET', '/api/auth/me', undefined, expired);
    assert.equal(r1.status, 401);
    assert.equal(r1.body.code, 'TOKEN_EXPIRED');
    const r2 = await api('GET', '/api/auth/me', undefined, 'garbage');
    assert.equal(r2.body.code, 'INVALID_TOKEN');
  });
});
