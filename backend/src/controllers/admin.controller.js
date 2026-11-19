// ══════════════════════════════════════════════════════════════
// Vendra Backend - Admin Controller
// Stats, vendor + product approval, policies, riders, finance, users, orders
// ══════════════════════════════════════════════════════════════

const crypto = require('crypto');
const bcrypt = require('bcrypt');
const pool = require('../db');
const { SALT_ROUNDS } = require('./auth.controller');
const { getEscrowPoolBalanceReadOnly } = require('../services/escrowPool.service');
const { listPolicies, getPolicies: readPolicies } = require('../services/policy.service');
const { notify } = require('../services/notification.service');
const { broadcast, connectedClients } = require('../realtime');
const { sweepStatus } = require('../services/sweepStatus');
const { httpError, asyncHandler, withTransaction, intParam, paging, pageOf } = require('../utils/http');
const { releaseDueEscrows } = require('../services/orderSettlement.service');
const { listMessages } = require('./chat.controller');
const { haversineKm, metersBetween } = require('../utils/geo');
const { toPaisa, percentOf, paisaToNumber } = require('../utils/money');
const { trustCountSql } = require('../services/trust.service');
const { recordAudit, AUDIT_ACTIONS } = require('../services/audit.service');

/**
 * Platform GMV by channel (SRDS §2.1): walk-in POS sales carry no platform fee, online
 * orders pay commission when their escrow is released. Online GMV counts the item
 * subtotal (delivery fees aside) of orders that weren't cancelled.
 * @param days how far back the daily series goes
 */
async function channelBreakdown(days = 14) {
  const [totals, series, commission] = await Promise.all([
    pool.query(
      `SELECT
         (SELECT COALESCE(SUM(total_amount), 0) FROM pos_sales) AS pos_gmv,
         (SELECT COUNT(*) FROM pos_sales) AS pos_count,
         (SELECT COALESCE(SUM(total_amount), 0) FROM pos_sales WHERE created_at::date = CURRENT_DATE) AS pos_today,
         (SELECT COALESCE(SUM(COALESCE(subtotal, total_amount)), 0) FROM orders WHERE status <> 'cancelled') AS online_gmv,
         (SELECT COUNT(*) FROM orders WHERE status <> 'cancelled') AS online_count,
         (SELECT COALESCE(SUM(COALESCE(subtotal, total_amount)), 0) FROM orders
           WHERE status <> 'cancelled' AND created_at::date = CURRENT_DATE) AS online_today`
    ),
    pool.query(
      `SELECT to_char(d, 'YYYY-MM-DD') AS day,
              (SELECT COALESCE(SUM(total_amount), 0) FROM pos_sales WHERE created_at::date = d::date) AS walk_in,
              (SELECT COALESCE(SUM(COALESCE(subtotal, total_amount)), 0) FROM orders
                WHERE status <> 'cancelled' AND created_at::date = d::date) AS online
       FROM generate_series(CURRENT_DATE - ($1::int - 1), CURRENT_DATE, INTERVAL '1 day') AS d
       ORDER BY d`,
      [days]
    ),
    pool.query(`SELECT COALESCE(SUM(amount), 0) AS amount FROM platform_ledger WHERE entry_type = 'commission'`),
  ]);
  const t = totals.rows[0];
  const walkIn = Number(t.pos_gmv);
  const online = Number(t.online_gmv);
  return {
    totalGmv: walkIn + online,
    walkIn: { gmv: walkIn, sales: Number(t.pos_count), today: Number(t.pos_today), commission: 0 },
    online: { gmv: online, orders: Number(t.online_count), today: Number(t.online_today), commission: Number(commission.rows[0].amount) },
    series: series.rows.map((r) => ({
      day: r.day,
      walkIn: Number(r.walk_in),
      online: Number(r.online),
    })),
  };
}

