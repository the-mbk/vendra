// ══════════════════════════════════════════════════════════════
// Vendra Backend - Demo data (development only)
//
// Fills a freshly migrated, empty database with a living marketplace in
// Islamabad and Rawalpindi: ~1,000 users (stores, riders, customers), ~1,900
// products with real photos, and 90 days of order history whose money adds
// up exactly (wallets + escrow + platform revenue = opening balances).
//
//   npm run seed                 1,000 users
//   npm run seed -- --users=3000 a bigger city
//
// Product names, descriptions and photos come from dummyjson.com (cached in
// backend/.cache/ after the first run). Photos are stored in the configured
// file storage (the SeaweedFS bucket locally). Every account's password is
// password123. The data is generated from a fixed seed, so it's the same
// every time.
// ══════════════════════════════════════════════════════════════

require('dotenv').config();

const fs = require('fs');
const { Client } = require('pg');
const { createRandom } = require('./demoData/random');
const { MARKETS, NEIGHBOURHOODS, pointIn, homeAddress, shopAddress } = require('./demoData/places');
const { personName, phone, cnic, makeEmails, STORE_TYPES, STORE_PREFIXES } = require('./demoData/people');
const { loadCatalog } = require('./demoData/catalog');
const { haversineKm } = require('./utils/geo');
const { deliveryFeePaisa } = require('./services/deliveryFee');
const { toPaisa, paisaToString, percentOf } = require('./utils/money');

const PASSWORD_HASH = '$2b$10$wxA3oAhNajZeHYp3m8a.YeMXgbOYx0QlSIDZlgWPJtW2le7OWS2se'; // password123
const MIN = 60 * 1000;
const HOUR = 60 * MIN;
const DAY = 24 * HOUR;
const HISTORY_DAYS = 90;

// The accounts listed on the login screens (config/demoAccounts.js)
const DEMO = {
  admin: { full: 'Vendra Admin', email: 'admin@vendra.pk', phone: '0300-1234567' },
  vendors: [
    { full: 'Usman Tariq', email: 'usman@vendor.pk', phone: '0321-5551234', type: 'electronics', area: 'Blue Area', store: 'Capital Electronics Hub' },
    { full: 'Ayesha Khan', email: 'ayesha@vendor.pk', phone: '0333-7778899', type: 'fashion', area: 'Saddar', store: "Ayesha's Boutique" },
  ],
  customers: [
    { full: 'Ahmed Raza', email: 'ahmed@customer.pk', phone: '0312-4445566', area: 'F-7' },
    { full: 'Fatima Ali', email: 'fatima@customer.pk', phone: '0345-9998877', area: 'Satellite Town' },
  ],
  riders: [
    { full: 'Bilal Hussain', email: 'bilal@rider.pk', phone: '0301-2223344', area: 'G-9' },
    { full: 'Hamza Sheikh', email: 'hamza@rider.pk', phone: '0302-6667788', area: 'Saddar' },
  ],
};

const areaNamed = (name) => MARKETS.find((a) => a.name === name);

/** EAN-13 with the Pakistan GS1 prefix 896 */
function ean13(r) {
  const body = `896${r.digits(9)}`;
  const sum = [...body].reduce((s, d, i) => s + Number(d) * (i % 2 ? 3 : 1), 0);
  return body + ((10 - (sum % 10)) % 10);
}

function priceNear(r, rs) {
  const v = rs * r.float(0.92, 1.1);
  const step = v < 1000 ? 10 : v < 10000 ? 50 : 500;
  return Math.max(step, Math.round(v / step) * step);
}

// ──────────────────────────────────────
// Build everything in memory
// ──────────────────────────────────────

