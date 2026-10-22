// ══════════════════════════════════════════════════════════════
// Vendra Backend - Customer Controller
// Product browsing, checkout from the wallet, orders, tracking
// ══════════════════════════════════════════════════════════════

const pool = require('../db');
const { releaseOrderLocks, consumeOrderLocks } = require('../services/inventory.service');
const { refundEscrow, scheduleEscrowRelease } = require('../services/orderSettlement.service');
const { announceOrder } = require('../services/notification.service');
const { getPolicies } = require('../services/policy.service');
const { httpError, asyncHandler, withTransaction, intParam, paging, pageOf, searchPattern } = require('../utils/http');
const { readCheckoutInput, quoteCheckout, placeOrder } = require('../services/checkout.service');
const { haversineKm, isValidCoordinate } = require('../utils/geo');
const { paisaToNumber } = require('../utils/money');
const { publicGatewayConfig } = require('../services/gateway.client');
const { TOPUP_MIN_RS, TOPUP_MAX_RS } = require('../services/payments.service');
const { APP_MODE, FEATURES } = require('../config/mode');
const { DEMO_ACCOUNTS } = require('../config/demoAccounts');

const num = (v) => (v == null ? null : Number(v));

function formatProduct(p) {
  return {
    id: p.id,
    vendorId: p.vendor_id,
    storeName: p.store_name,
    storeAddress: p.store_address,
    vendorLat: num(p.vendor_lat),
    vendorLng: num(p.vendor_lng),
    categoryId: p.category_id,
    categoryName: p.category_name || null,
    name: p.name,
    description: p.description,
    price: Number(p.price),
    publicStock: p.public_stock,
    barcode: p.barcode,
    imageUrl: p.image_url,
    createdAt: p.created_at,
  };
}

const PRODUCT_SELECT = `
  SELECT p.*, v.store_name, v.store_address, v.latitude AS vendor_lat, v.longitude AS vendor_lng,
         c.name AS category_name
  FROM products p
  JOIN vendors v ON p.vendor_id = v.id
  LEFT JOIN categories c ON c.id = p.category_id
  WHERE p.is_active = true AND p.is_approved = true AND p.public_stock > 0 AND v.is_approved = true`;

/**
 * GET /api/public-config — policy values apps show before an order exists
 */
const getPublicConfig = asyncHandler(async (req, res) => {
  const p = await getPolicies();
  // ?role=customer|vendor|rider|admin narrows the demo accounts to that app's role
  const role = typeof req.query.role === 'string' ? req.query.role : null;
  res.json({
    success: true,
    data: {
      mode: APP_MODE,
      features: FEATURES,
      deliveryFee: p.delivery_fee, // base; the fee for a cart comes from POST /api/customer/checkout/quote
      deliveryFeePerKm: p.delivery_fee_per_km,
      maxDeliveryKm: p.max_delivery_km, // 0 = no limit
      disputeWindowMinutes: p.dispute_window_min,
      geofenceMeters: p.geofence_m,
      taskRadiusKm: p.task_radius_km,
      defaultBuffer: p.default_buffer,
      vendorAcceptTimeoutMinutes: p.vendor_accept_timeout_min,
      riderAssignTimeoutMinutes: p.rider_assign_timeout_min,
      payments: {
        ...publicGatewayConfig(),
        minTopup: TOPUP_MIN_RS,
        maxTopup: TOPUP_MAX_RS,
        minWithdrawal: p.min_withdrawal,
      },
      demoAccounts: FEATURES.demoLogin ? DEMO_ACCOUNTS.filter((a) => !role || a.role === role) : [],
    },
  });
});

/**
 * GET /api/categories
 */
const getCategories = asyncHandler(async (req, res) => {
  const r = await pool.query('SELECT id, name, icon FROM categories ORDER BY sort_order, name');
  res.json({ success: true, data: r.rows });
});

/**
 * GET /api/products?search=&vendor_id=&category_id=&limit=20&offset=0
 * Only approved, in-stock products from approved vendors. Paginated (max 100 per page).
 * search matches the product name, description or store name.
 */
const getProducts = asyncHandler(async (req, res) => {
  const { search, vendor_id: vendorId, category_id: categoryId } = req.query;
  let query = PRODUCT_SELECT;
  const params = [];

  const pattern = searchPattern(search);
  if (pattern) {
    params.push(pattern);
    const n = params.length;
    query += ` AND (p.name ILIKE $${n} OR p.description ILIKE $${n} OR v.store_name ILIKE $${n})`;
  }
  if (vendorId) {
    params.push(intParam(vendorId, 'vendor_id'));
    query += ` AND p.vendor_id = $${params.length}`;
  }
  if (categoryId) {
    params.push(intParam(categoryId, 'category_id'));
    query += ` AND p.category_id = $${params.length}`;
  }

  const page = paging(req.query);
  params.push(page.limit + 1, page.offset);
  query += ` ORDER BY p.created_at DESC, p.id DESC LIMIT $${params.length - 1} OFFSET $${params.length}`;
  const result = await pool.query(query, params);
  const { items, meta } = pageOf(result.rows, page);
  res.json({ success: true, data: items.map(formatProduct), meta });
});

