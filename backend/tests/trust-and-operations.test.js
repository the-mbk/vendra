// ══════════════════════════════════════════════════════════════
// End-to-end tests for migration 010: reviews & ratings, delivery
// handover OTP, rider approval, shop staff roles, packing checklist,
// photo gallery, POS receipts, payout slips, security headers and
// rate limits.
// Run: TEST_DATABASE_URL=postgresql://... npm test
// ══════════════════════════════════════════════════════════════

const { test, before, after, describe } = require('node:test');
const assert = require('node:assert/strict');
const { resetDatabase, startServer, cardToken, apiClient, query, moneyInvariant } = require('./helpers');

const CLIFTON = { lat: 24.8138, lng: 67.0300 };  // Ahmed's pin
const SADDAR = { lat: 24.8556, lng: 67.0224 };   // Karachi Electronics Hub

let srv;
let api;
const tokens = {};

async function login(email, role, password = 'password123') {
  const r = await api('POST', '/api/auth/login', { email, password, role });
  assert.equal(r.status, 200, JSON.stringify(r.body));
  return r.body.data.token;
}

const otpOf = async (orderId) => (await query('SELECT delivery_otp FROM orders WHERE id = $1', [orderId])).rows[0].delivery_otp;

async function packAll(orderId, token = tokens.usman) {
  const o = await api('GET', `/api/vendor/orders/${orderId}`, undefined, token);
  for (const item of o.body.data.items) {
    const r = await api('PUT', `/api/vendor/orders/${orderId}/items/${item.id}/pack`, { packed: true }, token);
    assert.equal(r.status, 200, JSON.stringify(r.body));
  }
}

async function placeDelivery(items, token = tokens.ahmed) {
  const co = await api('POST', '/api/customer/checkout', {
    items, deliveryType: 'delivery', deliveryAddress: 'House 21, Clifton', customerLat: CLIFTON.lat, customerLng: CLIFTON.lng,
  }, token);
  assert.equal(co.status, 201, JSON.stringify(co.body));
  return co.body.data.id;
}

/** Order placed, accepted, packed, ready and picked up by Bilal (on the way to the door) */
async function pickedOrder(items) {
  const id = await placeDelivery(items);
  assert.equal((await api('PUT', `/api/vendor/orders/${id}/approve`, undefined, tokens.usman)).status, 200);
  await packAll(id);
  for (const step of ['prepare', 'ready-for-pickup']) {
    const r = await api('PUT', `/api/vendor/orders/${id}/${step}`, undefined, tokens.usman);
    assert.equal(r.status, 200, `${step}: ${JSON.stringify(r.body)}`);
  }
  await api('PUT', '/api/rider/status', { isOnline: true, ...SADDAR }, tokens.bilal);
  assert.equal((await api('POST', `/api/rider/tasks/${id}/accept`, undefined, tokens.bilal)).status, 200);
  assert.equal((await api('POST', `/api/rider/orders/${id}/picked`, SADDAR, tokens.bilal)).status, 200);
  return id;
}

async function deliveredOrder(items) {
  const id = await pickedOrder(items);
  const r = await api('POST', `/api/rider/orders/${id}/deliver`, { ...CLIFTON, otp: await otpOf(id) }, tokens.bilal);
  assert.equal(r.status, 200, JSON.stringify(r.body));
  return { id, delivery: r.body.data };
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
  for (let i = 0; i < 2; i++) {
    const r = await api('POST', '/api/payments/topup', { amount: 500000, token: await cardToken(srv.gatewayUrl) }, tokens.ahmed);
    assert.equal(r.status, 200, JSON.stringify(r.body));
  }
});

after(async () => {
  await srv?.stop();
});

