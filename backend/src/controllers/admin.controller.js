// ══════════════════════════════════════════════════════════════
// Vendra Backend - Admin Controller
// Stats, vendor + product approval, policies, riders, finance, users, orders
// ══════════════════════════════════════════════════════════════

const crypto = require('crypto');
const bcrypt = require('bcrypt');
const pool = require('../db');
const { SALT_ROUNDS } = require('./auth.controller');
const { getEscrowPoolBalanceReadOnly } = require('../services/escrowPool.service');
const { listPolicies } = require('../services/policy.service');
const { notify } = require('../services/notification.service');
const { broadcast } = require('../realtime');
const { httpError, asyncHandler, withTransaction, intParam } = require('../utils/http');

/** GET /api/admin/stats */
const getDashboardStats = asyncHandler(async (req, res) => {
  const [vendors, users, orders, products, disputes] = await Promise.all([
    pool.query(`SELECT COUNT(*) FILTER (WHERE is_approved) AS approved,
                       COUNT(*) FILTER (WHERE NOT is_approved) AS pending, COUNT(*) AS total FROM vendors`),
    pool.query(`SELECT COUNT(*) FILTER (WHERE u.role = 'customer') AS customers,
                       COUNT(*) FILTER (WHERE u.role = 'rider') AS riders,
                       COUNT(*) FILTER (WHERE r.is_online) AS riders_online
                FROM users u LEFT JOIN riders r ON r.user_id = u.id`),
    pool.query(`SELECT COUNT(*) AS total,
                       COUNT(*) FILTER (WHERE created_at::date = CURRENT_DATE) AS today,
                       COALESCE(SUM(total_amount) FILTER (WHERE status <> 'cancelled'), 0) AS total_revenue,
                       COALESCE(SUM(total_amount) FILTER (WHERE status <> 'cancelled' AND created_at::date = CURRENT_DATE), 0) AS today_revenue,
                       COUNT(*) FILTER (WHERE status NOT IN ('delivered', 'cancelled')) AS in_progress
                FROM orders`),
    pool.query(`SELECT COUNT(*) FILTER (WHERE is_active) AS total,
                       COUNT(*) FILTER (WHERE is_active AND NOT is_approved) AS pending FROM products`),
    pool.query(`SELECT COUNT(*) FILTER (WHERE status = 'open') AS open FROM disputes`),
  ]);
  const platform = await pool.query('SELECT COALESCE(SUM(amount), 0) AS total FROM platform_ledger');

  res.json({
    success: true,
    data: {
      vendors: vendors.rows[0],
      customers: Number(users.rows[0].customers),
      riders: Number(users.rows[0].riders),
      ridersOnline: Number(users.rows[0].riders_online),
      orders: {
        total: Number(orders.rows[0].total),
        today: Number(orders.rows[0].today),
        inProgress: Number(orders.rows[0].in_progress),
        totalRevenue: Number(orders.rows[0].total_revenue),
        todayRevenue: Number(orders.rows[0].today_revenue),
      },
      products: Number(products.rows[0].total),
      pendingProducts: Number(products.rows[0].pending),
      openDisputes: Number(disputes.rows[0].open),
      escrowHeld: await getEscrowPoolBalanceReadOnly(),
      platformRevenue: Number(platform.rows[0].total),
    },
  });
});

// ──────────────────────────────────────
// Vendors
// ──────────────────────────────────────

/** GET /api/admin/vendors */
const getAllVendors = asyncHandler(async (req, res) => {
  const r = await pool.query(
    `SELECT v.id, v.store_name, v.store_address, v.cnic, v.is_approved, v.created_at, v.latitude, v.longitude,
            u.id AS user_id, u.full_name, u.email, u.phone,
            (SELECT COUNT(*) FROM products p WHERE p.vendor_id = v.id AND p.is_active) AS product_count,
            (SELECT COALESCE(SUM(o.total_amount), 0) FROM orders o WHERE o.vendor_id = v.id AND o.status <> 'cancelled') AS total_revenue
     FROM vendors v JOIN users u ON u.id = v.user_id
     ORDER BY v.created_at DESC`
  );
  res.json({
    success: true,
    data: r.rows.map((v) => ({
      id: v.id,
      userId: v.user_id,
      storeName: v.store_name,
      storeAddress: v.store_address,
      cnic: v.cnic,
      isApproved: v.is_approved,
      hasLocation: v.latitude != null,
      ownerName: v.full_name,
      email: v.email,
      phone: v.phone,
      productCount: Number(v.product_count),
      totalRevenue: Number(v.total_revenue),
      createdAt: v.created_at,
    })),
  });
});

