// ══════════════════════════════════════════════════════════════
// Vendra Backend - Customer Controller
// Handles product browsing, atomic checkout, and order history
// ══════════════════════════════════════════════════════════════

const pool = require('../db');
const { lockEscrowRow, creditEscrowPool, debitEscrowPool } = require('../services/escrowPool.service');
const { payoutVendorFromEscrow } = require('../services/orderSettlement.service');

const STANDARD_DELIVERY_FEE = 150;

/**
 * GET /api/products
 * Browse available products (public_stock > 0).
 * Query params: search, vendor_id
 * Returns vendor location info alongside each product
 */
const getProducts = async (req, res) => {
  try {
    const { search, vendor_id } = req.query;
    let query = `
      SELECT p.*, v.store_name, v.store_address, v.latitude AS vendor_lat, v.longitude AS vendor_lng
      FROM products p
      JOIN vendors v ON p.vendor_id = v.id
      WHERE p.is_active = true AND p.public_stock > 0 AND v.is_approved = true
    `;
    const params = [];
    let paramIndex = 1;

    if (search) {
      query += ` AND (p.name ILIKE $${paramIndex} OR p.description ILIKE $${paramIndex})`;
      params.push(`%${search}%`);
      paramIndex++;
    }

    if (vendor_id) {
      query += ` AND p.vendor_id = $${paramIndex}`;
      params.push(vendor_id);
      paramIndex++;
    }

    query += ' ORDER BY p.created_at DESC';
    const result = await pool.query(query, params);

    res.json({
      success: true,
      data: result.rows.map((p) => ({
        id: p.id,
        vendorId: p.vendor_id,
        storeName: p.store_name,
        storeAddress: p.store_address,
        vendorLat: p.vendor_lat ? parseFloat(p.vendor_lat) : null,
        vendorLng: p.vendor_lng ? parseFloat(p.vendor_lng) : null,
        name: p.name,
        description: p.description,
        price: parseFloat(p.price),
        publicStock: p.public_stock,
        barcode: p.barcode,
        imageUrl: p.image_url,
        createdAt: p.created_at,
      })),
    });
  } catch (error) {
    console.error('Get products error:', error);
    res.status(500).json({ success: false, message: 'Failed to fetch products.' });
  }
};

/**
 * GET /api/vendors/:id
 * Get vendor details + all their products
 */
const getVendorDetails = async (req, res) => {
  try {
    const vendorId = req.params.id;

    // Get vendor info
    const vendorResult = await pool.query(
      `SELECT v.*, u.full_name AS owner_name, u.phone AS owner_phone
       FROM vendors v
       JOIN users u ON v.user_id = u.id
       WHERE v.id = $1 AND v.is_approved = true`,
      [vendorId]
    );

    if (vendorResult.rows.length === 0) {
      return res.status(404).json({ success: false, message: 'Vendor not found' });
    }

    const vendor = vendorResult.rows[0];

    // Get vendor's products
    const productsResult = await pool.query(
      `SELECT * FROM products WHERE vendor_id = $1 AND is_active = true AND public_stock > 0 ORDER BY created_at DESC`,
      [vendorId]
    );

    res.json({
      success: true,
      data: {
        id: vendor.id,
        storeName: vendor.store_name,
        storeAddress: vendor.store_address,
        ownerName: vendor.owner_name,
        ownerPhone: vendor.owner_phone,
        latitude: vendor.latitude ? parseFloat(vendor.latitude) : null,
        longitude: vendor.longitude ? parseFloat(vendor.longitude) : null,
        products: productsResult.rows.map((p) => ({
          id: p.id,
          vendorId: p.vendor_id,
          storeName: vendor.store_name,
          name: p.name,
          description: p.description,
          price: parseFloat(p.price),
          publicStock: p.public_stock,
          barcode: p.barcode,
          imageUrl: p.image_url,
          createdAt: p.created_at,
        })),
      },
    });
  } catch (error) {
    console.error('Get vendor details error:', error);
    res.status(500).json({ success: false, message: 'Failed to fetch vendor details.' });
  }
};

/**
 * POST /api/customer/checkout
 * ATOMIC ORDER RESERVATION TRANSACTION
 * Body: { items: [{ productId, quantity }], deliveryType: 'delivery'|'self_pickup', deliveryAddress, customerLat, customerLng }
 * Orders now start as 'pending' and require vendor approval
 */