/**
 * GET /api/vendors/:id — store details + its products
 */
const getVendorDetails = asyncHandler(async (req, res) => {
  const vendorId = intParam(req.params.id);
  const vendorResult = await pool.query(
    `SELECT v.*, u.full_name AS owner_name, u.phone AS owner_phone
     FROM vendors v JOIN users u ON v.user_id = u.id
     WHERE v.id = $1 AND v.is_approved = true`,
    [vendorId]
  );
  if (vendorResult.rows.length === 0) throw httpError(404, 'Vendor not found');

  const vendor = vendorResult.rows[0];
  const productsResult = await pool.query(`${PRODUCT_SELECT} AND p.vendor_id = $1 ORDER BY p.created_at DESC`, [vendorId]);

  res.json({
    success: true,
    data: {
      id: vendor.id,
      storeName: vendor.store_name,
      storeAddress: vendor.store_address,
      ownerName: vendor.owner_name,
      ownerPhone: vendor.owner_phone,
      latitude: num(vendor.latitude),
      longitude: num(vendor.longitude),
      products: productsResult.rows.map(formatProduct),
    },
  });
});

/**
 * POST /api/customer/checkout/quote — what this cart costs right now, with the
 * distance-based delivery fee. Same body as checkout; same errors (409 stock etc.).
 */
const quoteCart = asyncHandler(async (req, res) => {
  const q = await quoteCheckout(pool, readCheckoutInput(req.body));
  res.json({
    success: true,
    data: {
      subtotal: paisaToNumber(q.subtotalPaisa),
      deliveryFee: paisaToNumber(q.deliveryFeePaisa),
      total: paisaToNumber(q.totalPaisa),
      distanceKm: Number(q.distanceKm.toFixed(2)),
      vendorId: q.vendorId,
    },
  });
});

/**
 * GET /api/stores?lat&lng&search — every approved store with a location and something on sale
 * (for the map). search matches the store name or address. With lat/lng they're sorted nearest first and carry distanceKm and
 * deliversToYou (within the max_delivery_km policy).
 */
const getStores = asyncHandler(async (req, res) => {
  const lat = Number(req.query.lat);
  const lng = Number(req.query.lng);
  const near = isValidCoordinate(lat, lng);
  const { max_delivery_km: maxKm } = await getPolicies();
  const r = await pool.query(
    `SELECT v.id, v.store_name, v.store_address, v.latitude, v.longitude, COUNT(p.id)::int AS product_count
     FROM vendors v
     JOIN products p ON p.vendor_id = v.id AND p.is_active AND p.is_approved AND p.public_stock > 0
     WHERE v.is_approved AND v.latitude IS NOT NULL AND v.longitude IS NOT NULL
       AND ($1::text IS NULL OR v.store_name ILIKE $1 OR v.store_address ILIKE $1)
     GROUP BY v.id
     ORDER BY v.store_name`,
    [searchPattern(req.query.search)]
  );
  const stores = r.rows.map((v) => ({
    id: v.id,
    storeName: v.store_name,
    storeAddress: v.store_address,
    latitude: Number(v.latitude),
    longitude: Number(v.longitude),
    productCount: v.product_count,
    distanceKm: near ? Number(haversineKm(lat, lng, Number(v.latitude), Number(v.longitude)).toFixed(2)) : null,
  }));
  if (near) {
    for (const st of stores) st.deliversToYou = !(maxKm > 0) || st.distanceKm <= maxKm;
    stores.sort((a, b) => a.distanceKm - b.distanceKm);
  }
  res.json({ success: true, data: stores });
});

/**
 * POST /api/customer/checkout — pay from the wallet
 * Body: { items: [{ productId, quantity }], deliveryType: 'delivery'|'self_pickup',
 *         deliveryAddress, customerLat, customerLng }
 * Delivery orders must include the customer's pin: the rider's 200 m geofence checks against it.
 * Paying by card: POST /api/payments/checkout (same body plus a card token).
 */
const checkout = asyncHandler(async (req, res) => {
  const input = readCheckoutInput(req.body);
  const data = await withTransaction((client, afterCommit) => placeOrder(client, afterCommit, req.user.userId, input));
  res.status(201).json({ success: true, message: 'Order placed successfully! Waiting for vendor approval.', data });
});