describe('Delivery handover OTP (anti GPS-spoofing)', () => {
  let id;

  test('the customer sees their code; the store never does', async () => {
    id = await pickedOrder([{ productId: 4, quantity: 1 }]);
    const mine = await api('GET', `/api/customer/orders/${id}`, undefined, tokens.ahmed);
    assert.match(mine.body.data.deliveryOtp, /^\d{4}$/);
    const store = await api('GET', `/api/vendor/orders/${id}`, undefined, tokens.usman);
    assert.equal(store.body.data.delivery_otp, undefined);
    assert.equal(store.body.data.otp_required, true);
    const rider = await api('GET', '/api/rider/orders', undefined, tokens.bilal);
    const task = rider.body.data.find((o) => o.id === id);
    assert.equal(task.otpRequired, true);
    assert.equal(JSON.stringify(rider.body).includes(mine.body.data.deliveryOtp + '"'), false, 'code not in the rider payload');
  });

  test('at the door, GPS alone is not enough', async () => {
    const r = await api('POST', `/api/rider/orders/${id}/deliver`, CLIFTON, tokens.bilal);
    assert.equal(r.status, 400);
    assert.equal(r.body.code, 'OTP_REQUIRED');
  });

  test('wrong codes count down and then lock the handover', async () => {
    const real = await otpOf(id);
    const wrong = real === '0000' ? '1111' : '0000';
    for (let left = 4; left >= 1; left--) {
      const r = await api('POST', `/api/rider/orders/${id}/deliver`, { ...CLIFTON, otp: wrong }, tokens.bilal);
      assert.equal(r.status, 422);
      assert.equal(r.body.code, 'WRONG_OTP');
      assert.equal(r.body.attemptsLeft, left);
    }
    const fifth = await api('POST', `/api/rider/orders/${id}/deliver`, { ...CLIFTON, otp: wrong }, tokens.bilal);
    assert.equal(fifth.body.attemptsLeft, 0);
    const locked = await api('POST', `/api/rider/orders/${id}/deliver`, { ...CLIFTON, otp: real }, tokens.bilal);
    assert.equal(locked.status, 429);
    assert.equal(locked.body.code, 'OTP_LOCKED');
    const n = await query(`SELECT COUNT(*)::int AS n FROM notifications WHERE user_id = 4 AND type = 'otp_locked' AND order_id = $1`, [id]);
    assert.equal(n.rows[0].n, 1, 'the customer is warned');
    const o = (await query('SELECT status FROM orders WHERE id = $1', [id])).rows[0];
    assert.equal(o.status, 'picked', 'nothing was delivered');
  });

  test('with the right code (after the lock) the delivery completes', async () => {
    await query('UPDATE orders SET otp_locked_until = NOW() - INTERVAL \'1 second\' WHERE id = $1', [id]);
    const r = await api('POST', `/api/rider/orders/${id}/deliver`, { ...CLIFTON, otp: await otpOf(id) }, tokens.bilal);
    assert.equal(r.status, 200, JSON.stringify(r.body));
    const mine = await api('GET', `/api/customer/orders/${id}`, undefined, tokens.ahmed);
    assert.equal(mine.body.data.deliveryOtp, null, 'the code disappears once used');
  });

  test('self pickup: the store enters the code shown at the counter', async () => {
    const co = await api('POST', '/api/customer/checkout', { items: [{ productId: 4, quantity: 1 }], deliveryType: 'self_pickup' }, tokens.ahmed);
    const pid = co.body.data.id;
    await api('PUT', `/api/vendor/orders/${pid}/approve`, undefined, tokens.usman);
    await packAll(pid);
    await api('PUT', `/api/vendor/orders/${pid}/prepare`, undefined, tokens.usman);
    await api('PUT', `/api/vendor/orders/${pid}/ready-for-pickup`, undefined, tokens.usman);
    const noCode = await api('PUT', `/api/vendor/orders/${pid}/deliver`, {}, tokens.usman);
    assert.equal(noCode.body.code, 'OTP_REQUIRED');
    const ok = await api('PUT', `/api/vendor/orders/${pid}/deliver`, { otp: co.body.data.deliveryOtp }, tokens.usman);
    assert.equal(ok.status, 200, JSON.stringify(ok.body));
  });
});