const checkout = async (req, res) => {
  const client = await pool.connect();

  try {
    const { items, deliveryType = 'delivery', deliveryAddress, customerLat, customerLng } = req.body;
    const customerId = req.user.userId;

    if (!items || !Array.isArray(items) || items.length === 0) {
      return res.status(400).json({
        success: false,
        message: 'Items array is required and must not be empty.',
      });
    }

    await client.query('BEGIN');

    // Step 1: Lock products with SELECT FOR UPDATE
    const productIds = items.map((i) => i.productId);
    const lockedProducts = await client.query(
      `SELECT * FROM products WHERE id = ANY($1) FOR UPDATE`,
      [productIds]
    );

    // Build a map for quick lookup
    const productMap = {};
    for (const p of lockedProducts.rows) {
      productMap[p.id] = p;
    }

    // Step 2: Verify all products exist and have sufficient stock
    let totalAmount = 0;
    let vendorId = null;
    const orderItems = [];

    for (const item of items) {
      const product = productMap[item.productId];

      if (!product) {
        await client.query('ROLLBACK');
        return res.status(404).json({
          success: false,
          message: `Product ${item.productId} not found.`,
        });
      }

      if (!product.is_active) {
        await client.query('ROLLBACK');
        return res.status(400).json({
          success: false,
          message: `Product "${product.name}" is no longer available.`,
        });
      }

      // Verify sufficient public stock
      if (product.public_stock < item.quantity) {
        await client.query('ROLLBACK');
        return res.status(400).json({
          success: false,
          message: `Insufficient stock for "${product.name}". Available: ${product.public_stock}, Requested: ${item.quantity}`,
        });
      }

      // All items must belong to the same vendor (single-vendor order)
      if (vendorId === null) {
        vendorId = product.vendor_id;
      } else if (product.vendor_id !== vendorId) {
        await client.query('ROLLBACK');
        return res.status(400).json({
          success: false,
          message: 'All items must be from the same vendor.',
        });
      }

      const itemTotal = parseFloat(product.price) * item.quantity;
      totalAmount += itemTotal;

      orderItems.push({
        productId: product.id,
        quantity: item.quantity,
        unitPrice: parseFloat(product.price),
        productName: product.name,
      });
    }

    const deliveryFee = deliveryType === 'delivery' ? STANDARD_DELIVERY_FEE : 0;
    totalAmount += deliveryFee;

    // Calculate estimated delivery time (approx 3 min per km, min 15 min)
    let estimatedMinutes = null;
    if (deliveryType === 'delivery' && customerLat && customerLng) {
      // Get vendor location
      const vendorLoc = await client.query('SELECT latitude, longitude FROM vendors WHERE id = $1', [vendorId]);
      if (vendorLoc.rows[0]?.latitude && vendorLoc.rows[0]?.longitude) {
        const dist = haversineDistance(
          customerLat, customerLng,
          parseFloat(vendorLoc.rows[0].latitude), parseFloat(vendorLoc.rows[0].longitude)
        );
        estimatedMinutes = Math.max(15, Math.round(dist * 3));
      }
    }

    // --- ESCROW LOGIC START ---
    await lockEscrowRow(client);
    const userWalletRes = await client.query(
      'SELECT wallet_balance FROM users WHERE id = $1 FOR UPDATE',
      [customerId]
    );
    const walletBalance = parseFloat(userWalletRes.rows[0].wallet_balance);

    if (walletBalance < totalAmount) {
      await client.query('ROLLBACK');
      return res.status(400).json({
        success: false,
        message: `Insufficient wallet balance. Total amount is Rs. ${totalAmount.toFixed(2)} but you only have Rs. ${walletBalance.toFixed(2)}.`,
      });
    }

    const newBalance = walletBalance - totalAmount;
    await client.query('UPDATE users SET wallet_balance = $1 WHERE id = $2', [newBalance, customerId]);
    await creditEscrowPool(client, totalAmount);
    // --- ESCROW LOGIC END ---

    // Step 3: Create order with PENDING status (vendor must approve)
    const orderResult = await client.query(
      `INSERT INTO orders (customer_id, vendor_id, status, total_amount, delivery_type, delivery_address, customer_lat, customer_lng, estimated_minutes)
       VALUES ($1, $2, 'pending', $3, $4, $5, $6, $7, $8)
       RETURNING *`,
      [customerId, vendorId, totalAmount.toFixed(2), deliveryType, deliveryAddress || null, customerLat || null, customerLng || null, estimatedMinutes]
    );
    const order = orderResult.rows[0];

    // Step 4: Insert order items, update stock, create locks and ledger entries
    for (const item of orderItems) {
      // Insert order item
      await client.query(
        `INSERT INTO order_items (order_id, product_id, quantity, unit_price)
         VALUES ($1, $2, $3, $4)`,
        [order.id, item.productId, item.quantity, item.unitPrice]
      );

      const product = productMap[item.productId];
      const newReserved = product.reserved_quantity + item.quantity;
      const newPublicStock = Math.max(0, product.private_stock - product.buffer - newReserved);

      // Update product stock
      await client.query(
        `UPDATE products SET
          reserved_quantity = $1,
          public_stock = $2,
          updated_at = CURRENT_TIMESTAMP
         WHERE id = $3`,
        [newReserved, newPublicStock, item.productId]
      );

      // Create inventory lock
      await client.query(
        `INSERT INTO inventory_locks (product_id, order_id, quantity, status)
         VALUES ($1, $2, $3, 'active')`,
        [item.productId, order.id, item.quantity]
      );

      // Log to inventory ledger
      await client.query(
        `INSERT INTO inventory_ledger
         (product_id, vendor_id, change_type, quantity_change, private_stock_after, public_stock_after, reference_id)
         VALUES ($1, $2, 'reserve', $3, $4, $5, $6)`,
        [item.productId, vendorId, -item.quantity, product.private_stock, newPublicStock, order.id]
      );
    }

    // Create wallet ledger entry for escrow hold
    await client.query(
      `INSERT INTO wallet_ledger (user_id, order_id, transaction_type, amount, balance_after, description)
       VALUES ($1, $2, 'escrow_hold', $3, $4, $5)`,
      [customerId, order.id, totalAmount, newBalance, `Escrow hold for Order #${order.id}`]
    );

    // Step 5: COMMIT transaction
    await client.query('COMMIT');

    res.status(201).json({
      success: true,
      message: 'Order placed successfully! Waiting for vendor approval.',
      data: {
        id: order.id,
        customerId: order.customer_id,
        vendorId: order.vendor_id,
        status: order.status,
        deliveryType: order.delivery_type,
        estimatedMinutes: order.estimated_minutes,
        totalAmount: parseFloat(order.total_amount),
        createdAt: order.created_at,
        escrowStatus: 'held',
        walletBalance: newBalance,
        deliveryFee,
        items: orderItems.map((i) => ({
          productId: i.productId,
          productName: i.productName,
          quantity: i.quantity,
          unitPrice: i.unitPrice,
        })),
      },
    });
  } catch (error) {
    await client.query('ROLLBACK');
    console.error('Checkout error:', error);
    res.status(500).json({ success: false, message: 'Checkout failed. Please try again.' });
  } finally {
    client.release();
  }
};