const ORDER_SELECT = `
  SELECT o.*, v.store_name, v.store_address, v.latitude AS vendor_lat, v.longitude AS vendor_lng,
         r.full_name AS rider_name, r.phone AS rider_phone,
         (SELECT json_build_object('id', d.id, 'status', d.status, 'resolution', d.resolution, 'issueType', d.issue_type)
            FROM disputes d WHERE d.order_id = o.id ORDER BY d.created_at DESC LIMIT 1) AS latest_dispute,
         COALESCE((SELECT json_agg(json_build_object(
              'id', oi.id, 'productId', oi.product_id, 'productName', p.name,
              'quantity', oi.quantity, 'unitPrice', oi.unit_price, 'imageUrl', p.image_url) ORDER BY oi.id)
            FROM order_items oi JOIN products p ON p.id = oi.product_id
            WHERE oi.order_id = o.id), '[]') AS items
  FROM orders o
  JOIN vendors v ON o.vendor_id = v.id
  LEFT JOIN users r ON r.id = o.rider_user_id`;

function formatCustomerOrder(o) {
  return {
    id: o.id,
    vendorId: o.vendor_id,
    storeName: o.store_name,
    storeAddress: o.store_address,
    vendorLat: num(o.vendor_lat),
    vendorLng: num(o.vendor_lng),
    status: o.status,
    deliveryType: o.delivery_type,
    deliveryAddress: o.delivery_address,
    customerLat: num(o.customer_lat),
    customerLng: num(o.customer_lng),
    estimatedMinutes: o.estimated_minutes,
    subtotal: Number(o.subtotal),
    deliveryFee: Number(o.delivery_fee),
    totalAmount: Number(o.total_amount),
    escrowStatus: o.escrow_status,
    escrowReleaseDueAt: o.escrow_release_due_at,
    cancellationReason: o.cancellation_reason,
    rider: o.rider_user_id ? { id: o.rider_user_id, name: o.rider_name, phone: o.rider_phone } : null,
    latestDispute: o.latest_dispute,
    createdAt: o.created_at,
    assignedAt: o.assigned_at,
    pickedAt: o.picked_at,
    deliveredAt: o.delivered_at,
    items: o.items.map((i) => ({ ...i, unitPrice: Number(i.unitPrice) })),
  };
}

/**
 * GET /api/customer/orders?scope=active|past&limit=20&offset=0 — newest first.
 * active = not yet delivered or cancelled. meta.activeCount is always the number of active orders.
 */
const getCustomerOrders = asyncHandler(async (req, res) => {
  const page = paging(req.query);
  const scope = req.query.scope;
  if (scope && !['active', 'past'].includes(scope)) throw httpError(400, 'scope must be active or past.');
  const filter = scope === 'active'
    ? `AND o.status NOT IN ('delivered', 'cancelled')`
    : scope === 'past' ? `AND o.status IN ('delivered', 'cancelled')` : '';
  const [r, active] = await Promise.all([
    pool.query(
      `${ORDER_SELECT} WHERE o.customer_id = $1 ${filter} ORDER BY o.created_at DESC, o.id DESC LIMIT $2 OFFSET $3`,
      [req.user.userId, page.limit + 1, page.offset]
    ),
    pool.query(`SELECT COUNT(*)::int AS n FROM orders WHERE customer_id = $1 AND status NOT IN ('delivered', 'cancelled')`, [req.user.userId]),
  ]);
  const { items, meta } = pageOf(r.rows, page);
  res.json({ success: true, data: items.map(formatCustomerOrder), meta: { ...meta, activeCount: active.rows[0].n } });
});

/**
 * GET /api/customer/orders/:id — one order (refresh after an order:update event)
 */
const getCustomerOrder = asyncHandler(async (req, res) => {
  const r = await pool.query(`${ORDER_SELECT} WHERE o.id = $1 AND o.customer_id = $2`, [intParam(req.params.id), req.user.userId]);
  if (r.rows.length === 0) throw httpError(404, 'Order not found.');
  res.json({ success: true, data: formatCustomerOrder(r.rows[0]) });
});

/**
 * GET /api/customer/orders/:id/tracking — order + live rider position + trip path
 */
const getOrderTracking = asyncHandler(async (req, res) => {
  const orderId = intParam(req.params.id);
  const r = await pool.query(`${ORDER_SELECT} WHERE o.id = $1 AND o.customer_id = $2`, [orderId, req.user.userId]);
  if (r.rows.length === 0) throw httpError(404, 'Order not found.');
  const order = r.rows[0];

  let riderLocation = null;
  let path = [];
  if (order.rider_user_id) {
    const loc = await pool.query(
      'SELECT current_lat, current_lng, last_location_at FROM riders WHERE user_id = $1',
      [order.rider_user_id]
    );
    if (loc.rows[0]?.current_lat != null) {
      riderLocation = {
        lat: Number(loc.rows[0].current_lat),
        lng: Number(loc.rows[0].current_lng),
        at: loc.rows[0].last_location_at,
      };
    }
    const pings = await pool.query(
      `SELECT latitude AS lat, longitude AS lng, recorded_at AS at
       FROM rider_locations WHERE order_id = $1 ORDER BY recorded_at`,
      [orderId]
    );
    path = pings.rows;
  }

  res.json({ success: true, data: { order: formatCustomerOrder(order), riderLocation, path } });
});