function setVendorApproval(approved) {
  return asyncHandler(async (req, res) => {
    const vendorId = intParam(req.params.id);
    const vendor = await withTransaction(async (client, afterCommit) => {
      const r = await client.query(
        'UPDATE vendors SET is_approved = $1 WHERE id = $2 RETURNING id, user_id, store_name, is_approved',
        [approved, vendorId]
      );
      if (r.rows.length === 0) throw httpError(404, 'Vendor not found.');
      await notify(client, afterCommit, r.rows[0].user_id, approved
        ? { type: 'vendor_approved', title: 'Your store is approved', body: 'Customers can now see and order your products.' }
        : { type: 'vendor_suspended', title: 'Your store has been suspended', body: 'Contact Vendra support for details.' });
      afterCommit.push(() => broadcast('catalog:update', { vendorId }));
      return r.rows[0];
    });
    res.json({
      success: true,
      message: `Vendor "${vendor.store_name}" has been ${approved ? 'approved' : 'disapproved'}.`,
      data: { id: vendor.id, store_name: vendor.store_name, is_approved: vendor.is_approved },
    });
  });
}

const approveVendor = setVendorApproval(true);
const disapproveVendor = setVendorApproval(false);

// ──────────────────────────────────────
// Product catalog approval (FR06)
// ──────────────────────────────────────

/** GET /api/admin/products?status=pending|approved|all */
const getProducts = asyncHandler(async (req, res) => {
  const status = req.query.status || 'pending';
  const filter = status === 'pending' ? 'AND NOT p.is_approved' : status === 'approved' ? 'AND p.is_approved' : '';
  const r = await pool.query(
    `SELECT p.id, p.name, p.description, p.price, p.private_stock, p.public_stock, p.buffer, p.reserved_quantity,
            p.barcode, p.image_url, p.is_approved, p.created_at, v.id AS vendor_id, v.store_name, c.name AS category_name
     FROM products p
     JOIN vendors v ON v.id = p.vendor_id
     LEFT JOIN categories c ON c.id = p.category_id
     WHERE p.is_active ${filter}
     ORDER BY p.is_approved, p.created_at DESC`
  );
  res.json({
    success: true,
    data: r.rows.map((p) => ({
      id: p.id,
      name: p.name,
      description: p.description,
      price: Number(p.price),
      privateStock: p.private_stock,
      publicStock: p.public_stock,
      buffer: p.buffer,
      reservedQuantity: p.reserved_quantity,
      barcode: p.barcode,
      imageUrl: p.image_url,
      isApproved: p.is_approved,
      vendorId: p.vendor_id,
      storeName: p.store_name,
      categoryName: p.category_name,
      createdAt: p.created_at,
    })),
  });
});

function setProductApproval(approved) {
  return asyncHandler(async (req, res) => {
    const productId = intParam(req.params.id);
    const product = await withTransaction(async (client, afterCommit) => {
      const r = await client.query(
        `UPDATE products p SET is_approved = $1, updated_at = NOW()
         FROM vendors v WHERE p.id = $2 AND v.id = p.vendor_id AND p.is_active
         RETURNING p.id, p.name, p.vendor_id, p.is_approved, v.user_id AS vendor_user_id`,
        [approved, productId]
      );
      if (r.rows.length === 0) throw httpError(404, 'Product not found.');
      const p = r.rows[0];
      await notify(client, afterCommit, p.vendor_user_id, approved
        ? { type: 'product_approved', title: `"${p.name}" is live`, body: 'Customers can now find and order it.' }
        : { type: 'product_hidden', title: `"${p.name}" was hidden`, body: 'An admin removed it from the marketplace.' });
      afterCommit.push(() => broadcast('catalog:update', { productId: p.id, vendorId: p.vendor_id }));
      return p;
    });
    res.json({
      success: true,
      message: `"${product.name}" ${approved ? 'approved' : 'hidden from the marketplace'}.`,
      data: { id: product.id, isApproved: product.is_approved },
    });
  });
}

const approveProduct = setProductApproval(true);
const hideProduct = setProductApproval(false);