/**
 * GET /api/customer/orders
 * Get all orders for the authenticated customer.
 */
const getCustomerOrders = async (req, res) => {
  try {
    const customerId = req.user.userId;

    const ordersResult = await pool.query(
      `SELECT o.*, v.store_name
       FROM orders o
       JOIN vendors v ON o.vendor_id = v.id
       WHERE o.customer_id = $1
       ORDER BY o.created_at DESC`,
      [customerId]
    );

    const orders = [];
    for (const order of ordersResult.rows) {
      const itemsResult = await pool.query(
        `SELECT oi.*, p.name as product_name
         FROM order_items oi
         JOIN products p ON oi.product_id = p.id
         WHERE oi.order_id = $1`,
        [order.id]
      );

      orders.push({
        id: order.id,
        vendorId: order.vendor_id,
        storeName: order.store_name,
        status: order.status,
        deliveryType: order.delivery_type,
        estimatedMinutes: order.estimated_minutes,
        totalAmount: parseFloat(order.total_amount),
        escrowStatus: order.status === 'delivered' ? 'released' : 'held',
        cancellationReason: order.cancellation_reason,
        createdAt: order.created_at,
        items: itemsResult.rows.map((item) => ({
          id: item.id,
          productId: item.product_id,
          productName: item.product_name,
          quantity: item.quantity,
          unitPrice: parseFloat(item.unit_price),
        })),
      });
    }

    res.json({ success: true, data: orders });
  } catch (error) {
    console.error('Get customer orders error:', error);
    res.status(500).json({ success: false, message: 'Failed to fetch orders.' });
  }
};