function buildDataset({ users: totalUsers }, catalog, policy, now) {
  const r = createRandom();
  const email = makeEmails();
  const at = (msAgo) => new Date(now - msAgo);
  const nVendors = Math.max(DEMO.vendors.length, Math.round(totalUsers * 0.12));
  const nRiders = Math.max(DEMO.riders.length, Math.round(totalUsers * 0.15));
  const nCustomers = Math.max(DEMO.customers.length, totalUsers - 1 - nVendors - nRiders);

  const users = [];
  const addUser = (u) => {
    const user = { id: users.length + 1, wallet: 0, ...u };
    users.push(user);
    return user;
  };

  addUser({ full: DEMO.admin.full, email: DEMO.admin.email, phone: DEMO.admin.phone, role: 'admin', created: at(260 * DAY) });

  // ── Stores ──
  const usedStoreNames = new Set();
  const typeWeights = Object.entries(STORE_TYPES).map(([k, t]) => [k, t.weight]);
  const marketWeights = MARKETS.map((a) => [a, a.city === 'Islamabad' ? 1.2 : 1]);
  const vendors = [];
  for (let i = 0; i < nVendors; i++) {
    const demo = DEMO.vendors[i];
    const type = demo?.type ?? r.weighted(typeWeights);
    const area = demo ? areaNamed(demo.area) : r.weighted(marketWeights);
    const name = demo ? { full: demo.full } : personName(r, { female: r.chance(0.2) });
    let store = demo?.store;
    while (!store || usedStoreNames.has(store)) {
      const base = `${r.pick(STORE_PREFIXES)} ${r.pick(STORE_TYPES[type].names)}`;
      store = usedStoreNames.has(base) ? `${base} ${area.name}` : base;
      if (usedStoreNames.has(store)) store = null;
    }
    usedStoreNames.add(store);
    const created = at(r.int(130, 240) * DAY + r.int(0, DAY));
    const owner = addUser({
      full: name.full,
      email: demo?.email ?? email(name.first, name.last),
      phone: demo?.phone ?? phone(r),
      role: 'vendor',
      created,
    });
    vendors.push({
      id: vendors.length + 1,
      user: owner,
      type,
      area,
      store,
      address: shopAddress(r, area),
      cnic: cnic(r, area.city),
      point: pointIn(r, area, 0.5),
      approved: demo ? true : r.chance(0.92),
      created,
      products: [],
    });
  }

  // ── Products ──
  const byGroup = {};
  for (const item of catalog) (byGroup[item.group] ||= []).push(item);
  const usedBarcodes = new Set();
  const products = [];
  for (const v of vendors) {
    const t = STORE_TYPES[v.type];
    // Luxury items (e.g. Rs 4M watches) don't fit a neighbourhood marketplace
    const pool = t.groups.flatMap((g) => byGroup[g] || []).filter((item) => item.priceRs <= 600000);
    const want = v.user.email === 'usman@vendor.pk' || v.user.email === 'ayesha@vendor.pk' ? pool.length : r.int(...t.products);
    for (const item of r.sample(pool, want)) {
      const price = priceNear(r, item.priceRs);
      const expensive = price >= 100000;
      let barcode;
      do barcode = ean13(r); while (usedBarcodes.has(barcode));
      usedBarcodes.add(barcode);
      const p = {
        id: products.length + 1,
        vendor: v,
        item,
        name: item.title,
        description: item.brand && !item.description.includes(item.brand) ? `${item.description} Brand: ${item.brand}.` : item.description,
        pricePaisa: toPaisa(price),
        finalStock: r.chance(0.06) ? r.int(0, 2) : expensive ? r.int(1, 12) : r.int(6, 140),
        buffer: expensive ? 1 : r.int(2, 6),
        approved: v.approved ? r.chance(0.96) : r.chance(0.5),
        barcode,
        created: new Date(v.created.getTime() + r.int(0, 25) * DAY),
        sold: [], // { orderId, qty, at }
      };
      products.push(p);
      v.products.push(p);
    }
  }

  // ── Riders ──
  const riders = [];
  const vehicles = [['motorcycle', 85], ['bicycle', 9], ['car', 6]];
  for (let i = 0; i < nRiders; i++) {
    const demo = DEMO.riders[i];
    const area = demo ? areaNamed(demo.area) : r.pick(NEIGHBOURHOODS);
    const name = demo ? { full: demo.full } : personName(r, { female: r.chance(0.04) });
    const user = addUser({
      full: name.full,
      email: demo?.email ?? email(name.first, name.last),
      phone: demo?.phone ?? phone(r),
      role: 'rider',
      created: at(r.int(95, 220) * DAY),
    });
    riders.push({ id: riders.length + 1, user, area, vehicle: r.weighted(vehicles), point: pointIn(r, area, 1.5), lastSeen: at(r.int(1, 96) * HOUR) });
  }

  // ── Customers ──
  const customers = [];
  for (let i = 0; i < nCustomers; i++) {
    const demo = DEMO.customers[i];
    const area = demo ? areaNamed(demo.area) : r.pick(NEIGHBOURHOODS);
    const name = demo ? { full: demo.full } : personName(r);
    const recent = !demo && r.chance(0.3);
    const user = addUser({
      full: name.full,
      email: demo?.email ?? email(name.first, name.last),
      phone: demo?.phone ?? phone(r),
      role: 'customer',
      created: at((recent ? r.int(3, HISTORY_DAYS) : r.int(HISTORY_DAYS + 5, 240)) * DAY),
    });
    customers.push({ user, area, demo: !!demo, home: pointIn(r, area, 0.8), address: homeAddress(r, area) });
  }

  // ── Orders and money ──
  const openStores = vendors.filter((v) => v.approved && v.products.filter((p) => p.approved).length >= 3);
  const ridersNear = new Map(openStores.map((v) => {
    const near = riders.filter((rd) => haversineKm(rd.point.lat, rd.point.lng, v.point.lat, v.point.lng) <= 10);
    return [v, near.length ? near : riders.filter((rd) => rd.area.city === v.area.city)];
  }));

  const orders = [];
  const items = [];
  const events = []; // wallet movements: { user, at, type, amount (signed paisa), orderId, description }
  const platform = []; // { orderId, type, amount, at }
  let escrowPool = 0;

  for (const c of customers) {
    const n = c.demo ? 14 : r.weighted([[0, 15], [r.int(1, 3), 35], [r.int(4, 8), 35], [r.int(9, 20), 15]]);
    const stores = openStores
      .map((v) => ({ v, km: haversineKm(c.home.lat, c.home.lng, v.point.lat, v.point.lng) }))
      .sort((a, b) => a.km - b.km);
    const nearby = stores.filter((s) => s.km <= 8);
    const choices = (nearby.length >= 5 ? nearby : stores.slice(0, 15)).slice(0, 30);
    const from = Math.max(c.user.created.getTime(), now - HISTORY_DAYS * DAY);
    let maxCancelled = 0;
    let spent = 0;

    for (let k = 0; k < n; k++) {
      const { v, km: storeKm } = r.pick(choices);
      const delivery = r.chance(0.85) && !(policy.max_delivery_km > 0 && storeKm > policy.max_delivery_km);
      // Newer orders are more common; delivery orders end at least 3 h before now
      const created = from + (now - 3 * HOUR - from) * Math.sqrt(r.next());
      // Everyday items are bought far more often than Rs 100k+ ones
      const basket = v.products.filter((p) => p.approved && (p.pricePaisa < toPaisa(100000) || r.chance(0.2)));
      const lines = r.sample(basket.length ? basket : v.products.filter((p) => p.approved), r.weighted([[1, 55], [2, 30], [3, 15]]))
        .map((p) => ({ p, qty: p.pricePaisa >= toPaisa(50000) ? 1 : r.weighted([[1, 70], [2, 22], [3, 8]]) }));
      const subtotal = lines.reduce((s, l) => s + l.p.pricePaisa * l.qty, 0);
      const straightKm = haversineKm(v.point.lat, v.point.lng, c.home.lat, c.home.lng);
      const fee = delivery ? deliveryFeePaisa(policy, straightKm) : 0;
      const total = subtotal + fee;
      const id = orders.length + 1;

      const o = {
        id, customer: c, vendor: v, delivery, created: new Date(created), subtotal, fee, total,
        estimated: delivery ? Math.max(15, Math.round(straightKm * 3)) : null,
        rider: null, readyAt: null, assignedAt: null, arrivedAt: null, pickedAt: null, deliveredAt: null,
        km: null, wait: null, payout: 0, status: 'delivered', escrow: 'released', dueAt: null, settledAt: null, reason: null,
      };
      orders.push(o);
      for (const l of lines) {
        items.push({ id: items.length + 1, orderId: id, productId: l.p.id, qty: l.qty, unit: l.p.pricePaisa });
      }
      events.push({ user: c.user, at: o.created, type: 'escrow_hold', amount: -total, orderId: id, description: `Escrow hold for Order #${id}` });

      if (r.chance(0.1)) {
        // Cancelled and refunded
        const reason = r.weighted([['Customer cancelled', 35], ['Vendor cancelled', 25], ["Store didn't respond in time", 20], ...(delivery ? [['No rider available', 20]] : [])]);
        o.status = 'cancelled';
        o.escrow = 'refunded';
        o.reason = reason;
        let settled = created + r.int(2, 25) * MIN;
        if (reason === "Store didn't respond in time") settled = created + policy.vendor_accept_timeout_min * MIN;
        if (reason === 'No rider available') {
          o.readyAt = new Date(created + r.int(8, 30) * MIN);
          settled = o.readyAt.getTime() + policy.rider_assign_timeout_min * MIN;
        }
        o.settledAt = new Date(Math.min(settled, now - MIN));
        events.push({ user: c.user, at: o.settledAt, type: 'escrow_refund', amount: total, orderId: id, description: `Escrow refund for cancelled Order #${id}` });
        maxCancelled = Math.max(maxCancelled, total);
        continue;
      }

      spent += total;
      o.readyAt = new Date(created + r.int(8, 35) * MIN);
      if (delivery) {
        const rider = r.pick(ridersNear.get(v));
        o.rider = rider;
        o.assignedAt = new Date(o.readyAt.getTime() + r.int(1, 10) * MIN);
        o.arrivedAt = new Date(o.assignedAt.getTime() + r.int(4, 15) * MIN);
        o.wait = r.chance(0.7) ? r.int(0, 5) : r.int(6, 18);
        o.pickedAt = new Date(o.arrivedAt.getTime() + o.wait * MIN);
        o.km = Number(Math.max(0.6, straightKm * r.float(1.15, 1.4)).toFixed(3));
        o.deliveredAt = new Date(o.pickedAt.getTime() + Math.round(o.km * 2.5 + r.int(3, 10)) * MIN);
        o.payout = toPaisa(policy.rider_base_fee + policy.rider_per_km * o.km
          + policy.rider_per_wait_min * Math.max(0, o.wait - policy.rider_free_wait_min));
        events.push({ user: rider.user, at: o.deliveredAt, type: 'rider_payout', amount: o.payout, orderId: id, description: `Delivery payout for Order #${id}` });
      } else {
        o.deliveredAt = new Date(o.readyAt.getTime() + r.int(20, 300) * MIN);
        o.pickedAt = o.deliveredAt;
      }
      if (o.deliveredAt.getTime() > now - 2 * MIN) o.deliveredAt = new Date(now - 2 * MIN);
      for (const l of lines) l.p.sold.push({ orderId: id, qty: l.qty, at: o.deliveredAt });

      o.dueAt = new Date(o.deliveredAt.getTime() + policy.dispute_window_min * MIN);
      if (o.dueAt.getTime() <= now) {
        // Escrow released after the dispute window
        o.settledAt = o.dueAt;
        const commission = percentOf(subtotal, policy.commission_pct);
        events.push({ user: v.user, at: o.settledAt, type: 'escrow_release', amount: subtotal - commission, orderId: id, description: `Escrow released for Order #${id} (after ${policy.commission_pct}% commission)` });
        if (commission) platform.push({ orderId: id, type: 'commission', amount: commission, at: o.settledAt });
        if (fee - o.payout) platform.push({ orderId: id, type: 'delivery_margin', amount: fee - o.payout, at: o.settledAt });
      } else {
        // Delivered within the last day: still held; the backend releases it when due
        o.escrow = 'held';
        escrowPool += total - o.payout;
      }
    }

    // Money they had before the gateway existed: enough for every order, plus something left over
    const leftover = c.demo ? toPaisa(150000) : toPaisa(r.int(20, 400) * 100);
    events.push({
      user: c.user,
      at: c.user.created,
      type: 'opening_balance',
      amount: spent + Math.max(leftover, maxCancelled),
      orderId: null,
      description: 'Opening balance (demo data)',
    });
  }

  // Wallet ledger: running balances in time order
  events.sort((a, b) => a.at - b.at || (b.amount > 0) - (a.amount > 0));
  const walletLedger = events.map((e, i) => {
    e.user.wallet += e.amount;
    if (e.user.wallet < 0) throw new Error(`Generated a negative balance for ${e.user.email}`);
    return { id: i + 1, ...e, balanceAfter: e.user.wallet };
  });

  // Inventory ledger: opening stock, then each delivered sale
  const inventory = [];
  for (const p of products) {
    const sold = p.sold.sort((a, b) => a.at - b.at);
    let stock = p.finalStock + sold.reduce((s, x) => s + x.qty, 0);
    const pub = (n) => Math.max(0, n - p.buffer);
    inventory.push({ p, type: 'stock_in', change: stock, privateAfter: stock, publicAfter: pub(stock), ref: null, notes: 'Opening stock', at: p.created });
    for (const s of sold) {
      stock -= s.qty;
      inventory.push({ p, type: 'sale', change: -s.qty, privateAfter: stock, publicAfter: pub(stock), ref: s.orderId, notes: 'Online order delivered', at: s.at });
    }
  }

  return { users, vendors, products, riders, customers, orders, items, walletLedger, platform, inventory, escrowPool };
}