describe('Itemised rider payout slip', () => {
  test('delivery returns and stores base + distance + waiting lines that add up', async () => {
    const { id, delivery } = await deliveredOrder([{ productId: 2, quantity: 1 }]);
    const b = delivery.payoutBreakdown;
    assert.equal(b.baseFee, 60);
    assert.equal(b.perKm, 25);
    assert.ok(b.distanceKm > 0);
    assert.ok(Math.abs(b.baseFee + b.distancePay + b.waitPay - b.total) < 0.02, JSON.stringify(b));
    assert.equal(b.total, delivery.payout);
    const history = await api('GET', '/api/rider/orders?scope=history', undefined, tokens.bilal);
    assert.deepEqual(history.body.data.find((o) => o.id === id).payoutBreakdown.total, b.total);
  });

  test('task cards show the estimated slip', async () => {
    const id = await placeDelivery([{ productId: 4, quantity: 1 }]);
    await api('PUT', `/api/vendor/orders/${id}/approve`, undefined, tokens.usman);
    await packAll(id);
    await api('PUT', `/api/vendor/orders/${id}/prepare`, undefined, tokens.usman);
    await api('PUT', `/api/vendor/orders/${id}/ready-for-pickup`, undefined, tokens.usman);
    const tasks = await api('GET', '/api/rider/tasks', undefined, tokens.bilal);
    const t = tasks.body.data.tasks.find((x) => x.id === id);
    assert.equal(t.estimatedPayoutBreakdown.baseFee, 60);
    assert.equal(t.estimatedPayoutBreakdown.total, t.estimatedPayout);
    // leave it for the timeout sweep of other suites: cancel by rejecting isn't possible at this stage, so deliver it
    await api('POST', `/api/rider/tasks/${id}/accept`, undefined, tokens.bilal);
    await api('POST', `/api/rider/orders/${id}/picked`, SADDAR, tokens.bilal);
    await api('POST', `/api/rider/orders/${id}/deliver`, { ...CLIFTON, otp: await otpOf(id) }, tokens.bilal);
  });
});

describe('Reviews and ratings', () => {
  let id;

  test('only delivered orders can be reviewed', async () => {
    const pending = await placeDelivery([{ productId: 3, quantity: 1 }]);
    const r = await api('POST', `/api/customer/orders/${pending}/review`, { items: [{ productId: 3, rating: 5 }] }, tokens.ahmed);
    assert.equal(r.status, 409);
    assert.equal(r.body.code, 'NOT_DELIVERED');
    await api('POST', `/api/customer/orders/${pending}/cancel`, undefined, tokens.ahmed);
  });

  test('the customer rates products and the rider once', async () => {
    ({ id } = await deliveredOrder([{ productId: 3, quantity: 1 }, { productId: 4, quantity: 1 }]));
    const before = await api('GET', `/api/customer/orders/${id}`, undefined, tokens.ahmed);
    assert.equal(before.body.data.canReview, true);

    const notInOrder = await api('POST', `/api/customer/orders/${id}/review`, { items: [{ productId: 1, rating: 4 }] }, tokens.ahmed);
    assert.equal(notInOrder.status, 400);
    const badStars = await api('POST', `/api/customer/orders/${id}/review`, { items: [{ productId: 3, rating: 6 }] }, tokens.ahmed);
    assert.equal(badStars.status, 400);

    const r = await api('POST', `/api/customer/orders/${id}/review`, {
      items: [{ productId: 3, rating: 5, comment: 'Great bass, fast delivery' }, { productId: 4, rating: 3 }],
      riderRating: 4,
    }, tokens.ahmed);
    assert.equal(r.status, 201, JSON.stringify(r.body));

    const again = await api('POST', `/api/customer/orders/${id}/review`, { items: [{ productId: 3, rating: 1 }] }, tokens.ahmed);
    assert.equal(again.status, 409);
    assert.equal(again.body.code, 'ALREADY_REVIEWED');

    const after = await api('GET', `/api/customer/orders/${id}`, undefined, tokens.ahmed);
    assert.equal(after.body.data.canReview, false);
    assert.equal(after.body.data.items.find((i) => i.productId === 3).myRating, 5);
  });

  test('outsiders cannot review someone else\'s order', async () => {
    const r = await api('POST', `/api/customer/orders/${id}/review`, { items: [{ productId: 3, rating: 1 }] }, tokens.fatima);
    assert.equal(r.status, 404);
  });

  test('product pages show the average, the star breakdown and the reviews', async () => {
    const p = await api('GET', '/api/products/3');
    assert.equal(p.status, 200);
    assert.equal(p.body.data.averageRating, 5);
    assert.equal(p.body.data.ratingCount, 1);
    assert.equal(p.body.data.ratingDistribution['5'], 1);
    assert.equal(p.body.data.latestReviews[0].comment, 'Great bass, fast delivery');
    assert.equal(p.body.data.latestReviews[0].customerName, 'Ahmed R.', 'surname shortened');

    const list = await api('GET', '/api/products?search=JBL');
    assert.equal(list.body.data[0].averageRating, 5);
    const reviews = await api('GET', '/api/products/4/reviews');
    assert.equal(reviews.body.data[0].rating, 3);

    const store = await api('GET', '/api/vendors/1');
    assert.equal(store.body.data.ratingCount, 2);
    assert.equal(store.body.data.averageRating, 4);
  });

  test('the store and the rider hear about it', async () => {
    const v = await api('GET', '/api/vendor/reviews', undefined, tokens.usman);
    assert.equal(v.body.meta.count, 2);
    const e = await api('GET', '/api/rider/earnings', undefined, tokens.bilal);
    assert.equal(e.body.data.averageRating, 4);
    const n = await query(`SELECT type FROM notifications WHERE order_id = $1 AND type IN ('review_received', 'rider_rated')`, [id]);
    assert.equal(n.rows.length, 2);
  });
});