// ──────────────────────────────────────
// Policy engine
// ──────────────────────────────────────

/** GET /api/admin/policies */
const getPolicies = asyncHandler(async (req, res) => {
  res.json({ success: true, data: await listPolicies() });
});

/** PUT /api/admin/policies  Body: { values: { key: number, ... } } */
const updatePolicies = asyncHandler(async (req, res) => {
  const values = req.body.values;
  if (!values || typeof values !== 'object' || Array.isArray(values)) {
    throw httpError(400, 'Send { values: { key: number } }.');
  }

  await withTransaction(async (client) => {
    const known = await client.query('SELECT key, unit FROM policies');
    const units = new Map(known.rows.map((r) => [r.key, r.unit]));

    for (const [key, raw] of Object.entries(values)) {
      if (!units.has(key)) throw httpError(400, `Unknown policy "${key}".`);
      const value = Number(raw);
      if (!Number.isFinite(value) || value < 0) throw httpError(400, `"${key}" must be a number of 0 or more.`);
      if (units.get(key) === '%' && value > 100) throw httpError(400, `"${key}" can't be more than 100%.`);
      if (units.get(key) === '0/1' && ![0, 1].includes(value)) throw httpError(400, `"${key}" must be 0 or 1.`);
      if (units.get(key) === 'units' && !Number.isInteger(value)) throw httpError(400, `"${key}" must be a whole number.`);
      await client.query(
        'UPDATE policies SET value = $1, updated_by = $2, updated_at = NOW() WHERE key = $3',
        [value, req.user.userId, key]
      );
    }
  });

  res.json({ success: true, message: 'Policies updated. New values apply to the next action.', data: await listPolicies() });
});

// ──────────────────────────────────────
// Riders + finance
// ──────────────────────────────────────

/** GET /api/admin/riders */
const getRiders = asyncHandler(async (req, res) => {
  const r = await pool.query(
    `SELECT u.id, u.full_name, u.email, u.phone, u.wallet_balance, u.created_at,
            r.vehicle_type, r.is_online, r.last_location_at,
            COUNT(o.id) FILTER (WHERE o.status = 'delivered') AS deliveries,
            COALESCE(SUM(o.rider_payout) FILTER (WHERE o.status = 'delivered'), 0) AS earnings,
            MAX(o.id) FILTER (WHERE o.status IN ('ready_for_pickup', 'picked', 'on_the_way')) AS active_order_id
     FROM users u
     JOIN riders r ON r.user_id = u.id
     LEFT JOIN orders o ON o.rider_user_id = u.id
     GROUP BY u.id, r.id
     ORDER BY r.is_online DESC, u.created_at DESC`
  );
  res.json({
    success: true,
    data: r.rows.map((x) => ({
      id: x.id,
      fullName: x.full_name,
      email: x.email,
      phone: x.phone,
      vehicleType: x.vehicle_type,
      isOnline: x.is_online,
      lastLocationAt: x.last_location_at,
      deliveries: Number(x.deliveries),
      earnings: Number(x.earnings),
      walletBalance: Number(x.wallet_balance),
      activeOrderId: x.active_order_id,
      createdAt: x.created_at,
    })),
  });
});

/** GET /api/admin/finance — escrow pool, platform revenue, recent entries */
const getFinance = asyncHandler(async (req, res) => {
  const [held, revenue, payouts, recent] = await Promise.all([
    pool.query(`SELECT escrow_status, COUNT(*) AS orders, COALESCE(SUM(total_amount - rider_payout), 0) AS amount
                FROM orders WHERE escrow_status IN ('held', 'disputed') GROUP BY escrow_status`),
    pool.query(`SELECT entry_type, COALESCE(SUM(amount), 0) AS amount FROM platform_ledger GROUP BY entry_type`),
    pool.query(`SELECT COALESCE(SUM(rider_payout), 0) AS amount FROM orders`),
    pool.query(`SELECT pl.*, v.store_name FROM platform_ledger pl
                JOIN orders o ON o.id = pl.order_id JOIN vendors v ON v.id = o.vendor_id
                ORDER BY pl.created_at DESC, pl.id DESC LIMIT 30`),
  ]);
  const byStatus = Object.fromEntries(held.rows.map((r) => [r.escrow_status, { orders: Number(r.orders), amount: Number(r.amount) }]));
  const byType = Object.fromEntries(revenue.rows.map((r) => [r.entry_type, Number(r.amount)]));

  res.json({
    success: true,
    data: {
      escrowPool: await getEscrowPoolBalanceReadOnly(),
      held: byStatus.held || { orders: 0, amount: 0 },
      disputed: byStatus.disputed || { orders: 0, amount: 0 },
      commission: byType.commission || 0,
      deliveryMargin: byType.delivery_margin || 0,
      platformRevenue: (byType.commission || 0) + (byType.delivery_margin || 0),
      riderPayouts: Number(payouts.rows[0].amount),
      recent: recent.rows.map((e) => ({
        id: e.id,
        orderId: e.order_id,
        storeName: e.store_name,
        type: e.entry_type,
        amount: Number(e.amount),
        createdAt: e.created_at,
      })),
    },
  });
});