/**
 * Haversine formula to calculate distance (km) between two GPS points
 */
function haversineDistance(lat1, lon1, lat2, lon2) {
  const R = 6371; // Earth radius in km
  const dLat = ((lat2 - lat1) * Math.PI) / 180;
  const dLon = ((lon2 - lon1) * Math.PI) / 180;
  const a =
    Math.sin(dLat / 2) * Math.sin(dLat / 2) +
    Math.cos((lat1 * Math.PI) / 180) * Math.cos((lat2 * Math.PI) / 180) *
    Math.sin(dLon / 2) * Math.sin(dLon / 2);
  const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
  return R * c;
}

/**
 * POST /api/customer/orders/:id/cancel
 * Cancel a pending order and refund escrow.
 */
const cancelOrder = async (req, res) => {
  const client = await pool.connect();
  try {
    const orderId = req.params.id;
    const customerId = req.user.userId;

    await client.query('BEGIN');

    // Get the order
    const orderResult = await client.query(
      `SELECT * FROM orders WHERE id = $1 AND customer_id = $2 AND status = 'pending' FOR UPDATE`,
      [orderId, customerId]
    );

    if (orderResult.rows.length === 0) {
      await client.query('ROLLBACK');
      return res.status(404).json({ success: false, message: 'Order not found or already processed' });
    }

    // Release inventory locks
    const locks = await client.query(
      `SELECT * FROM inventory_locks WHERE order_id = $1 AND status = 'active'`,
      [orderId]
    );

    for (const lock of locks.rows) {
      // Get current product state
      const product = await client.query('SELECT * FROM products WHERE id = $1 FOR UPDATE', [lock.product_id]);
      const p = product.rows[0];
      const newReserved = Math.max(0, p.reserved_quantity - lock.quantity);
      const newPublicStock = Math.max(0, p.private_stock - p.buffer - newReserved);

      // Release stock
      await client.query(
        `UPDATE products SET reserved_quantity = $1, public_stock = $2, updated_at = NOW() WHERE id = $3`,
        [newReserved, newPublicStock, lock.product_id]
      );

      // Mark lock as released
      await client.query(
        `UPDATE inventory_locks SET status = 'released' WHERE id = $1`,
        [lock.id]
      );

      // Log to ledger
      await client.query(
        `INSERT INTO inventory_ledger (product_id, vendor_id, change_type, quantity_change, private_stock_after, public_stock_after, reference_id, notes)
         VALUES ($1, (SELECT vendor_id FROM products WHERE id=$1), 'release', $2, $3, $4, $5, 'Order cancelled by customer')`,
        [lock.product_id, lock.quantity, p.private_stock, newPublicStock, orderId]
      );
    }

    // Cancel the order
    await client.query(
      `UPDATE orders SET status = 'cancelled', cancellation_reason = 'Customer cancelled', updated_at = NOW() WHERE id = $1`,
      [orderId]
    );

    // --- ESCROW REFUND LOGIC START ---
    const order = orderResult.rows[0];
    const totalAmount = parseFloat(order.total_amount);

    await lockEscrowRow(client);
    await debitEscrowPool(client, totalAmount);

    const userWalletRes = await client.query('SELECT wallet_balance FROM users WHERE id = $1 FOR UPDATE', [customerId]);
    const walletBalance = parseFloat(userWalletRes.rows[0].wallet_balance);
    const newBalance = walletBalance + totalAmount;

    await client.query('UPDATE users SET wallet_balance = $1 WHERE id = $2', [newBalance, customerId]);

    await client.query(
      `INSERT INTO wallet_ledger (user_id, order_id, transaction_type, amount, balance_after, description)
       VALUES ($1, $2, 'escrow_refund', $3, $4, $5)`,
      [customerId, orderId, totalAmount, newBalance, `Escrow refund for cancelled Order #${orderId}`]
    );
    // --- ESCROW REFUND LOGIC END ---

    await client.query('COMMIT');

    res.json({ success: true, message: 'Order cancelled successfully. Amount refunded to wallet.' });
  } catch (err) {
    await client.query('ROLLBACK');
    console.error('Cancel order error:', err);
    res.status(500).json({ success: false, message: 'Failed to cancel order.' });
  } finally {
    client.release();
  }
};

/**
 * POST /api/customer/wallet/topup
 * Top up the customer's wallet balance.
 */