describe('Packing checklist (FR07)', () => {
  let id;

  test('an order cannot be marked packed until every item is', async () => {
    id = await placeDelivery([{ productId: 1, quantity: 1 }, { productId: 2, quantity: 2 }]);
    await api('PUT', `/api/vendor/orders/${id}/approve`, undefined, tokens.usman);
    const r = await api('PUT', `/api/vendor/orders/${id}/prepare`, undefined, tokens.usman);
    assert.equal(r.status, 409);
    assert.equal(r.body.code, 'PACKING_INCOMPLETE');
    assert.equal(r.body.missing.length, 2);
  });

  test('scanning packs one unit and refuses the wrong item', async () => {
    const wrong = await api('POST', `/api/vendor/orders/${id}/scan`, { barcode: '6925281985642' }, tokens.usman);
    assert.equal(wrong.status, 422);
    assert.equal(wrong.body.code, 'WRONG_ITEM');

    const one = await api('POST', `/api/vendor/orders/${id}/scan`, { barcode: '8481940129871' }, tokens.usman);
    assert.equal(one.status, 200, JSON.stringify(one.body));
    assert.equal(one.body.data.scanned.packed_quantity, 1);
    await api('POST', `/api/vendor/orders/${id}/scan`, { barcode: '8481940129871' }, tokens.usman);
    const extra = await api('POST', `/api/vendor/orders/${id}/scan`, { barcode: '8481940129871' }, tokens.usman);
    assert.equal(extra.status, 409);
    assert.equal(extra.body.code, 'ALREADY_PACKED');

    const phone = await api('POST', `/api/vendor/orders/${id}/scan`, { barcode: '8806094975123' }, tokens.usman);
    assert.equal(phone.body.data.complete, true);
    assert.equal(phone.body.data.packed_units, 3);
  });

  test('ticks can be undone, and packing only happens on accepted orders', async () => {
    const o = await api('GET', `/api/vendor/orders/${id}`, undefined, tokens.usman);
    const item = o.body.data.items[0];
    const undo = await api('PUT', `/api/vendor/orders/${id}/items/${item.id}/pack`, { packed: false }, tokens.usman);
    assert.equal(undo.body.data.complete, false);
    await api('PUT', `/api/vendor/orders/${id}/items/${item.id}/pack`, { packed: true }, tokens.usman);
    const done = await api('PUT', `/api/vendor/orders/${id}/prepare`, undefined, tokens.usman);
    assert.equal(done.status, 200, JSON.stringify(done.body));
    const late = await api('PUT', `/api/vendor/orders/${id}/items/${item.id}/pack`, { packed: false }, tokens.usman);
    assert.equal(late.status, 409);
  });
});