/** GET /api/admin/stats */
const getDashboardStats = asyncHandler(async (req, res) => {
  const [vendors, users, orders, products, disputes] = await Promise.all([
    pool.query(`SELECT COUNT(*) FILTER (WHERE is_approved) AS approved,
                       COUNT(*) FILTER (WHERE NOT is_approved) AS pending,
                       COUNT(*) FILTER (WHERE location_requested_at IS NOT NULL) AS location_requests,
                       COUNT(*) AS total FROM vendors`),
    pool.query(`SELECT COUNT(*) FILTER (WHERE u.role = 'customer') AS customers,
                       COUNT(*) FILTER (WHERE u.role = 'rider') AS riders,
                       COUNT(*) FILTER (WHERE r.is_online) AS riders_online,
                       COUNT(*) FILTER (WHERE r.approval_status = 'pending') AS riders_pending
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
  const [platform, recentDisputes, health] = await Promise.all([
    pool.query('SELECT COALESCE(SUM(amount), 0) AS total FROM platform_ledger'),
    pool.query(
      `SELECT d.id, d.order_id, d.issue_type, d.status, d.raised_by_role, d.created_at, v.store_name,
              (o.total_amount - o.rider_payout) AS held_amount
       FROM disputes d JOIN orders o ON o.id = d.order_id JOIN vendors v ON v.id = o.vendor_id
       ORDER BY (d.status = 'open') DESC, d.created_at DESC LIMIT 5`
    ),
    platformHealth(),
  ]);

  res.json({
    success: true,
    data: {
      vendors: vendors.rows[0],
      customers: Number(users.rows[0].customers),
      riders: Number(users.rows[0].riders),
      ridersOnline: Number(users.rows[0].riders_online),
      pendingRiders: Number(users.rows[0].riders_pending),
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
      channels: await channelBreakdown(),
      recentDisputes: recentDisputes.rows.map((d) => ({
        id: d.id,
        orderId: d.order_id,
        issueType: d.issue_type,
        status: d.status,
        raisedByRole: d.raised_by_role,
        storeName: d.store_name,
        heldAmount: Number(d.held_amount),
        createdAt: d.created_at,
      })),
      health,
    },
  });
});

/**
 * Platform health for the dashboard (SRDS Fig 2.9, §4.3.2 health checks):
 *   database  round-trip time of a trivial query
 *   escrow    the pool must equal what open orders still hold (SSR 02); any gap is a bug
 *   sweep     when the background jobs (escrow release, timeouts, gateway catch-up) last ran
 *   realtime  sockets connected right now
 */
async function platformHealth() {
  const started = process.hrtime.bigint();
  await pool.query('SELECT 1');
  const dbMs = Number(process.hrtime.bigint() - started) / 1e6;

  const held = await pool.query(
    `SELECT COALESCE(SUM(total_amount - rider_payout), 0) AS amount, COUNT(*)::int AS orders
     FROM orders WHERE escrow_status IN ('held', 'disputed')`
  );
  const poolBalance = toPaisa(await getEscrowPoolBalanceReadOnly());
  const ordersHeld = toPaisa(held.rows[0].amount);

  return {
    database: { ok: true, latencyMs: Math.round(dbMs * 10) / 10 },
    escrow: {
      balanced: poolBalance === ordersHeld,
      pool: paisaToNumber(poolBalance),
      heldByOrders: paisaToNumber(ordersHeld),
      orders: held.rows[0].orders,
    },
    sweep: sweepStatus(),
    realtime: { connections: connectedClients() },
  };
}

// ──────────────────────────────────────
// Vendors
// ──────────────────────────────────────

/** GET /api/admin/vendors */
const getAllVendors = asyncHandler(async (req, res) => {
  const r = await pool.query(
    `SELECT v.id, v.store_name, v.store_address, v.cnic, v.is_approved, v.created_at, v.latitude, v.longitude,
            v.pending_latitude, v.pending_longitude, v.pending_address, v.location_requested_at,
            u.id AS user_id, u.full_name, u.email, u.phone,
            (SELECT COUNT(*) FROM products p WHERE p.vendor_id = v.id AND p.is_active) AS product_count,
            (SELECT COALESCE(SUM(o.total_amount), 0) FROM orders o WHERE o.vendor_id = v.id AND o.status <> 'cancelled') AS total_revenue,
            ${trustCountSql('walk_in_override', 'vendor_id', 'v.id')} AS walk_in_overrides,
            (SELECT COUNT(*)::int FROM trust_events te JOIN orders o ON o.id = te.order_id
              WHERE te.kind = 'handover_lockout' AND te.vendor_id = v.id AND o.delivery_type = 'self_pickup'
                AND te.created_at >= NOW() - INTERVAL '30 days') AS counter_lockouts
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
      latitude: v.latitude,
      longitude: v.longitude,
      pendingLocation: v.location_requested_at
        ? {
            latitude: v.pending_latitude,
            longitude: v.pending_longitude,
            address: v.pending_address,
            requestedAt: v.location_requested_at,
            movedKm: v.latitude != null
              ? Number(haversineKm(v.latitude, v.longitude, v.pending_latitude, v.pending_longitude).toFixed(2))
              : null,
          }
        : null,
      ownerName: v.full_name,
      email: v.email,
      phone: v.phone,
      productCount: Number(v.product_count),
      totalRevenue: Number(v.total_revenue),
      // Anti-abuse signals over the last 30 days
      trust: { walkInOverrides: v.walk_in_overrides, counterLockouts: v.counter_lockouts },
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
      await recordAudit(client, req, {
        action: approved ? 'vendor_approved' : 'vendor_disapproved',
        targetType: 'vendor',
        targetId: vendorId,
        summary: `${approved ? 'Approved' : 'Disapproved'} store "${r.rows[0].store_name}"`,
      });
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

/**
 * PUT /api/admin/vendors/:id/location/approve — the store moves to the requested point
 * PUT /api/admin/vendors/:id/location/reject  Body: { reason } — the store stays put
 */
function reviewLocation(approve) {
  return asyncHandler(async (req, res) => {
    const vendorId = intParam(req.params.id);
    const reason = typeof req.body?.reason === 'string' ? req.body.reason.trim().slice(0, 300) : '';
    if (!approve && !reason) throw httpError(400, 'Give the vendor a reason for rejecting the new location.');
    const vendor = await withTransaction(async (client, afterCommit) => {
      const v = (await client.query('SELECT * FROM vendors WHERE id = $1 FOR UPDATE', [vendorId])).rows[0];
      if (!v) throw httpError(404, 'Vendor not found.');
      if (!v.location_requested_at) throw httpError(409, 'This store has no location change waiting for review.');
      const r = await client.query(
        approve
          ? `UPDATE vendors SET latitude = pending_latitude, longitude = pending_longitude,
                    store_address = COALESCE(pending_address, store_address),
                    pending_latitude = NULL, pending_longitude = NULL, pending_address = NULL,
                    location_requested_at = NULL, location_rejection_reason = NULL
             WHERE id = $1 RETURNING *`
          : `UPDATE vendors SET pending_latitude = NULL, pending_longitude = NULL, pending_address = NULL,
                    location_requested_at = NULL, location_rejection_reason = $2
             WHERE id = $1 RETURNING *`,
        approve ? [vendorId] : [vendorId, reason]
      );
      await notify(client, afterCommit, v.user_id, approve
        ? { type: 'location_approved', title: 'New store location approved', body: 'Customers and riders now see your store at its new location.' }
        : { type: 'location_rejected', title: 'Store location change rejected', body: reason });
      afterCommit.push(() => broadcast('catalog:update', { vendorId }));
      await recordAudit(client, req, {
        action: approve ? 'location_approved' : 'location_rejected',
        targetType: 'vendor',
        targetId: vendorId,
        summary: approve
          ? `Moved "${v.store_name}" to its requested location`
          : `Rejected the location change for "${v.store_name}"`,
        details: {
          from: { lat: Number(v.latitude), lng: Number(v.longitude) },
          requested: { lat: Number(v.pending_latitude), lng: Number(v.pending_longitude) },
          ...(approve ? {} : { reason }),
        },
      });
      return r.rows[0];
    });
    res.json({
      success: true,
      message: approve ? `"${vendor.store_name}" moved to its new location.` : `Location change for "${vendor.store_name}" rejected.`,
      data: { id: vendor.id, latitude: vendor.latitude, longitude: vendor.longitude, storeAddress: vendor.store_address },
    });
  });
}

const approveVendorLocation = reviewLocation(true);
const rejectVendorLocation = reviewLocation(false);

// ──────────────────────────────────────
// Product catalog approval (FR06)
// ──────────────────────────────────────

/** GET /api/admin/products?status=pending|approved|all */
const getProducts = asyncHandler(async (req, res) => {
  const status = req.query.status || 'pending';
  const filter = status === 'pending' ? 'AND NOT p.is_approved' : status === 'approved' ? 'AND p.is_approved' : '';
  const r = await pool.query(
    `SELECT p.id, p.name, p.description, p.price, p.private_stock, p.public_stock, p.buffer, p.reserved_quantity,
            p.barcode, p.weight_grams, p.image_url, p.is_approved, p.created_at, v.id AS vendor_id, v.store_name, c.name AS category_name
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
      weightGrams: p.weight_grams,
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
      await recordAudit(client, req, {
        action: approved ? 'product_approved' : 'product_hidden',
        targetType: 'product',
        targetId: p.id,
        summary: `${approved ? 'Approved' : 'Hid'} product "${p.name}"`,
      });
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

  await withTransaction(async (client, afterCommit) => {
    const known = await client.query('SELECT key, unit, label, value FROM policies');
    const units = new Map(known.rows.map((r) => [r.key, r.unit]));
    const current = new Map(known.rows.map((r) => [r.key, r]));
    const changes = [];

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
      const before = Number(current.get(key).value);
      if (before !== value) changes.push({ key, label: current.get(key).label, from: before, to: value, unit: units.get(key) });
    }
    if (changes.length > 0) {
      await recordAudit(client, req, {
        action: 'policy_changed',
        targetType: 'policy',
        summary: changes.map((c) => `${c.label}: ${c.from} → ${c.to}${c.unit && c.unit !== '0/1' ? ` ${c.unit}` : ''}`).join('; '),
        details: { changes },
      });
    }
    // Every app re-reads GET /api/public-config when it hears this
    afterCommit.push(() => broadcast('config:update', { keys: Object.keys(values) }));
  });

  res.json({ success: true, message: 'Policies updated. New values apply to the next action.', data: await listPolicies() });
});

// ──────────────────────────────────────
// Riders + finance
// ──────────────────────────────────────

/** GET /api/admin/riders?status=pending|approved|rejected — waiting riders first */
const getRiders = asyncHandler(async (req, res) => {
  const status = ['pending', 'approved', 'rejected'].includes(req.query.status) ? req.query.status : null;
  const r = await pool.query(
    `SELECT u.id, u.full_name, u.email, u.phone, u.wallet_balance, u.created_at,
            r.vehicle_type, r.is_online, r.last_location_at,
            r.cnic, r.license_number, r.vehicle_number, r.approval_status, r.rejection_reason, r.reviewed_at,
            COUNT(o.id) FILTER (WHERE o.status = 'delivered') AS deliveries,
            COALESCE(SUM(o.rider_payout) FILTER (WHERE o.status = 'delivered'), 0) AS earnings,
            ROUND(AVG(o.rider_rating), 1)::float8 AS average_rating,
            MAX(o.id) FILTER (WHERE o.status IN ('ready_for_pickup', 'picked', 'on_the_way')) AS active_order_id,
            ${trustCountSql('rider_task_timeout', 'user_id', 'u.id')} AS task_timeouts,
            ${trustCountSql('handover_lockout', 'user_id', 'u.id')} AS handover_lockouts
     FROM users u
     JOIN riders r ON r.user_id = u.id
     LEFT JOIN orders o ON o.rider_user_id = u.id
     WHERE ($1::text IS NULL OR r.approval_status = $1)
     GROUP BY u.id, r.id
     ORDER BY (r.approval_status = 'pending') DESC, r.is_online DESC, u.created_at DESC`,
    [status]
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
      cnic: x.cnic,
      licenseNumber: x.license_number,
      vehicleNumber: x.vehicle_number,
      approvalStatus: x.approval_status,
      rejectionReason: x.rejection_reason,
      reviewedAt: x.reviewed_at,
      averageRating: x.average_rating,
      deliveries: Number(x.deliveries),
      earnings: Number(x.earnings),
      walletBalance: Number(x.wallet_balance),
      activeOrderId: x.active_order_id,
      // Anti-abuse signals over the last 30 days
      trust: { taskTimeouts: x.task_timeouts, handoverLockouts: x.handover_lockouts },
      createdAt: x.created_at,
    })),
  });
});

/**
 * PUT /api/admin/riders/:id/approve — the rider can go online
 * PUT /api/admin/riders/:id/reject  Body: { reason } — the rider fixes their documents and resubmits
 * (:id is the rider's user id, as listed by GET /api/admin/riders)
 */
function reviewRider(approve) {
  return asyncHandler(async (req, res) => {
    const userId = intParam(req.params.id);
    const reason = typeof req.body?.reason === 'string' ? req.body.reason.trim().slice(0, 300) : '';
    if (!approve && !reason) throw httpError(400, 'Tell the rider what to fix (reason).');

    const rider = await withTransaction(async (client, afterCommit) => {
      const current = (await client.query('SELECT * FROM riders WHERE user_id = $1 FOR UPDATE', [userId])).rows[0];
      if (!current) throw httpError(404, 'Rider not found.');
      if (approve && !current.cnic) throw httpError(409, 'This rider has not sent their CNIC yet.');
      if (!approve) {
        const active = await client.query(
          `SELECT 1 FROM orders WHERE rider_user_id = $1 AND status IN ('ready_for_pickup', 'picked', 'on_the_way')`, [userId]);
        if (active.rows.length) throw httpError(409, 'This rider is on a delivery. Reject them after it is finished.');
      }
      const r = await client.query(
        `UPDATE riders SET approval_status = $1::varchar, rejection_reason = $2, reviewed_at = NOW(),
                is_online = CASE WHEN $1::varchar = 'approved' THEN is_online ELSE false END
         WHERE user_id = $3 RETURNING *`,
        [approve ? 'approved' : 'rejected', approve ? null : reason, userId]
      );
      await notify(client, afterCommit, userId, approve
        ? { type: 'rider_approved', title: 'You are approved to deliver', body: 'Go online to start receiving delivery tasks.' }
        : { type: 'rider_rejected', title: 'Your rider documents need changes', body: reason });
      const name = (await client.query('SELECT full_name FROM users WHERE id = $1', [userId])).rows[0]?.full_name;
      await recordAudit(client, req, {
        action: approve ? 'rider_approved' : 'rider_rejected',
        targetType: 'rider',
        targetId: userId,
        summary: approve ? `Approved rider ${name}` : `Rejected rider ${name}'s documents`,
        details: approve ? null : { reason },
      });
      return r.rows[0];
    });
    res.json({
      success: true,
      message: approve ? 'Rider approved.' : 'Rider rejected. They have been told what to fix.',
      data: { id: userId, approvalStatus: rider.approval_status, rejectionReason: rider.rejection_reason },
    });
  });
}

const approveRider = reviewRider(true);
const rejectRider = reviewRider(false);

const ACTIVE_DELIVERY = ['ready_for_pickup', 'picked', 'on_the_way'];

/** Lifecycle column of a delivery order on the dispatch board */
function dispatchStage(o) {
  if (o.status === 'ready_for_pickup') return o.rider_user_id ? 'assigned' : 'ready_for_pickup';
  return o.status; // picked | on_the_way | delivered
}

/**
 * GET /api/admin/fleet — live fleet + dispatch board (SRDS §1.3, §2.5.3)
 *   riders      online / engaged on a delivery / idle (and whether an idle rider is within
 *               the task radius of a store, i.e. can be dispatched right now)
 *   deliveries  every delivery in flight plus today's completed ones, with the store
 *               waiting time; waits beyond rider_free_wait_min are flagged (slow stores)
 *   slowStores  stores whose average wait over the last 30 days exceeds the free allowance
 */
const getFleet = asyncHandler(async (req, res) => {
  const policies = await readPolicies();
  const freeWait = Number(policies.rider_free_wait_min);
  const [ridersRes, storesRes, ordersRes, slowRes] = await Promise.all([
    pool.query(
      `SELECT u.id, u.full_name, u.phone, r.vehicle_type, r.is_online, r.current_lat, r.current_lng, r.last_location_at,
              (SELECT o.id FROM orders o WHERE o.rider_user_id = u.id AND o.status = ANY($1::order_status[])
                ORDER BY o.assigned_at DESC LIMIT 1) AS active_order_id
       FROM users u JOIN riders r ON r.user_id = u.id
       WHERE r.approval_status = 'approved'
       ORDER BY r.is_online DESC, u.full_name`,
      [ACTIVE_DELIVERY]
    ),
    pool.query(
      `SELECT v.id, v.store_name, v.latitude, v.longitude,
              (SELECT COUNT(*)::int FROM orders o WHERE o.vendor_id = v.id AND o.status = 'ready_for_pickup'
                 AND o.delivery_type = 'delivery' AND o.rider_user_id IS NULL) AS waiting_for_rider
       FROM vendors v WHERE v.is_approved AND v.latitude IS NOT NULL`
    ),
    pool.query(
      `SELECT o.id, o.status, o.rider_user_id, o.ready_at, o.assigned_at, o.rider_arrived_at, o.picked_at, o.delivered_at,
              o.wait_minutes, o.total_amount, v.store_name, cu.full_name AS customer_name, ru.full_name AS rider_name,
              v.latitude AS store_lat, v.longitude AS store_lng, o.customer_lat, o.customer_lng
       FROM orders o
       JOIN vendors v ON v.id = o.vendor_id
       JOIN users cu ON cu.id = o.customer_id
       LEFT JOIN users ru ON ru.id = o.rider_user_id
       WHERE o.delivery_type = 'delivery'
         AND (o.status = ANY($1::order_status[]) OR (o.status = 'delivered' AND o.delivered_at::date = CURRENT_DATE))
       ORDER BY COALESCE(o.ready_at, o.created_at)`,
      [ACTIVE_DELIVERY]
    ),
    pool.query(
      `SELECT v.id, v.store_name, ROUND(AVG(o.wait_minutes), 1)::float8 AS avg_wait, COUNT(*) AS deliveries,
              COUNT(*) FILTER (WHERE o.wait_minutes > $1) AS slow_deliveries
       FROM orders o JOIN vendors v ON v.id = o.vendor_id
       WHERE o.status = 'delivered' AND o.wait_minutes IS NOT NULL AND o.delivered_at >= NOW() - INTERVAL '30 days'
       GROUP BY v.id HAVING AVG(o.wait_minutes) > $1
       ORDER BY avg_wait DESC LIMIT 10`,
      [freeWait]
    ),
  ]);

  const stores = storesRes.rows;
  const nearAStore = (lat, lng) => lat != null && stores.some((s) =>
    haversineKm(lat, lng, s.latitude, s.longitude) <= Number(policies.task_radius_km));

  const riders = ridersRes.rows.map((r) => {
    const state = r.active_order_id ? 'engaged' : (r.is_online ? 'idle' : 'offline');
    return {
      id: r.id,
      name: r.full_name,
      phone: r.phone,
      vehicleType: r.vehicle_type,
      isOnline: r.is_online,
      state,
      activeOrderId: r.active_order_id,
      lastLocationAt: r.last_location_at,
      // Live map: only riders who are online have a position worth showing
      lat: r.is_online && r.current_lat != null ? Number(r.current_lat) : null,
      lng: r.is_online && r.current_lng != null ? Number(r.current_lng) : null,
      withinTaskRadius: state === 'idle' ? nearAStore(r.current_lat, r.current_lng) : null,
    };
  });

  const now = Date.now();
  const deliveries = ordersRes.rows.map((o) => {
    let waitMinutes = o.wait_minutes != null ? Number(o.wait_minutes) : null;
    if (waitMinutes == null && o.rider_arrived_at) {
      waitMinutes = Math.max(0, ((o.picked_at ? new Date(o.picked_at).getTime() : now) - new Date(o.rider_arrived_at).getTime()) / 60000);
    }
    return {
      id: o.id,
      stage: dispatchStage(o),
      storeName: o.store_name,
      customerName: o.customer_name,
      riderName: o.rider_name,
      totalAmount: Number(o.total_amount),
      readyAt: o.ready_at,
      assignedAt: o.assigned_at,
      arrivedAt: o.rider_arrived_at,
      pickedAt: o.picked_at,
      deliveredAt: o.delivered_at,
      waitMinutes: waitMinutes == null ? null : Math.round(waitMinutes * 10) / 10,
      // Rider is (or was) kept waiting at the store beyond the free allowance
      waitExceeded: waitMinutes != null && waitMinutes > freeWait,
      waitingNow: Boolean(o.rider_arrived_at && !o.picked_at),
      riderId: o.rider_user_id,
      store: o.store_lat != null ? { lat: Number(o.store_lat), lng: Number(o.store_lng) } : null,
      customer: o.customer_lat != null ? { lat: Number(o.customer_lat), lng: Number(o.customer_lng) } : null,
    };
  });

  res.json({
    success: true,
    data: {
      counts: {
        online: riders.filter((r) => r.isOnline).length,
        engaged: riders.filter((r) => r.state === 'engaged').length,
        idle: riders.filter((r) => r.state === 'idle').length,
        idleWithinRadius: riders.filter((r) => r.state === 'idle' && r.withinTaskRadius).length,
        offline: riders.filter((r) => r.state === 'offline').length,
      },
      riders,
      deliveries,
      stores: stores.map((s) => ({
        id: s.id,
        name: s.store_name,
        lat: Number(s.latitude),
        lng: Number(s.longitude),
        waitingForRider: s.waiting_for_rider,
      })),
      slowStores: slowRes.rows.map((s) => ({
        vendorId: s.id,
        storeName: s.store_name,
        averageWaitMinutes: s.avg_wait,
        deliveries: Number(s.deliveries),
        slowDeliveries: Number(s.slow_deliveries),
      })),
      freeWaitMinutes: freeWait,
      taskRadiusKm: Number(policies.task_radius_km),
    },
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
      channels: await channelBreakdown(30),
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
            o.payment_method, o.cancellation_reason,
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
      paymentMethod: o.payment_method,
      cancellationReason: o.cancellation_reason,
      itemCount: Number(o.item_count),
      createdAt: o.created_at,
      updatedAt: o.updated_at,
    })),
  });
});