const topupWallet = async (req, res) => {
  const client = await pool.connect();
  try {
    const customerId = req.user.userId;
    const { amount } = req.body;
    
    if (!amount || amount <= 0) {
      return res.status(400).json({ success: false, message: 'Invalid top-up amount' });
    }

    await client.query('BEGIN');

    const userWalletRes = await client.query('SELECT wallet_balance FROM users WHERE id = $1 FOR UPDATE', [customerId]);
    const walletBalance = parseFloat(userWalletRes.rows[0].wallet_balance);
    const newBalance = walletBalance + amount;

    await client.query(
      'UPDATE users SET wallet_balance = $1 WHERE id = $2',
      [newBalance, customerId]
    );

    await client.query(
      `INSERT INTO wallet_ledger (user_id, transaction_type, amount, balance_after, description)
       VALUES ($1, 'deposit', $2, $3, $4)`,
      [customerId, amount, newBalance, `Top-up of Rs. ${amount}`]
    );

    await client.query('COMMIT');

    res.json({ success: true, message: 'Wallet topped up successfully.', walletBalance: newBalance });
  } catch (err) {
    await client.query('ROLLBACK');
    console.error('Topup wallet error:', err);
    res.status(500).json({ success: false, message: 'Failed to top up wallet.' });
  } finally {
    client.release();
  }
};

/**
 * POST /api/customer/orders/:id/picked-up
 * Self pickup only — customer confirms they collected items (intermediate step).
 */
const customerMarkPickedUp = async (req, res) => {
  const client = await pool.connect();
  try {
    const orderId = req.params.id;
    const customerId = req.user.userId;

    await client.query('BEGIN');

    const updated = await client.query(
      `UPDATE orders SET status = 'picked', updated_at = NOW()
       WHERE id = $1 AND customer_id = $2 AND delivery_type = 'self_pickup'
         AND status = 'ready_for_pickup'
       RETURNING id`,
      [orderId, customerId]
    );

    if (updated.rows.length === 0) {
      await client.query('ROLLBACK');
      return res.status(400).json({
        success: false,
        message: 'Order not found, not self pickup, or not ready for pickup.',
      });
    }

    await client.query('COMMIT');

    res.json({ success: true, message: 'Marked as picked up.' });
  } catch (err) {
    await client.query('ROLLBACK');
    console.error('customerMarkPickedUp error:', err);
    res.status(500).json({ success: false, message: 'Failed to update order.' });
  } finally {
    client.release();
  }
};

/**
 * POST /api/customer/orders/:id/confirm-received
 * Self pickup — customer confirms completion → delivered + escrow to vendor.
 * Allowed from ready_for_pickup or picked (skip intermediate if desired).
 */
const customerConfirmOrderDelivered = async (req, res) => {
  const client = await pool.connect();
  try {
    const orderId = req.params.id;
    const customerId = req.user.userId;

    await client.query('BEGIN');

    const deliveredUpdate = await client.query(
      `UPDATE orders SET status = 'delivered', updated_at = NOW()
       WHERE id = $1 AND customer_id = $2 AND delivery_type = 'self_pickup'
         AND status IN ('ready_for_pickup', 'picked')
       RETURNING vendor_id`,
      [orderId, customerId]
    );

    if (deliveredUpdate.rows.length === 0) {
      await client.query('ROLLBACK');
      return res.status(400).json({
        success: false,
        message:
          'Cannot confirm delivery for this order. It may not be self pickup, not yours, or not ready yet.',
      });
    }

    const vendorId = deliveredUpdate.rows[0].vendor_id;

    await payoutVendorFromEscrow(
      client,
      orderId,
      vendorId,
      `Customer confirmed pickup complete — Order #${orderId}`
    );

    await client.query('COMMIT');

    res.json({
      success: true,
      message: 'Thank you! Order completed and vendor has been paid.',
    });
  } catch (err) {
    await client.query('ROLLBACK');
    if (err.code === 'ESCROW_POOL_UNDERFLOW') {
      return res.status(409).json({ success: false, message: 'Escrow sync error. Contact support.' });
    }
    console.error('customerConfirmOrderDelivered error:', err);
    res.status(500).json({ success: false, message: 'Failed to complete order.' });
  } finally {
    client.release();
  }
};

module.exports = {
  getProducts,
  getVendorDetails,
  checkout,
  getCustomerOrders,
  cancelOrder,
  topupWallet,
  customerMarkPickedUp,
  customerConfirmOrderDelivered,
};