describe('Rider documents and approval', () => {
  let token;
  let userId;

  test('sign-up needs a valid CNIC, licence and vehicle number', async () => {
    const bad = await api('POST', '/api/auth/signup', {
      fullName: 'Kamran Ali', email: 'kamran@rider.pk', password: 'secret123', role: 'rider', vehicleType: 'motorcycle', cnic: '123',
    });
    assert.equal(bad.status, 400);
    const ok = await api('POST', '/api/auth/signup', {
      fullName: 'Kamran Ali', email: 'kamran@rider.pk', password: 'secret123', role: 'rider',
      vehicleType: 'motorcycle', cnic: '4210112345679', licenseNumber: 'khi-dl-1010', vehicleNumber: 'kha 123',
    });
    assert.equal(ok.status, 201, JSON.stringify(ok.body));
    token = ok.body.data.token;
    userId = ok.body.data.user.id;
    const p = await api('GET', '/api/rider/profile', undefined, token);
    assert.equal(p.body.data.approvalStatus, 'pending');
    assert.equal(p.body.data.cnic, '42101-1234567-9', 'CNIC normalised');
    assert.equal(p.body.data.vehicleNumber, 'KHA 123');
  });

  test('a pending rider cannot go online or see tasks', async () => {
    const online = await api('PUT', '/api/rider/status', { isOnline: true, ...SADDAR }, token);
    assert.equal(online.status, 403);
    assert.equal(online.body.code, 'RIDER_NOT_APPROVED');
    const tasks = await api('GET', '/api/rider/tasks', undefined, token);
    assert.equal(tasks.body.data.reason, 'not_approved');
  });

  test('the admin sees the queue, rejects with a reason, the rider resubmits', async () => {
    const queue = await api('GET', '/api/admin/riders?status=pending', undefined, tokens.admin);
    assert.ok(queue.body.data.some((r) => r.id === userId && r.cnic === '42101-1234567-9'));
    const stats = await api('GET', '/api/admin/stats', undefined, tokens.admin);
    assert.ok(stats.body.data.pendingRiders >= 1);

    const noReason = await api('PUT', `/api/admin/riders/${userId}/reject`, {}, tokens.admin);
    assert.equal(noReason.status, 400);
    const reject = await api('PUT', `/api/admin/riders/${userId}/reject`, { reason: 'Licence photo unreadable' }, tokens.admin);
    assert.equal(reject.status, 200);
    const me = await api('GET', '/api/auth/me', undefined, token);
    assert.equal(me.body.data.riderApprovalStatus, 'rejected');
    assert.equal(me.body.data.riderRejectionReason, 'Licence photo unreadable');

    const resubmit = await api('PUT', '/api/rider/documents', { cnic: '42101-1234567-9', licenseNumber: 'KHI-DL-2020', vehicleNumber: 'KHA 123' }, token);
    assert.equal(resubmit.status, 200, JSON.stringify(resubmit.body));
    assert.equal(resubmit.body.data.approvalStatus, 'pending');
  });

  test('once approved the rider can go online', async () => {
    const approve = await api('PUT', `/api/admin/riders/${userId}/approve`, undefined, tokens.admin);
    assert.equal(approve.status, 200);
    const online = await api('PUT', '/api/rider/status', { isOnline: true, ...SADDAR }, token);
    assert.equal(online.status, 200, JSON.stringify(online.body));
    await api('PUT', '/api/rider/status', { isOnline: false }, token);
  });
});