// ──────────────────────────────────────
// Orders + users
// ──────────────────────────────────────

/** GET /api/admin/orders */
const getAllOrders = asyncHandler(async (req, res) => {
  const r = await pool.query(
    `SELECT o.id, o.status, o.escrow_status, o.delivery_type, o.total_amount, o.rider_payout, o.created_at, o.updated_at,
            u.full_name AS customer_name, u.email AS customer_email, v.store_name, rd.full_name AS rider_name,
            (SELECT COUNT(*) FROM order_items oi WHERE oi.order_id = o.id) AS item_count
     FROM orders o
     JOIN users u ON u.id = o.customer_id
     JOIN vendors v ON v.id = o.vendor_id
     LEFT JOIN users rd ON rd.id = o.rider_user_id
     ORDER BY o.created_at DESC`
  );
  res.json({
    success: true,
    data: r.rows.map((o) => ({
      id: o.id,
      customerName: o.customer_name,
      customerEmail: o.customer_email,
      storeName: o.store_name,
      riderName: o.rider_name,
      status: o.status,
      escrowStatus: o.escrow_status,
      deliveryType: o.delivery_type,
      totalAmount: Number(o.total_amount),
      riderPayout: Number(o.rider_payout),
      itemCount: Number(o.item_count),
      createdAt: o.created_at,
      updatedAt: o.updated_at,
    })),
  });
});

/** GET /api/admin/users */
const getAllUsers = asyncHandler(async (req, res) => {
  const r = await pool.query(
    `SELECT u.id, u.full_name, u.email, u.phone, u.role, u.created_at, v.store_name, v.is_approved
     FROM users u LEFT JOIN vendors v ON u.vendor_id = v.id
     ORDER BY u.created_at DESC`
  );
  res.json({
    success: true,
    data: r.rows.map((u) => ({
      id: u.id,
      fullName: u.full_name,
      email: u.email,
      phone: u.phone,
      role: u.role,
      storeName: u.store_name || null,
      isApproved: u.is_approved,
      createdAt: u.created_at,
    })),
  });
});

/**
 * PUT /api/admin/users/:id/reset-password
 * Sets a random temporary password (returned once, for the admin to pass on).
 * The user must change it after signing in. Admin accounts can't be reset here.
 */
const resetUserPassword = asyncHandler(async (req, res) => {
  const userId = intParam(req.params.id);
  // No look-alike characters (0/O, 1/l/I) so it can be read out over the phone
  const alphabet = 'abcdefghjkmnpqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  const temp = Array.from(crypto.randomBytes(10), (b) => alphabet[b % alphabet.length]).join('');
  const hash = await bcrypt.hash(temp, SALT_ROUNDS);

  const r = await pool.query(
    `UPDATE users SET password_hash = $1, must_change_password = true, password_changed_at = NOW()
     WHERE id = $2 AND role <> 'admin' RETURNING id, full_name, email`,
    [hash, userId]
  );
  if (r.rows.length === 0) throw httpError(404, 'User not found (admin passwords cannot be reset here).');
  res.json({
    success: true,
    message: `Temporary password set for ${r.rows[0].full_name}. They must change it after signing in.`,
    data: { userId, email: r.rows[0].email, temporaryPassword: temp },
  });
});

module.exports = {
  resetUserPassword,
  getDashboardStats,
  getAllVendors,
  approveVendor,
  disapproveVendor,
  getProducts,
  approveProduct,
  hideProduct,
  getPolicies,
  updatePolicies,
  getRiders,
  getFinance,
  getAllOrders,
  getAllUsers,
};