// ──────────────────────────────────────
// Write it
// ──────────────────────────────────────

async function bulkInsert(client, table, columns, rows) {
  const per = Math.floor(60000 / columns.length);
  for (let i = 0; i < rows.length; i += per) {
    const chunk = rows.slice(i, i + per);
    const params = [];
    const values = chunk.map((row, ri) => {
      params.push(...row);
      return `(${columns.map((_, ci) => `$${ri * columns.length + ci + 1}`).join(', ')})`;
    });
    await client.query(`INSERT INTO ${table} (${columns.join(', ')}) VALUES ${values.join(', ')}`, params);
  }
}

async function writeDataset(client, d) {
  const money = paisaToString;
  await bulkInsert(client, 'users', ['id', 'full_name', 'email', 'phone', 'password_hash', 'role', 'wallet_balance', 'created_at'],
    d.users.map((u) => [u.id, u.full, u.email, u.phone, PASSWORD_HASH, u.role, money(u.wallet), u.created]));
  await bulkInsert(client, 'vendors', ['id', 'user_id', 'store_name', 'store_address', 'cnic', 'latitude', 'longitude', 'is_approved', 'created_at'],
    d.vendors.map((v) => [v.id, v.user.id, v.store, v.address, v.cnic, v.point.lat, v.point.lng, v.approved, v.created]));
  await client.query('UPDATE users u SET vendor_id = v.id FROM vendors v WHERE v.user_id = u.id');
  await bulkInsert(client, 'riders', ['id', 'user_id', 'vehicle_type', 'is_online', 'current_lat', 'current_lng', 'last_location_at', 'created_at'],
    d.riders.map((rd) => [rd.id, rd.user.id, rd.vehicle, false, rd.point.lat, rd.point.lng, rd.lastSeen, rd.user.created]));
  await bulkInsert(client, 'products',
    ['id', 'vendor_id', 'name', 'description', 'price', 'private_stock', 'buffer', 'reserved_quantity', 'public_stock', 'barcode', 'image_url', 'category_id', 'is_approved', 'is_active', 'created_at', 'updated_at'],
    d.products.map((p) => [p.id, p.vendor.id, p.name, p.description, money(p.pricePaisa), p.finalStock, p.buffer, 0,
      Math.max(0, p.finalStock - p.buffer), p.barcode, p.item.imageFile ? `/uploads/products/catalog-${p.item.key}.webp` : null,
      p.item.categoryId, p.approved, true, p.created, p.created]));
  await bulkInsert(client, 'orders',
    ['id', 'customer_id', 'vendor_id', 'status', 'subtotal', 'delivery_fee', 'total_amount', 'delivery_type', 'delivery_address',
      'customer_lat', 'customer_lng', 'estimated_minutes', 'payment_method', 'rider_user_id', 'ready_at', 'assigned_at', 'rider_arrived_at',
      'picked_at', 'delivered_at', 'delivery_lat', 'delivery_lng', 'distance_km', 'wait_minutes', 'rider_payout', 'escrow_status',
      'escrow_release_due_at', 'escrow_settled_at', 'cancellation_reason', 'created_at', 'updated_at'],
    d.orders.map((o) => {
      const delivered = o.status === 'delivered';
      const pin = o.delivery ? o.customer.home : { lat: null, lng: null };
      return [o.id, o.customer.user.id, o.vendor.id, o.status, money(o.subtotal), money(o.fee), money(o.total),
        o.delivery ? 'delivery' : 'self_pickup', o.delivery ? o.customer.address : null, pin.lat, pin.lng, o.estimated, 'wallet',
        o.rider?.user.id ?? null, o.readyAt, o.assignedAt, o.arrivedAt, delivered ? o.pickedAt : null, o.deliveredAt,
        delivered && o.delivery ? pin.lat : null, delivered && o.delivery ? pin.lng : null, o.km, o.wait, money(o.payout), o.escrow,
        o.dueAt, o.settledAt, o.reason, o.created, o.settledAt ?? o.deliveredAt ?? o.created];
    }));
  await bulkInsert(client, 'order_items', ['id', 'order_id', 'product_id', 'quantity', 'unit_price', 'subtotal'],
    d.items.map((i) => [i.id, i.orderId, i.productId, i.qty, money(i.unit), money(i.unit * i.qty)]));
  await bulkInsert(client, 'inventory_ledger',
    ['id', 'product_id', 'vendor_id', 'change_type', 'quantity_change', 'private_stock_after', 'public_stock_after', 'reference_id', 'notes', 'created_at'],
    d.inventory.map((e, i) => [i + 1, e.p.id, e.p.vendor.id, e.type, e.change, e.privateAfter, e.publicAfter, e.ref, e.notes, e.at]));
  await bulkInsert(client, 'wallet_ledger', ['id', 'user_id', 'order_id', 'transaction_type', 'amount', 'balance_after', 'description', 'created_at'],
    d.walletLedger.map((e) => [e.id, e.user.id, e.orderId, e.type, money(Math.abs(e.amount)), money(e.balanceAfter), e.description, e.at]));
  await bulkInsert(client, 'platform_ledger', ['id', 'order_id', 'entry_type', 'amount', 'created_at'],
    d.platform.map((e, i) => [i + 1, e.orderId, e.type, money(e.amount), e.at]));
  await client.query(
    'INSERT INTO platform_escrow_wallet (id, balance) VALUES (1, $1) ON CONFLICT (id) DO UPDATE SET balance = EXCLUDED.balance',
    [money(d.escrowPool)]
  );

  for (const [table, seq] of [['users', 'users_id_seq'], ['vendors', 'vendors_id_seq'], ['riders', 'riders_id_seq'],
    ['products', 'products_id_seq'], ['orders', 'orders_id_seq'], ['order_items', 'order_items_id_seq'],
    ['inventory_ledger', 'inventory_ledger_id_seq'], ['wallet_ledger', 'wallet_ledger_id_seq'], ['platform_ledger', 'platform_ledger_id_seq']]) {
    await client.query(`SELECT setval('${seq}', GREATEST((SELECT COALESCE(MAX(id), 0) FROM ${table}), 1))`);
  }
}