describe('Shop staff roles with PIN switching', () => {
  let cashierId;
  let packerId;
  let cashier;
  let packer;

  test('the owner adds staff; PINs are checked', async () => {
    const bad = await api('POST', '/api/vendor/staff', { fullName: 'Ali', role: 'cashier', pin: '12' }, tokens.usman);
    assert.equal(bad.status, 400);
    const c = await api('POST', '/api/vendor/staff', { fullName: 'Ali Cashier', role: 'cashier', pin: '4321' }, tokens.usman);
    assert.equal(c.status, 201, JSON.stringify(c.body));
    cashierId = c.body.data.id;
    const p = await api('POST', '/api/vendor/staff', { fullName: 'Sara Packer', role: 'packer', pin: '8765' }, tokens.usman);
    packerId = p.body.data.id;
    const roster = await api('GET', '/api/vendor/staff/roster', undefined, tokens.usman);
    assert.equal(roster.body.data.length, 2);
    assert.equal(JSON.stringify(roster.body).includes('pin'), false, 'no PIN data in the roster');

    const wrong = await api('POST', '/api/vendor/staff/switch', { staffId: cashierId, pin: '0000' }, tokens.usman);
    assert.equal(wrong.status, 401);
    assert.equal(wrong.body.attemptsLeft, 4);
    const ok = await api('POST', '/api/vendor/staff/switch', { staffId: cashierId, pin: '4321' }, tokens.usman);
    assert.equal(ok.status, 200);
    cashier = ok.body.data.token;
    assert.deepEqual(ok.body.data.staff.permissions, ['products.view', 'pos']);
    packer = (await api('POST', '/api/vendor/staff/switch', { staffId: packerId, pin: '8765' }, cashier)).body.data.token;
  });

  test('a cashier rings up sales but cannot touch orders, stock, staff or money', async () => {
    const sale = await api('POST', '/api/vendor/pos/sales', { items: [{ productId: 4, quantity: 1 }] }, cashier);
    assert.equal(sale.status, 201, JSON.stringify(sale.body));
    assert.equal(sale.body.data.receipt.cashier, 'Ali Cashier');

    const order = await api('GET', '/api/vendor/orders?scope=active', undefined, cashier);
    assert.equal(order.status, 403);
    assert.equal(order.body.code, 'STAFF_FORBIDDEN');
    assert.equal((await api('PUT', '/api/vendor/products/4', { private_stock: 1 }, cashier)).status, 403);
    assert.equal((await api('GET', '/api/vendor/staff', undefined, cashier)).status, 403);
    const wallet = await api('GET', '/api/wallet', undefined, cashier);
    assert.equal(wallet.status, 403);
    assert.equal(wallet.body.code, 'STAFF_NOT_ALLOWED');
    assert.equal((await api('POST', '/api/withdrawals', { amount: 500 }, cashier)).status, 403);
    const me = await api('GET', '/api/auth/me', undefined, cashier);
    assert.equal(me.body.data.staff.role, 'cashier');
  });

  test('a packer packs and prepares; the order remembers who packed it', async () => {
    const id = await placeDelivery([{ productId: 4, quantity: 1 }]);
    await api('PUT', `/api/vendor/orders/${id}/approve`, undefined, packer);
    assert.equal((await api('POST', '/api/vendor/pos/sales', { items: [{ productId: 4, quantity: 1 }] }, packer)).status, 403);
    await packAll(id, packer);
    const r = await api('PUT', `/api/vendor/orders/${id}/prepare`, undefined, packer);
    assert.equal(r.status, 200, JSON.stringify(r.body));
    const o = await api('GET', `/api/vendor/orders/${id}`, undefined, tokens.usman);
    assert.equal(o.body.data.packed_by_name, 'Sara Packer');
  });

  test('removed staff are signed out at once; five wrong PINs lock', async () => {
    await api('DELETE', `/api/vendor/staff/${cashierId}`, undefined, tokens.usman);
    const r = await api('GET', '/api/vendor/products', undefined, cashier);
    assert.equal(r.status, 401);
    assert.equal(r.body.code, 'STAFF_INACTIVE');

    for (let i = 0; i < 5; i++) await api('POST', '/api/vendor/staff/switch', { staffId: packerId, pin: '1111' }, tokens.usman);
    const locked = await api('POST', '/api/vendor/staff/switch', { staffId: packerId, pin: '8765' }, tokens.usman);
    assert.equal(locked.status, 429);
    assert.equal(locked.body.code, 'PIN_LOCKED');
    // A new PIN from the owner lifts the lock
    await api('PUT', `/api/vendor/staff/${packerId}`, { pin: '2468' }, tokens.usman);
    assert.equal((await api('POST', '/api/vendor/staff/switch', { staffId: packerId, pin: '2468' }, tokens.usman)).status, 200);
  });
});

