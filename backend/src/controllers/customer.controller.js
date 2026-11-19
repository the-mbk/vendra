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
const { submitOrderReview, formatReview } = require('../services/review.service');
const { haversineKm, isValidCoordinate } = require('../utils/geo');
const { paisaToNumber } = require('../utils/money');
const { shortName, contactWhile } = require('../utils/privacy');
const { publicGatewayConfig } = require('../services/gateway.client');
const payoutAccounts = require('../services/payoutAccounts.service');
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
    storeLogoUrl: p.store_logo_url || null,
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
    averageRating: p.rating_count > 0 ? Math.round((p.rating_sum / p.rating_count) * 10) / 10 : null,
    ratingCount: p.rating_count ?? 0,
    createdAt: p.created_at,
  };
}

/** Average and count of a store's product reviews */
async function storeRating(db, vendorId) {
  const r = await db.query(
    'SELECT COUNT(*)::int AS count, ROUND(AVG(rating), 1)::float8 AS average FROM product_reviews WHERE vendor_id = $1',
    [vendorId]
  );
  return { averageRating: r.rows[0].average, ratingCount: r.rows[0].count };
}

/** How many of a store's (or product's) reviews gave each number of stars */
function starDistribution(rows) {
  const distribution = { 5: 0, 4: 0, 3: 0, 2: 0, 1: 0 };
  for (const row of rows) distribution[row.rating] = row.n;
  return distribution;
}

const REVIEW_SELECT = `
  SELECT pr.*, u.full_name AS customer_name, p.name AS product_name
  FROM product_reviews pr JOIN users u ON u.id = pr.customer_id JOIN products p ON p.id = pr.product_id`;