/**
 * POST /api/customer/orders/:id/cancel — pending orders only; stock released, full refund
 */
const cancelOrder = asyncHandler(async (req, res) => {
  const orderId = intParam(req.params.id);
  const refund = await withTransaction(async (client, afterCommit) => {
    const r = await client.query(
      `SELECT * FROM orders WHERE id = $1 AND customer_id = $2 FOR UPDATE`,
      [orderId, req.user.userId]
    );
    if (r.rows.length === 0) throw httpError(404, 'Order not found.');
    if (r.rows[0].status !== 'pending') {
      throw httpError(409, 'Only orders the store has not accepted yet can be cancelled. Raise a dispute instead.');
    }

    await releaseOrderLocks(client, afterCommit, orderId, 'Order cancelled by customer');
    await client.query(
      `UPDATE orders SET status = 'cancelled', cancellation_reason = 'Customer cancelled', updated_at = NOW() WHERE id = $1`,
      [orderId]
    );
    const result = await refundEscrow(client, afterCommit, orderId, { note: `Escrow refund for cancelled Order #${orderId}` });
    await announceOrder(client, afterCommit, orderId, 'order_cancelled', {
      vendor: { title: `Order #${orderId} cancelled`, body: 'The customer cancelled. Reserved stock is back on sale.' },
      customer: { title: `Order #${orderId} cancelled`, body: `Rs. ${result.refund.toFixed(2)} refunded to your wallet.` },
    });
    return result;
  });

  res.json({ success: true, message: 'Order cancelled. Amount refunded to wallet.', data: { refund: refund.refund } });
});

/**
 * POST /api/customer/orders/:id/picked-up — self pickup: customer collected items
 */
const customerMarkPickedUp = asyncHandler(async (req, res) => {
  const orderId = intParam(req.params.id);
  await withTransaction(async (client, afterCommit) => {
    const updated = await client.query(
      `UPDATE orders SET status = 'picked', picked_at = NOW(), updated_at = NOW()
       WHERE id = $1 AND customer_id = $2 AND delivery_type = 'self_pickup' AND status = 'ready_for_pickup'
       RETURNING id`,
      [orderId, req.user.userId]
    );
    if (updated.rows.length === 0) throw httpError(400, 'Order not found, not self pickup, or not ready for pickup.');
    await announceOrder(client, afterCommit, orderId, 'order_picked', {
      vendor: { title: `Order #${orderId} collected`, body: 'The customer picked up their order.' },
    });
  });
  res.json({ success: true, message: 'Marked as picked up.' });
});

/**
 * POST /api/customer/orders/:id/confirm-received — self pickup complete.
 * Stock is deducted and the dispute window starts; escrow releases after it.
 */
const customerConfirmOrderDelivered = asyncHandler(async (req, res) => {
  const orderId = intParam(req.params.id);
  await withTransaction(async (client, afterCommit) => {
    const updated = await client.query(
      `UPDATE orders SET status = 'delivered', delivered_at = NOW(), updated_at = NOW()
       WHERE id = $1 AND customer_id = $2 AND delivery_type = 'self_pickup'
         AND status IN ('ready_for_pickup', 'picked')
       RETURNING id`,
      [orderId, req.user.userId]
    );
    if (updated.rows.length === 0) {
      throw httpError(400, 'Cannot confirm this order. It may not be self pickup, not yours, or not ready yet.');
    }
    await consumeOrderLocks(client, afterCommit, orderId, 'Self pickup completed');
    await scheduleEscrowRelease(client, afterCommit, orderId);
    await announceOrder(client, afterCommit, orderId, 'order_delivered', {
      vendor: { title: `Order #${orderId} completed`, body: 'Payment will be released after the dispute window.' },
      customer: { title: `Order #${orderId} completed`, body: 'Something wrong? You can raise a dispute before payment is released.' },
    });
  });
  res.json({ success: true, message: 'Thank you! Order completed. Payment will be released to the store after the dispute window.' });
});

module.exports = {
  getPublicConfig,
  quoteCart,
  getStores,
  getCategories,
  getProducts,
  getVendorDetails,
  checkout,
  getCustomerOrders,
  getCustomerOrder,
  getOrderTracking,
  cancelOrder,
  customerMarkPickedUp,
  customerConfirmOrderDelivered,
};