/**
 * GET /api/admin/orders/:id — one order in full for the inspection drawer: the three
 * parties, the basket, the handover evidence (code, attempts, where the rider stood
 * against the customer's pin) and how the money splits. Settled orders show the
 * platform ledger; open ones an estimate at the current commission rate.
 */
const getOrderDetails = asyncHandler(async (req, res) => {
  const id = intParam(req.params.id, 'Order id');
  const [orderRes, itemsRes, ledgerRes, policies, messages] = await Promise.all([
    pool.query(
      `SELECT o.*,
              u.full_name AS customer_name, u.email AS customer_email, u.phone AS customer_phone,
              v.store_name, v.store_address,
              rd.full_name AS rider_name, rd.phone AS rider_phone
       FROM orders o
       JOIN users u ON u.id = o.customer_id
       JOIN vendors v ON v.id = o.vendor_id
       LEFT JOIN users rd ON rd.id = o.rider_user_id
       WHERE o.id = $1`,
      [id]
    ),
    pool.query(
      `SELECT oi.*, p.name AS product_name, p.image_url, p.barcode
       FROM order_items oi
       JOIN products p ON p.id = oi.product_id
       WHERE oi.order_id = $1
       ORDER BY oi.id`,
      [id]
    ),
    // What the platform kept, and what the store and customer actually received
    pool.query(
      `SELECT entry_type, SUM(amount) AS amount FROM platform_ledger WHERE order_id = $1 GROUP BY entry_type
       UNION ALL
       SELECT transaction_type, SUM(amount) FROM wallet_ledger
       WHERE order_id = $1 AND transaction_type IN ('escrow_release', 'escrow_refund') GROUP BY transaction_type`,
      [id]
    ),
    readPolicies(),
    listMessages(id),
  ]);
  if (orderRes.rows.length === 0) throw httpError(404, 'Order not found');
  const o = orderRes.rows[0];
  const num = (v) => (v == null ? null : Number(v));

  // Settlement: the ledgers once escrow is released, otherwise what it would be today
  const ledger = Object.fromEntries(ledgerRes.rows.map((r) => [r.entry_type, toPaisa(r.amount)]));
  const settled = o.escrow_status === 'released';
  const subtotalPaisa = toPaisa(o.subtotal ?? o.total_amount);
  const commissionPaisa = settled ? (ledger.commission || 0) : percentOf(subtotalPaisa, policies.commission_pct);
  const storeNetPaisa = settled ? (ledger.escrow_release || 0) : subtotalPaisa - commissionPaisa;

  res.json({
    success: true,
    data: {
      id: o.id,
      customerName: o.customer_name,
      customerEmail: o.customer_email,
      customerPhone: o.customer_phone,
      storeName: o.store_name,
      storeAddress: o.store_address,
      riderName: o.rider_name,
      riderPhone: o.rider_phone,
      status: o.status,
      escrowStatus: o.escrow_status,
      escrowReleaseDueAt: o.escrow_release_due_at,
      deliveryType: o.delivery_type,
      deliveryAddress: o.delivery_address,
      deliveryNote: o.delivery_note || null,
      customerLat: num(o.customer_lat),
      customerLng: num(o.customer_lng),
      distanceKm: num(o.distance_km),
      subtotal: Number(o.subtotal ?? o.total_amount),
      deliveryFee: Number(o.delivery_fee || 0),
      totalAmount: Number(o.total_amount),
      riderPayout: Number(o.rider_payout || 0),
      paymentMethod: o.payment_method,
      cancellationReason: o.cancellation_reason,
      // state: estimate (still in escrow) | released | refunded (nothing paid out)
      settlement: o.escrow_status === 'refunded'
        ? {
          state: 'refunded',
          refunded: paisaToNumber(ledger.escrow_refund || 0),
          storeFee: paisaToNumber(ledger.escrow_release || 0), // late cancellation fee, if any
        }
        : {
          state: settled ? 'released' : 'estimate',
          commissionPct: Number(policies.commission_pct),
          commission: paisaToNumber(commissionPaisa),
          storeNet: paisaToNumber(storeNetPaisa),
          customerRefund: paisaToNumber(settled ? ledger.escrow_refund || 0 : 0),
          deliveryMargin: settled ? paisaToNumber(ledger.delivery_margin || 0) : null,
        },
      handover: {
        codeVerifiedAt: o.otp_verified_at,
        failedAttempts: o.otp_failed_attempts || 0,
        lockedUntil: o.otp_locked_until && new Date(o.otp_locked_until) > new Date() ? o.otp_locked_until : null,
        riderLat: num(o.delivery_lat),
        riderLng: num(o.delivery_lng),
        distanceFromPinMeters: metersBetween(o.delivery_lat, o.delivery_lng, o.customer_lat, o.customer_lng),
        geofenceMeters: Number(policies.geofence_m),
      },
      createdAt: o.created_at,
      assignedAt: o.assigned_at,
      readyAt: o.ready_at,
      arrivedAt: o.rider_arrived_at,
      pickedAt: o.picked_at,
      deliveredAt: o.delivered_at,
      items: itemsRes.rows.map((i) => ({
        id: i.id,
        productId: i.product_id,
        name: i.product_name,
        barcode: i.barcode,
        imageUrl: i.image_url,
        quantity: i.quantity,
        unitPrice: Number(i.unit_price),
        subtotal: Number(i.subtotal),
      })),
      // Customer ↔ rider chat, kept as evidence
      messages,
    },
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

  const user = await withTransaction(async (client) => {
    const r = await client.query(
      `UPDATE users SET password_hash = $1, must_change_password = true, password_changed_at = NOW()
       WHERE id = $2 AND role <> 'admin' RETURNING id, full_name, email, role`,
      [hash, userId]
    );
    if (r.rows.length === 0) throw httpError(404, 'User not found (admin passwords cannot be reset here).');
    // The temporary password itself is never logged
    await recordAudit(client, req, {
      action: 'password_reset',
      targetType: 'user',
      targetId: userId,
      summary: `Reset the password of ${r.rows[0].full_name} (${r.rows[0].role})`,
    });
    return r.rows[0];
  });
  res.json({
    success: true,
    message: `Temporary password set for ${user.full_name}. They must change it after signing in.`,
    data: { userId, email: user.email, temporaryPassword: temp },
  });
});

// ──────────────────────────────────────
// Audit trail + escrow settlement
// ──────────────────────────────────────

/** GET /api/admin/audit-log?action=&limit=&offset= — newest first */
const getAuditLog = asyncHandler(async (req, res) => {
  const page = paging(req.query, { defaultLimit: 30 });
  const action = AUDIT_ACTIONS.includes(req.query.action) ? req.query.action : null;
  const r = await pool.query(
    `SELECT a.*, u.full_name AS admin_name
     FROM admin_audit_log a LEFT JOIN users u ON u.id = a.admin_user_id
     WHERE ($1::text IS NULL OR a.action = $1)
     ORDER BY a.created_at DESC, a.id DESC LIMIT $2 OFFSET $3`,
    [action, page.limit + 1, page.offset]
  );
  const { items, meta } = pageOf(r.rows, page);
  res.json({
    success: true,
    data: items.map((a) => ({
      id: a.id,
      adminName: a.admin_name,
      action: a.action,
      targetType: a.target_type,
      targetId: a.target_id,
      summary: a.summary,
      details: a.details,
      ipAddress: a.ip_address,
      createdAt: a.created_at,
    })),
    meta: { ...meta, actions: AUDIT_ACTIONS },
  });
});

/**
 * GET /api/admin/settlement — what the escrow sweep will pay stores, and when.
 * Delivered orders release once their dispute window passes (open disputes never do);
 * the sweep runs every SWEEP_SECONDS.
 */
const getSettlement = asyncHandler(async (req, res) => {
  const r = await pool.query(
    `SELECT COUNT(*) FILTER (WHERE escrow_release_due_at <= NOW())::int AS due_orders,
            COALESCE(SUM(total_amount - rider_payout) FILTER (WHERE escrow_release_due_at <= NOW()), 0) AS due_amount,
            COUNT(*) FILTER (WHERE escrow_release_due_at <= NOW() + INTERVAL '24 hours')::int AS day_orders,
            COALESCE(SUM(total_amount - rider_payout) FILTER (WHERE escrow_release_due_at <= NOW() + INTERVAL '24 hours'), 0) AS day_amount,
            MIN(escrow_release_due_at) FILTER (WHERE escrow_release_due_at > NOW()) AS next_due_at
     FROM orders WHERE status = 'delivered' AND escrow_status = 'held'`
  );
  const x = r.rows[0];
  const sweep = sweepStatus();
  res.json({
    success: true,
    data: {
      dueNow: { orders: x.due_orders, amount: Number(x.due_amount) },
      next24h: { orders: x.day_orders, amount: Number(x.day_amount) },
      nextDueAt: x.next_due_at,
      sweep: {
        ...sweep,
        nextRunInSeconds: sweep.lastRunAt ? Math.max(0, sweep.intervalSeconds - sweep.secondsAgo) : null,
      },
    },
  });
});

/** POST /api/admin/settlement/run — release every escrow that is due now, without waiting for the sweep */
const runSettlement = asyncHandler(async (req, res) => {
  const released = await releaseDueEscrows();
  if (released > 0) {
    await recordAudit(pool, req, {
      action: 'escrow_settled',
      targetType: 'escrow',
      summary: `Released escrow for ${released} delivered order${released === 1 ? '' : 's'} by hand`,
      details: { released },
    });
  }
  res.json({
    success: true,
    message: released ? `Released escrow for ${released} order${released === 1 ? '' : 's'}.` : 'Nothing was due for release.',
    data: { released },
  });
});

module.exports = {
  resetUserPassword,
  getAuditLog,
  getSettlement,
  runSettlement,
  getDashboardStats,
  getAllVendors,
  approveVendor,
  disapproveVendor,
  approveVendorLocation,
  rejectVendorLocation,
  getProducts,
  approveProduct,
  hideProduct,
  getPolicies,
  updatePolicies,
  getRiders,
  approveRider,
  rejectRider,
  getFleet,
  getFinance,
  getAllOrders,
  getOrderDetails,
  getAllUsers,
};