const PRODUCT_SELECT = `
  SELECT p.*, v.store_name, v.store_address, v.latitude AS vendor_lat, v.longitude AS vendor_lng,
         v.logo_url AS store_logo_url, c.name AS category_name
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
      // Rider payout rates (FR04): the rider app's store waiting clock uses the wait ones
      riderBaseFee: p.rider_base_fee,
      riderPerKm: p.rider_per_km,
      riderPerWaitMin: p.rider_per_wait_min,
      riderFreeWaitMinutes: p.rider_free_wait_min,
      defaultBuffer: p.default_buffer,
      vendorAcceptTimeoutMinutes: p.vendor_accept_timeout_min,
      riderAssignTimeoutMinutes: p.rider_assign_timeout_min,
      // Task hoarding guard: reach the store within this time of accepting, or lose the delivery
      riderPickupTimeoutMinutes: p.rider_pickup_timeout_min,
      // At the store: collect within this time of arriving, or lose the delivery
      riderStoreWaitMaxMinutes: p.rider_store_wait_max_min,
      // Cancelling after the store accepted costs this share of the items (pending orders cancel free)
      cancelPenaltyPct: p.cancel_penalty_pct,
      // Stores are told to restock at this many free shelf units
      lowStockUnits: p.low_stock_units,
      payments: {
        ...publicGatewayConfig(), // provider: vendrapay | stripe, publishableKey, gatewayUrl (Vendra Pay only)
        // Where withdrawals go: card (Vendra Pay), payoneer, or stripe_account (Stripe Connect)
        payoutsTo: { card: 'card', payoneer: 'payoneer', stripe_connect: 'stripe_account' }[payoutAccounts.mode()],
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
  const [productsResult, rating, stars, latest] = await Promise.all([
    pool.query(`${PRODUCT_SELECT} AND p.vendor_id = $1 ORDER BY p.created_at DESC`, [vendorId]),
    storeRating(pool, vendorId),
    pool.query('SELECT rating, COUNT(*)::int AS n FROM product_reviews WHERE vendor_id = $1 GROUP BY rating', [vendorId]),
    pool.query(`${REVIEW_SELECT} WHERE pr.vendor_id = $1 ORDER BY pr.created_at DESC, pr.id DESC LIMIT 3`, [vendorId]),
  ]);

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
      logoUrl: vendor.logo_url || null,
      coverUrl: vendor.cover_url || null,
      ...rating,
      ratingDistribution: starDistribution(stars.rows),
      latestReviews: latest.rows.map(formatReview),
      products: productsResult.rows.map(formatProduct),
    },
  });
});

/**
 * GET /api/products/:id — one product with its photo gallery, rating summary and
 * latest reviews. Out-of-stock products still open (shown as sold out).
 */
const getProduct = asyncHandler(async (req, res) => {
  const productId = intParam(req.params.id);
  const r = await pool.query(
    `SELECT p.*, v.store_name, v.store_address, v.latitude AS vendor_lat, v.longitude AS vendor_lng,
            v.logo_url AS store_logo_url, c.name AS category_name
     FROM products p JOIN vendors v ON v.id = p.vendor_id LEFT JOIN categories c ON c.id = p.category_id
     WHERE p.id = $1 AND p.is_active AND p.is_approved AND v.is_approved`,
    [productId]
  );
  if (r.rows.length === 0) throw httpError(404, 'Product not found.');
  const [gallery, stars, latest] = await Promise.all([
    pool.query('SELECT url FROM product_images WHERE product_id = $1 ORDER BY position, id', [productId]),
    pool.query('SELECT rating, COUNT(*)::int AS n FROM product_reviews WHERE product_id = $1 GROUP BY rating', [productId]),
    pool.query(
      `SELECT pr.*, u.full_name AS customer_name FROM product_reviews pr JOIN users u ON u.id = pr.customer_id
       WHERE pr.product_id = $1 ORDER BY pr.created_at DESC, pr.id DESC LIMIT 3`,
      [productId]
    ),
  ]);
  const product = formatProduct(r.rows[0]);
  const images = [product.imageUrl, ...gallery.rows.map((g) => g.url)].filter(Boolean);
  const distribution = starDistribution(stars.rows);
  res.json({
    success: true,
    data: {
      ...product,
      images: [...new Set(images)],
      ratingDistribution: distribution,
      latestReviews: latest.rows.map(formatReview),
    },
  });
});

/** GET /api/products/:id/reviews?limit=&offset= — newest first */
const getProductReviews = asyncHandler(async (req, res) => {
  const productId = intParam(req.params.id);
  const page = paging(req.query);
  const r = await pool.query(
    `SELECT pr.*, u.full_name AS customer_name FROM product_reviews pr JOIN users u ON u.id = pr.customer_id
     WHERE pr.product_id = $1 ORDER BY pr.created_at DESC, pr.id DESC LIMIT $2 OFFSET $3`,
    [productId, page.limit + 1, page.offset]
  );
  const { items, meta } = pageOf(r.rows, page);
  res.json({ success: true, data: items.map(formatReview), meta });
});

/** GET /api/vendors/:id/reviews?limit=&offset= — all of a store's product reviews, newest first */
const getStoreReviews = asyncHandler(async (req, res) => {
  const vendorId = intParam(req.params.id);
  const page = paging(req.query);
  const r = await pool.query(
    `${REVIEW_SELECT} WHERE pr.vendor_id = $1 ORDER BY pr.created_at DESC, pr.id DESC LIMIT $2 OFFSET $3`,
    [vendorId, page.limit + 1, page.offset]
  );
  const { items, meta } = pageOf(r.rows, page);
  res.json({ success: true, data: items.map(formatReview), meta });
});

/**
 * GET /api/customer/products/:id/review-order — the customer's latest delivered order with
 * this product that they haven't reviewed yet → { orderId } (null when there is none).
 * The product page shows "Write a review" for it; the review itself is POST /customer/orders/:id/review.
 */
const getReviewableOrder = asyncHandler(async (req, res) => {
  const productId = intParam(req.params.id);
  const r = await pool.query(
    `SELECT o.id FROM orders o JOIN order_items oi ON oi.order_id = o.id
     WHERE o.customer_id = $1 AND oi.product_id = $2 AND o.status = 'delivered' AND o.reviewed_at IS NULL
     ORDER BY o.created_at DESC LIMIT 1`,
    [req.user.userId, productId]
  );
  res.json({ success: true, data: { orderId: r.rows[0]?.id ?? null } });
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
    `SELECT v.id, v.store_name, v.store_address, v.latitude, v.longitude, v.logo_url, v.cover_url,
            COUNT(p.id)::int AS product_count
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
    logoUrl: v.logo_url || null,
    coverUrl: v.cover_url || null,
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
         r.full_name AS rider_name, r.phone AS rider_phone, r.avatar_url AS rider_photo_url,
         (SELECT json_build_object('id', d.id, 'status', d.status, 'resolution', d.resolution, 'issueType', d.issue_type)
            FROM disputes d WHERE d.order_id = o.id ORDER BY d.created_at DESC LIMIT 1) AS latest_dispute,
         COALESCE((SELECT json_agg(json_build_object(
              'id', oi.id, 'productId', oi.product_id, 'productName', p.name,
              'quantity', oi.quantity, 'unitPrice', oi.unit_price, 'imageUrl', p.image_url,
              'myRating', pr.rating, 'myComment', pr.comment) ORDER BY oi.id)
            FROM order_items oi JOIN products p ON p.id = oi.product_id
            LEFT JOIN product_reviews pr ON pr.order_id = oi.order_id AND pr.product_id = oi.product_id
            WHERE oi.order_id = o.id), '[]') AS items,
         -- Receipt: what came back to the wallet, and the card that paid
         (SELECT COALESCE(SUM(wl.amount), 0) FROM wallet_ledger wl
            WHERE wl.order_id = o.id AND wl.user_id = o.customer_id AND wl.transaction_type = 'escrow_refund') AS refunded_amount,
         (SELECT CONCAT_WS(' ', INITCAP(pm.card_brand), 'ending', pm.card_last4) FROM payments pm
            WHERE pm.order_id = o.id AND pm.purpose = 'checkout' AND pm.status = 'succeeded' AND pm.card_last4 IS NOT NULL
            ORDER BY pm.id DESC LIMIT 1) AS card_label
  FROM orders o
  JOIN vendors v ON o.vendor_id = v.id
  LEFT JOIN users r ON r.id = o.rider_user_id`;

const isOpen = (status) => !['delivered', 'cancelled'].includes(status);

/**
 * policies (optional) lets a pending order carry reservationExpiresAt: the
 * moment its reserved stock is released if the store hasn't accepted it.
 */
function formatCustomerOrder(o, policies = null) {
  const reservationExpiresAt = o.status === 'pending' && policies
    ? new Date(new Date(o.created_at).getTime() + policies.vendor_accept_timeout_min * 60000)
    : null;
  const otpLocked = o.otp_locked_until && new Date(o.otp_locked_until) > new Date();
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
    deliveryNote: o.delivery_note || null,
    customerLat: num(o.customer_lat),
    customerLng: num(o.customer_lng),
    estimatedMinutes: o.estimated_minutes,
    subtotal: Number(o.subtotal),
    deliveryFee: Number(o.delivery_fee),
    totalAmount: Number(o.total_amount),
    escrowStatus: o.escrow_status,
    escrowReleaseDueAt: o.escrow_release_due_at,
    cancellationReason: o.cancellation_reason,
    // The rider's short name; their number only while the delivery is under way
    rider: o.rider_user_id
      ? {
        id: o.rider_user_id,
        name: shortName(o.rider_name),
        phone: contactWhile(o.status, o.rider_phone),
        photoUrl: o.rider_photo_url || null,
      }
      : null,
    latestDispute: o.latest_dispute,
    createdAt: o.created_at,
    assignedAt: o.assigned_at,
    pickedAt: o.picked_at,
    deliveredAt: o.delivered_at,
    reservationExpiresAt,
    paymentMethod: o.payment_method,
    cardLabel: o.card_label || null,
    refundedAmount: Number(o.refunded_amount || 0),
    // Handover code: shown to the customer only, until the order is handed over
    deliveryOtp: isOpen(o.status) ? o.delivery_otp : null,
    otpLockedUntil: otpLocked ? o.otp_locked_until : null,
    reviewedAt: o.reviewed_at,
    canReview: o.status === 'delivered' && !o.reviewed_at,
    riderRating: o.rider_rating,
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
  const [r, active, policies] = await Promise.all([
    pool.query(
      `${ORDER_SELECT} WHERE o.customer_id = $1 ${filter} ORDER BY o.created_at DESC, o.id DESC LIMIT $2 OFFSET $3`,
      [req.user.userId, page.limit + 1, page.offset]
    ),
    pool.query(`SELECT COUNT(*)::int AS n FROM orders WHERE customer_id = $1 AND status NOT IN ('delivered', 'cancelled')`, [req.user.userId]),
    getPolicies(),
  ]);
  const { items, meta } = pageOf(r.rows, page);
  res.json({ success: true, data: items.map((o) => formatCustomerOrder(o, policies)), meta: { ...meta, activeCount: active.rows[0].n } });
});

/**
 * GET /api/customer/orders/:id — one order (refresh after an order:update event)
 */
const getCustomerOrder = asyncHandler(async (req, res) => {
  const r = await pool.query(`${ORDER_SELECT} WHERE o.id = $1 AND o.customer_id = $2`, [intParam(req.params.id), req.user.userId]);
  if (r.rows.length === 0) throw httpError(404, 'Order not found.');
  res.json({ success: true, data: formatCustomerOrder(r.rows[0], await getPolicies()) });
});

/**
 * GET /api/customer/orders/:id/tracking — order + live rider position + trip path.
 * The rider's live position is only shared while they are on this delivery;
 * after handover the customer keeps the trip path but not where the rider is now.
 */
const getOrderTracking = asyncHandler(async (req, res) => {
  const orderId = intParam(req.params.id);
  const r = await pool.query(`${ORDER_SELECT} WHERE o.id = $1 AND o.customer_id = $2`, [orderId, req.user.userId]);
  if (r.rows.length === 0) throw httpError(404, 'Order not found.');
  const order = r.rows[0];

  let riderLocation = null;
  let path = [];
  if (order.rider_user_id) {
    if (isOpen(order.status)) {
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
    }
    const pings = await pool.query(
      `SELECT latitude AS lat, longitude AS lng, recorded_at AS at
       FROM rider_locations WHERE order_id = $1 ORDER BY recorded_at`,
      [orderId]
    );
    path = pings.rows;
  }

  res.json({ success: true, data: { order: formatCustomerOrder(order, await getPolicies()), riderLocation, path } });
});

/**
 * POST /api/customer/orders/:id/cancel — stock released, money back to the wallet.
 *   pending    the store hasn't accepted: free, full refund
 *   confirmed  accepted but not packed: the store keeps cancel_penalty_pct % of the items
 *              for the work started (policy engine, SRDS §1.3); the rest is refunded
 * Packed orders can no longer be cancelled; a dispute is the way after that.
 */
const cancelOrder = asyncHandler(async (req, res) => {
  const orderId = intParam(req.params.id);
  const result = await withTransaction(async (client, afterCommit) => {
    const r = await client.query(
      `SELECT * FROM orders WHERE id = $1 AND customer_id = $2 FOR UPDATE`,
      [orderId, req.user.userId]
    );
    if (r.rows.length === 0) throw httpError(404, 'Order not found.');
    const { status } = r.rows[0];
    if (!['pending', 'confirmed'].includes(status)) {
      throw httpError(409, 'This order is already packed, so it can no longer be cancelled. Raise a dispute instead.', {
        code: 'TOO_LATE_TO_CANCEL',
      });
    }
    const feePct = status === 'confirmed' ? (await getPolicies(client)).cancel_penalty_pct || 0 : 0;

    await releaseOrderLocks(client, afterCommit, orderId, 'Order cancelled by customer');
    await client.query(
      `UPDATE orders SET status = 'cancelled', cancellation_reason = $2, updated_at = NOW() WHERE id = $1`,
      [orderId, feePct > 0 ? `Customer cancelled after the store accepted (${feePct}% fee)` : 'Customer cancelled']
    );
    const settled = await refundEscrow(client, afterCommit, orderId, {
      note: `Escrow refund for cancelled Order #${orderId}`, storeFeePct: feePct,
    });
    const fee = settled.storeFee > 0 ? ` Rs. ${settled.storeFee.toFixed(2)} late cancellation fee paid to the store.` : '';
    await announceOrder(client, afterCommit, orderId, 'order_cancelled', {
      vendor: {
        title: `Order #${orderId} cancelled`,
        body: `The customer cancelled. Reserved stock is back on sale.${settled.storeFee > 0 ? ` Rs. ${settled.storeFee.toFixed(2)} fee added to your wallet.` : ''}`,
      },
      customer: { title: `Order #${orderId} cancelled`, body: `Rs. ${settled.refund.toFixed(2)} refunded to your wallet.${fee}` },
    });
    const wallet = await client.query('SELECT wallet_balance FROM users WHERE id = $1', [req.user.userId]);
    return { ...settled, walletBalance: Number(wallet.rows[0].wallet_balance) };
  });

  res.json({
    success: true,
    message: result.storeFee > 0
      ? `Order cancelled. Rs. ${result.refund.toFixed(2)} refunded; Rs. ${result.storeFee.toFixed(2)} went to the store as the late cancellation fee.`
      : 'Order cancelled. Amount refunded to wallet.',
    data: { refund: result.refund, storeFee: result.storeFee, walletBalance: result.walletBalance },
  });
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

/**
 * POST /api/customer/orders/:id/review  Body: { items: [{ productId, rating, comment? }], riderRating? }
 * Once per delivered order.
 */
const reviewOrder = asyncHandler(async (req, res) => {
  const orderId = intParam(req.params.id);
  const data = await withTransaction((client, afterCommit) => submitOrderReview(client, afterCommit, req.user.userId, orderId, req.body));
  res.status(201).json({ success: true, message: 'Thanks for your review!', data });
});

module.exports = {
  getPublicConfig,
  quoteCart,
  getStores,
  getCategories,
  getProducts,
  getProduct,
  getProductReviews,
  getStoreReviews,
  getReviewableOrder,
  getVendorDetails,
  reviewOrder,
  checkout,
  getCustomerOrders,
  getCustomerOrder,
  getOrderTracking,
  cancelOrder,
  customerMarkPickedUp,
  customerConfirmOrderDelivered,
};