/** Copies the photos the products use into file storage (once each; products share them) */
async function uploadPhotos(products, log) {
  const { storageDriver, initStorage } = require('./services/storage.service');
  const where = await initStorage();
  const items = [...new Map(products.filter((p) => p.item.imageFile).map((p) => [p.item.key, p.item])).values()];
  for (let i = 0; i < items.length; i += 8) {
    await Promise.all(items.slice(i, i + 8).map((item) =>
      storageDriver.save('products', `catalog-${item.key}.webp`, fs.readFileSync(item.imageFile), 'image/webp')));
  }
  log(`  ${items.length} product photos stored in ${where}`);
}

async function seed(connectionString = process.env.DATABASE_URL, { users = 1000, log = console.log } = {}) {
  if (require('./config/mode').isProduction) {
    throw new Error('Demo data is never loaded in production mode (APP_MODE=production).');
  }
  const client = new Client({ connectionString });
  await client.connect();
  try {
    const existing = await client.query('SELECT COUNT(*) FROM users');
    if (Number(existing.rows[0].count) > 0) {
      throw new Error('Database already has users. Demo data only goes into an empty, freshly migrated database (reset it with .\\run-local.ps1 -Reset).');
    }
    const policy = Object.fromEntries((await client.query('SELECT key, value FROM policies')).rows.map((p) => [p.key, Number(p.value)]));

    log('Building the Islamabad & Rawalpindi demo marketplace…');
    const catalog = await loadCatalog({ log });
    const d = buildDataset({ users }, catalog, policy, Date.now());
    await uploadPhotos(d.products, log);

    await client.query('BEGIN');
    try {
      await writeDataset(client, d);
      await client.query('COMMIT');
    } catch (err) {
      await client.query('ROLLBACK');
      throw err;
    }

    const delivered = d.orders.filter((o) => o.status === 'delivered').length;
    log(`✓ ${d.users.length} users: ${d.vendors.length} stores (${d.vendors.filter((v) => v.approved).length} approved), `
      + `${d.riders.length} riders, ${d.customers.length} customers, 1 admin`);
    log(`✓ ${d.products.length} products, ${d.orders.length} orders over ${HISTORY_DAYS} days `
      + `(${delivered} delivered, ${d.orders.length - delivered} cancelled, ${d.orders.filter((o) => o.escrow === 'held').length} still in escrow)`);
    log('✓ Every account uses the password password123. Demo logins: admin@vendra.pk, usman@vendor.pk, ahmed@customer.pk, bilal@rider.pk');
  } finally {
    await client.end();
  }
}

if (require.main === module) {
  const arg = process.argv.find((a) => a.startsWith('--users='));
  const users = arg ? Number(arg.split('=')[1]) : 1000;
  if (!Number.isInteger(users) || users < 50 || users > 20000) {
    console.error('✗ --users must be a whole number between 50 and 20000');
    process.exit(1);
  }
  seed(process.env.DATABASE_URL, { users }).catch((err) => {
    console.error('✗ Seed failed:', err.message);
    process.exit(1);
  });
}

module.exports = { seed, buildDataset };