describe('POS receipts', () => {
  test('a sale returns a slip with the store header, footer and scan-to-pay QR', async () => {
    const settings = await api('PUT', '/api/vendor/receipt-settings', {
      receiptHeader: 'NTN 1234567-8', receiptFooter: 'No returns without receipt', paymentAccount: 'PK36SCBL0000001123456702', paymentAccountTitle: 'Usman Tariq',
    }, tokens.usman);
    assert.equal(settings.status, 200, JSON.stringify(settings.body));
    const sale = await api('POST', '/api/vendor/pos/sales', { items: [{ productId: 2, quantity: 2 }] }, tokens.usman);
    const receipt = sale.body.data.receipt;
    assert.match(receipt.receipt_number, /^POS-\d{6}$/);
    assert.equal(receipt.store.name, 'Karachi Electronics Hub');
    assert.equal(receipt.store.footer, 'No returns without receipt');
    assert.equal(receipt.sale.total_amount, 9998);
    assert.match(receipt.payment_qr.payload, /amount=9998\.00&ref=POS-\d+$/);
    const reprint = await api('GET', `/api/vendor/pos/sales/${sale.body.data.id}`, undefined, tokens.usman);
    assert.equal(reprint.body.data.receipt_number, receipt.receipt_number);
  });
});

describe('Product photo gallery', () => {
  test('vendors add extra photos; the product page lists them after the cover', async () => {
    const png = Buffer.from('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==', 'base64');
    const ids = [];
    for (let i = 0; i < 2; i++) {
      const form = new FormData();
      form.append('image', new Blob([png], { type: 'image/png' }), `p${i}.png`);
      const r = await api('POST', '/api/vendor/products/1/images', form, tokens.usman);
      assert.equal(r.status, 201, JSON.stringify(r.body));
      ids.push(r.body.data.gallery.at(-1).id);
    }
    const p = await api('GET', '/api/products/1');
    assert.equal(p.body.data.images.length, 2, 'first photo became the cover, second is extra');
    const del = await api('DELETE', `/api/vendor/products/1/images/${ids[1]}`, undefined, tokens.usman);
    assert.equal(del.status, 200);
    assert.equal((await api('GET', '/api/products/1')).body.data.images.length, 1);
  });
});

describe('Reservation timer', () => {
  test('a pending order says when its reserved stock is released', async () => {
    const id = await placeDelivery([{ productId: 4, quantity: 1 }]);
    const o = await api('GET', `/api/customer/orders/${id}`, undefined, tokens.ahmed);
    const left = new Date(o.body.data.reservationExpiresAt) - Date.now();
    assert.ok(left > 0 && left <= 30 * 60000, `${left} ms`);
    await api('POST', `/api/customer/orders/${id}/cancel`, undefined, tokens.ahmed);
  });
});

describe('Notification inbox paging', () => {
  test('older alerts come in pages', async () => {
    const first = await api('GET', '/api/notifications?limit=2', undefined, tokens.ahmed);
    assert.equal(first.body.data.notifications.length, 2);
    assert.equal(first.body.meta.hasMore, true);
    const next = await api('GET', `/api/notifications?limit=2&offset=${first.body.meta.nextOffset}`, undefined, tokens.ahmed);
    assert.notEqual(next.body.data.notifications[0].id, first.body.data.notifications[0].id);
  });
});

describe('Security (SSR 01)', () => {
  test('responses carry security headers', async () => {
    const res = await fetch(`${srv.baseUrl}/api/health`);
    assert.equal(res.headers.get('x-content-type-options'), 'nosniff');
    assert.equal(res.headers.get('x-powered-by'), null);
    assert.ok(res.headers.get('strict-transport-security'));
    assert.ok(res.headers.get('ratelimit-policy'), 'rate limit headers');
  });

  test('ten failed sign-ins lock that email out, even with the right password', async () => {
    for (let i = 0; i < 10; i++) {
      const r = await api('POST', '/api/auth/login', { email: 'fatima@customer.pk', password: 'wrong-password' });
      assert.equal(r.status, 401);
    }
    const blocked = await api('POST', '/api/auth/login', { email: 'fatima@customer.pk', password: 'password123' });
    assert.equal(blocked.status, 429);
    assert.equal(blocked.body.code, 'LOGIN_RATE_LIMITED');
    // Other accounts from the same address are unaffected
    assert.equal((await api('POST', '/api/auth/login', { email: 'ahmed@customer.pk', password: 'password123' })).status, 200);
  });

  test('money still balances after all of the above', async () => {
    const m = await moneyInvariant();
    assert.equal(m.accounted.toFixed(2), m.deposits.toFixed(2));
    assert.equal(m.pool.toFixed(2), m.held.toFixed(2));
  });
});
