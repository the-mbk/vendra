// ══════════════════════════════════════════════════════════════
// Vendra Backend - Customer Controller
// Product browsing, atomic checkout with escrow, orders, tracking
// ══════════════════════════════════════════════════════════════

const pool = require('../db');
const { lockEscrowRow, creditEscrowPool } = require('../services/escrowPool.service');
const { lockProducts, applyStockChange, releaseOrderLocks, consumeOrderLocks } = require('../services/inventory.service');
const { debitWallet, creditWallet } = require('../services/wallet.service');
const { refundEscrow, scheduleEscrowRelease } = require('../services/orderSettlement.service');
const { announceOrder } = require('../services/notification.service');
const { getPolicies } = require('../services/policy.service');
const { httpError, asyncHandler, withTransaction, intParam, paging, pageOf } = require('../utils/http');
const { haversineKm, isValidCoordinate } = require('../utils/geo');
const { toPaisa, paisaToString, paisaToNumber } = require('../utils/money');

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
  res.json({
    success: true,
    data: {
      deliveryFee: p.delivery_fee,
      disputeWindowMinutes: p.dispute_window_min,
      geofenceMeters: p.geofence_m,
      taskRadiusKm: p.task_radius_km,
      defaultBuffer: p.default_buffer,
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
 */
const getProducts = asyncHandler(async (req, res) => {
  const { search, vendor_id: vendorId, category_id: categoryId } = req.query;
  let query = PRODUCT_SELECT;
  const params = [];

  if (search) {
    params.push(`%${search}%`);
    query += ` AND (p.name ILIKE $${params.length} OR p.description ILIKE $${params.length})`;
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

function parseCheckoutItems(items) {
  if (!Array.isArray(items) || items.length === 0) {
    throw httpError(400, 'Items array is required and must not be empty.');
  }
  const merged = new Map();
  for (const item of items) {
    const productId = Number(item?.productId);
    const quantity = Number(item?.quantity);
    if (!Number.isInteger(productId) || productId <= 0 || !Number.isInteger(quantity) || quantity <= 0) {
      throw httpError(400, 'Each item needs a valid productId and a whole-number quantity above 0.');
    }
    merged.set(productId, (merged.get(productId) || 0) + quantity);
  }
  return [...merged].map(([productId, quantity]) => ({ productId, quantity }));
}

/**
 * POST /api/customer/checkout — ATOMIC ORDER RESERVATION (FR02) + ESCROW HOLD (FR03)
 * Body: { items: [{ productId, quantity }], deliveryType: 'delivery'|'self_pickup',
 *         deliveryAddress, customerLat, customerLng }
 * Delivery orders must include the customer's pin: the rider's 200 m geofence checks against it.
 */
const checkout = asyncHandler(async (req, res) => {
  const { deliveryType = 'delivery', deliveryAddress } = req.body;
  const customerLat = num(req.body.customerLat);
  const customerLng = num(req.body.customerLng);
  const customerId = req.user.userId;
  const items = parseCheckoutItems(req.body.items);

  if (!['delivery', 'self_pickup'].includes(deliveryType)) {
    throw httpError(400, "deliveryType must be 'delivery' or 'self_pickup'.");
  }
  if (deliveryType === 'delivery' && !isValidCoordinate(customerLat, customerLng)) {
    throw httpError(400, 'Set your delivery location on the map before placing a delivery order.');
  }

  const data = await withTransaction(async (client, afterCommit) => {
    const policies = await getPolicies(client);

    // Step 1: lock every product row (id order → no deadlocks between concurrent checkouts)
    const products = await lockProducts(client, items.map((i) => i.productId));

    // Step 2: validate stock and single-vendor rule
    let vendorId = null;
    let subtotal = 0;
    const lines = [];
    for (const item of items) {
      const p = products.get(item.productId);
      if (!p) throw httpError(404, `Product ${item.productId} not found.`);
      if (!p.is_active || !p.is_approved) throw httpError(400, `"${p.name}" is no longer available.`);
      if (p.public_stock < item.quantity) {
        throw httpError(409, `Insufficient stock for "${p.name}". Available: ${p.public_stock}, requested: ${item.quantity}.`, {
          code: 'INSUFFICIENT_STOCK', productId: p.id, available: p.public_stock,
        });
      }
      if (vendorId === null) vendorId = p.vendor_id;
      else if (p.vendor_id !== vendorId) throw httpError(400, 'All items must be from the same vendor.');

      const unit = toPaisa(p.price);
      subtotal += unit * item.quantity;
      lines.push({ product: p, quantity: item.quantity, unitPaisa: unit });
    }

    const vendor = (await client.query('SELECT latitude, longitude, is_approved FROM vendors WHERE id = $1', [vendorId])).rows[0];
    if (!vendor?.is_approved) throw httpError(400, 'This store is not accepting orders right now.');

    const deliveryFee = deliveryType === 'delivery' ? toPaisa(policies.delivery_fee) : 0;
    const total = subtotal + deliveryFee;

    let estimatedMinutes = null;
    if (deliveryType === 'delivery' && vendor.latitude != null) {
      const km = haversineKm(customerLat, customerLng, Number(vendor.latitude), Number(vendor.longitude));
      estimatedMinutes = Math.max(15, Math.round(km * 3));
    }

    // Step 3: create the order (pending vendor approval)
    const order = (await client.query(
      `INSERT INTO orders (customer_id, vendor_id, status, subtotal, delivery_fee, total_amount,
                           delivery_type, delivery_address, customer_lat, customer_lng, estimated_minutes, escrow_status)
       VALUES ($1, $2, 'pending', $3, $4, $5, $6, $7, $8, $9, $10, 'held')
       RETURNING *`,
      [customerId, vendorId, paisaToString(subtotal), paisaToString(deliveryFee), paisaToString(total),
        deliveryType, deliveryAddress || null, customerLat, customerLng, estimatedMinutes]
    )).rows[0];

    // Step 4: escrow hold — customer wallet → platform pool.
    // Lock order everywhere is products → escrow pool → wallets, so the pool row is locked first.
    await lockEscrowRow(client);
    const walletAfter = await debitWallet(client, {
      userId: customerId,
      amountPaisa: total,
      type: 'escrow_hold',
      orderId: order.id,
      description: `Escrow hold for Order #${order.id}`,
    });
    await creditEscrowPool(client, paisaToString(total));

    // Step 5: reserve stock + lock rows + ledger
    for (const line of lines) {
      await client.query(
        `INSERT INTO order_items (order_id, product_id, quantity, unit_price, subtotal) VALUES ($1, $2, $3, $4, $5)`,
        [order.id, line.product.id, line.quantity, paisaToString(line.unitPaisa), paisaToString(line.unitPaisa * line.quantity)]
      );
      await applyStockChange(client, afterCommit, line.product, {
        reservedQuantity: line.product.reserved_quantity + line.quantity,
        ledger: { type: 'reserve', quantityChange: -line.quantity, referenceId: order.id, notes: 'Online order reserved' },
      });
      await client.query(
        `INSERT INTO inventory_locks (product_id, order_id, quantity, status) VALUES ($1, $2, $3, 'active')`,
        [line.product.id, order.id, line.quantity]
      );
    }

    await announceOrder(client, afterCommit, order.id, 'order_placed', {
      vendor: { title: `New order #${order.id}`, body: `Rs. ${paisaToString(total)} · ${lines.length} item(s). Approve it to start packing.` },
      customer: { title: `Order #${order.id} placed`, body: 'Payment is held in escrow until delivery. Waiting for the store to accept.' },
    });

    return {
      id: order.id,
      customerId: order.customer_id,
      vendorId: order.vendor_id,
      status: order.status,
      deliveryType: order.delivery_type,
      estimatedMinutes: order.estimated_minutes,
      subtotal: paisaToNumber(subtotal),
      deliveryFee: paisaToNumber(deliveryFee),
      totalAmount: paisaToNumber(total),
      createdAt: order.created_at,
      escrowStatus: 'held',
      walletBalance: paisaToNumber(walletAfter),
      items: lines.map((l) => ({
        productId: l.product.id,
        productName: l.product.name,
        quantity: l.quantity,
        unitPrice: paisaToNumber(l.unitPaisa),
      })),
    };
  });

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
 * GET /api/customer/orders?limit=20&offset=0 — newest first
 */
const getCustomerOrders = asyncHandler(async (req, res) => {
  const page = paging(req.query);
  const r = await pool.query(
    `${ORDER_SELECT} WHERE o.customer_id = $1 ORDER BY o.created_at DESC, o.id DESC LIMIT $2 OFFSET $3`,
    [req.user.userId, page.limit + 1, page.offset]
  );
  const { items, meta } = pageOf(r.rows, page);
  res.json({ success: true, data: items.map(formatCustomerOrder), meta });
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
 * POST /api/customer/wallet/topup — simulated deposit (no payment gateway)
 */
const topupWallet = asyncHandler(async (req, res) => {
  const amount = Number(req.body.amount);
  if (!Number.isFinite(amount) || amount <= 0 || amount > 1000000) {
    throw httpError(400, 'Top-up amount must be between Rs. 0.01 and Rs. 1,000,000.');
  }
  const amountPaisa = toPaisa(amount);
  const balance = await withTransaction((client) => creditWallet(client, {
    userId: req.user.userId,
    amountPaisa,
    type: 'deposit',
    description: `Top-up of Rs. ${paisaToString(amountPaisa)}`,
  }));
  res.json({ success: true, message: 'Wallet topped up successfully.', walletBalance: paisaToNumber(balance) });
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
  getCategories,
  getProducts,
  getVendorDetails,
  checkout,
  getCustomerOrders,
  getCustomerOrder,
  getOrderTracking,
  cancelOrder,
  topupWallet,
  customerMarkPickedUp,
  customerConfirmOrderDelivered,
};
