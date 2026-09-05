// ══════════════════════════════════════════════════════════════
// Vendra Backend - Vendor Controller
// Handles product CRUD with dual inventory, orders, and ledger
// ══════════════════════════════════════════════════════════════

const pool = require('../db');
const { lockEscrowRow, creditEscrowPool, debitEscrowPool } = require('../services/escrowPool.service');
const { payoutVendorFromEscrow } = require('../services/orderSettlement.service');

// ──────────────────────────────────────
// CREATE PRODUCT
// ──────────────────────────────────────
const createProduct = async (req, res, next) => {
  try {
    const { name, description, price, private_stock, buffer = 5, barcode } = req.body;
    const vendorId = req.user.vendorId;

    if (!vendorId) {
      return res.status(400).json({ success: false, message: 'User is not linked to a vendor account' });
    }

    if (!name || price === undefined || private_stock === undefined) {
      return res.status(400).json({ success: false, message: 'Name, price, and private_stock are required' });
    }

    // Calculate public stock: private - buffer - reserved(0)
    const publicStock = Math.max(0, private_stock - buffer);

    const result = await pool.query(
      `INSERT INTO products (vendor_id, name, description, price, private_stock, public_stock, buffer, barcode)
       VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
       RETURNING *`,
      [vendorId, name, description, price, private_stock, publicStock, buffer, barcode]
    );

    // Log to inventory ledger
    await pool.query(
      `INSERT INTO inventory_ledger (product_id, vendor_id, change_type, quantity_change, private_stock_after, public_stock_after, notes)
       VALUES ($1, $2, 'stock_in', $3, $4, $5, 'Initial stock creation')`,
      [result.rows[0].id, vendorId, private_stock, private_stock, publicStock]
    );

    res.status(201).json({ success: true, data: result.rows[0] });
  } catch (err) {
    next(err);
  }
};

// ──────────────────────────────────────
// GET VENDOR'S PRODUCTS
// ──────────────────────────────────────
const getVendorProducts = async (req, res, next) => {
  try {
    const vendorId = req.user.vendorId;

    const result = await pool.query(
      `SELECT p.*,
              COALESCE(SUM(CASE WHEN il.status = 'active' THEN il.quantity ELSE 0 END), 0) AS active_reserved
       FROM products p
       LEFT JOIN inventory_locks il ON il.product_id = p.id
       WHERE p.vendor_id = $1 AND p.is_active = true
       GROUP BY p.id
       ORDER BY p.created_at DESC`,
      [vendorId]
    );

    // Enrich with store_name
    const vendorResult = await pool.query(
      'SELECT store_name FROM vendors WHERE id = $1', [vendorId]
    );
    const storeName = vendorResult.rows[0]?.store_name || 'My Store';

    const products = result.rows.map(p => ({
      ...p,
      store_name: storeName,
      reserved_quantity: parseInt(p.active_reserved) || 0,
    }));

    res.json({ success: true, data: products });
  } catch (err) {
    next(err);
  }
};

// ──────────────────────────────────────
// UPDATE PRODUCT
// ──────────────────────────────────────
const updateProduct = async (req, res, next) => {
  try {
    const productId = req.params.id;
    const vendorId = req.user.vendorId;
    const { name, description, price, private_stock, buffer, barcode } = req.body;

    // Verify ownership
    const existing = await pool.query(
      'SELECT * FROM products WHERE id = $1 AND vendor_id = $2 AND is_active = true',
      [productId, vendorId]
    );

    if (existing.rows.length === 0) {
      return res.status(404).json({ success: false, message: 'Product not found' });
    }

    const current = existing.rows[0];

    // Calculate new values
    const newPrivateStock = private_stock !== undefined ? private_stock : current.private_stock;
    const newBuffer = buffer !== undefined ? buffer : current.buffer;

    // Get current reserved quantity
    const reservedResult = await pool.query(
      `SELECT COALESCE(SUM(quantity), 0) AS reserved
       FROM inventory_locks WHERE product_id = $1 AND status = 'active'`,
      [productId]
    );
    const reserved = parseInt(reservedResult.rows[0].reserved) || 0;

    // Recalculate public stock
    const newPublicStock = Math.max(0, newPrivateStock - newBuffer - reserved);

    const result = await pool.query(
      `UPDATE products
       SET name = COALESCE($1, name),
           description = COALESCE($2, description),
           price = COALESCE($3, price),
           private_stock = $4,
           public_stock = $5,
           buffer = $6,
           barcode = COALESCE($7, barcode),
           updated_at = NOW()
       WHERE id = $8 AND vendor_id = $9
       RETURNING *`,
      [name, description, price, newPrivateStock, newPublicStock, newBuffer, barcode, productId, vendorId]
    );

    // Log stock change if private_stock was updated
    if (private_stock !== undefined && private_stock !== current.private_stock) {
      const change = private_stock - current.private_stock;
      await pool.query(
        `INSERT INTO inventory_ledger (product_id, vendor_id, change_type, quantity_change, private_stock_after, public_stock_after, notes)
         VALUES ($1, $2, 'stock_in', $3, $4, $5, 'Manual stock update')`,
        [productId, vendorId, change, newPrivateStock, newPublicStock]
      );
    }

    res.json({ success: true, data: result.rows[0] });
  } catch (err) {
    next(err);
  }
};

// ──────────────────────────────────────
// DELETE PRODUCT (Soft Delete)
// ──────────────────────────────────────
const deleteProduct = async (req, res, next) => {
  try {
    const productId = req.params.id;
    const vendorId = req.user.vendorId;

    const result = await pool.query(
      `UPDATE products SET is_active = false, updated_at = NOW()
       WHERE id = $1 AND vendor_id = $2
       RETURNING id`,
      [productId, vendorId]
    );

    if (result.rows.length === 0) {
      return res.status(404).json({ success: false, message: 'Product not found' });
    }

    res.json({ success: true, message: 'Product deleted' });
  } catch (err) {
    next(err);
  }
};

// ──────────────────────────────────────
// GET VENDOR'S ORDERS
// ──────────────────────────────────────
const getVendorOrders = async (req, res, next) => {
  try {
    const vendorId = req.user.vendorId;

    const result = await pool.query(
      `SELECT o.*,
              u.full_name AS customer_name,
              v.store_name,
              json_agg(json_build_object(
                'id', oi.id,
                'product_id', oi.product_id,
                'product_name', p.name,
                'quantity', oi.quantity,
                'unit_price', oi.unit_price,
                'subtotal', COALESCE(oi.subtotal, oi.unit_price * oi.quantity)
              )) AS items
       FROM orders o
       JOIN users u ON u.id = o.customer_id
       JOIN vendors v ON v.id = o.vendor_id
       JOIN order_items oi ON oi.order_id = o.id
       JOIN products p ON p.id = oi.product_id
       WHERE o.vendor_id = $1
       GROUP BY o.id, u.full_name, v.store_name
       ORDER BY o.created_at DESC`,
      [vendorId]
    );

    res.json({ success: true, data: result.rows });
  } catch (err) {
    next(err);
  }
};

// ──────────────────────────────────────
// APPROVE ORDER (vendor confirms)
// ──────────────────────────────────────
const approveOrder = async (req, res, next) => {
  try {
    const orderId = req.params.id;
    const vendorId = req.user.vendorId;

    const result = await pool.query(
      `UPDATE orders SET status = 'confirmed', updated_at = NOW()
       WHERE id = $1 AND vendor_id = $2 AND status = 'pending'
       RETURNING *`,
      [orderId, vendorId]
    );

    if (result.rows.length === 0) {
      return res.status(404).json({ success: false, message: 'Order not found or already processed' });
    }

    res.json({ success: true, message: 'Order approved!', data: result.rows[0] });
  } catch (err) {
    next(err);
  }
};

// ──────────────────────────────────────
// REJECT ORDER (vendor declines)
// ──────────────────────────────────────
const rejectOrder = async (req, res, next) => {
  const client = await pool.connect();
  try {
    const orderId = req.params.id;
    const vendorId = req.user.vendorId;

    await client.query('BEGIN');

    // Get the order
    const orderResult = await client.query(
      `SELECT * FROM orders WHERE id = $1 AND vendor_id = $2 AND status = 'pending' FOR UPDATE`,
      [orderId, vendorId]
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
         VALUES ($1, $2, 'release', $3, $4, $5, $6, 'Order rejected by vendor')`,
        [lock.product_id, vendorId, lock.quantity, p.private_stock, newPublicStock, orderId]
      );
    }

    // Cancel the order
    await client.query(
      `UPDATE orders SET status = 'cancelled', cancellation_reason = 'Vendor cancelled', updated_at = NOW() WHERE id = $1`,
      [orderId]
    );

    // --- ESCROW REFUND LOGIC START ---
    const order = orderResult.rows[0];
    const customerId = order.customer_id;
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
      [customerId, orderId, totalAmount, newBalance, `Escrow refund for rejected Order #${orderId}`]
    );
    // --- ESCROW REFUND LOGIC END ---

    await client.query('COMMIT');

    res.json({ success: true, message: 'Order rejected. Stock has been released.' });
  } catch (err) {
    await client.query('ROLLBACK');
    next(err);
  } finally {
    client.release();
  }
};

// ──────────────────────────────────────
// UPDATE VENDOR LOCATION
// ──────────────────────────────────────
const updateVendorLocation = async (req, res, next) => {
  try {
    const vendorId = req.user.vendorId;
    const { latitude, longitude, storeAddress } = req.body;

    if (!latitude || !longitude) {
      return res.status(400).json({ success: false, message: 'Latitude and longitude are required' });
    }

    const result = await pool.query(
      `UPDATE vendors SET latitude = $1, longitude = $2, store_address = COALESCE($3, store_address)
       WHERE id = $4 RETURNING *`,
      [latitude, longitude, storeAddress || null, vendorId]
    );

    res.json({ success: true, message: 'Location updated', data: result.rows[0] });
  } catch (err) {
    next(err);
  }
};

// ──────────────────────────────────────
// GET INVENTORY LEDGER
// ──────────────────────────────────────
const getInventoryLedger = async (req, res, next) => {
  try {
    const vendorId = req.user.vendorId;

    const result = await pool.query(
      `SELECT il.*, p.name AS product_name
       FROM inventory_ledger il
       JOIN products p ON p.id = il.product_id
       WHERE il.vendor_id = $1
       ORDER BY il.created_at DESC
       LIMIT 100`,
      [vendorId]
    );

    res.json({ success: true, data: result.rows });
  } catch (err) {
    next(err);
  }
};

// ──────────────────────────────────────
// MARK ORDER AS PREPARING (confirmed → packed)
// ──────────────────────────────────────
const markOrderPreparing = async (req, res, next) => {
  try {
    const vendorId = req.user.vendorId;
    const orderId = req.params.id;

    const result = await pool.query(
      `UPDATE orders SET status = 'packed', updated_at = NOW()
       WHERE id = $1 AND vendor_id = $2 AND status = 'confirmed'
       RETURNING *`,
      [orderId, vendorId]
    );

    if (result.rows.length === 0) {
      return res.status(404).json({ success: false, message: 'Order not found or not in confirmed state' });
    }

    res.json({ success: true, message: 'Order marked as preparing.', data: result.rows[0] });
  } catch (err) {
    next(err);
  }
};

// ──────────────────────────────────────
// MARK READY FOR PICKUP (does NOT release escrow — settlement on delivered / rider flow)
// ──────────────────────────────────────
const markOrderReadyForPickup = async (req, res, next) => {
  try {
    const vendorId = req.user.vendorId;
    const orderId = req.params.id;

    const result = await pool.query(
      `UPDATE orders SET status = 'ready_for_pickup', updated_at = NOW()
       WHERE id = $1 AND vendor_id = $2 AND status = 'packed'
       RETURNING *`,
      [orderId, vendorId]
    );

    if (result.rows.length === 0) {
      return res.status(404).json({
        success: false,
        message: 'Order not found or not in preparing state.',
      });
    }

    res.json({
      success: true,
      message: 'Order marked ready for pickup. Customer will confirm collection when applicable.',
      data: result.rows[0],
    });
  } catch (err) {
    next(err);
  }
};

// ──────────────────────────────────────
// MARK DELIVERED — Self pickup ONLY (releases escrow). Hidden/disabled for delivery orders.
// ──────────────────────────────────────
const markVendorOrderDelivered = async (req, res, next) => {
  const client = await pool.connect();
  try {
    const vendorId = req.user.vendorId;
    const orderId = req.params.id;

    await client.query('BEGIN');

    const deliveredUpdate = await client.query(
      `UPDATE orders SET status = 'delivered', updated_at = NOW()
       WHERE id = $1 AND vendor_id = $2 AND delivery_type = 'self_pickup'
         AND status IN ('ready_for_pickup', 'picked')
       RETURNING id`,
      [orderId, vendorId]
    );

    if (deliveredUpdate.rows.length === 0) {
      await client.query('ROLLBACK');
      return res.status(400).json({
        success: false,
        message:
          'Mark as Delivered is only available for self pickup orders in Ready or Picked-up state.',
      });
    }

    await payoutVendorFromEscrow(
      client,
      orderId,
      vendorId,
      `Vendor confirmed delivered — Self pickup Order #${orderId}`
    );

    await client.query('COMMIT');

    res.json({
      success: true,
      message: 'Order marked delivered. Funds released to your wallet.',
    });
  } catch (err) {
    await client.query('ROLLBACK');
    if (err.code === 'ESCROW_POOL_UNDERFLOW') {
      return res.status(409).json({
        success: false,
        message: 'Escrow pool out of sync. Contact support.',
      });
    }
    if (err.statusCode === 404) {
      return res.status(404).json({ success: false, message: err.message });
    }
    next(err);
  } finally {
    client.release();
  }
};

module.exports = {
  createProduct,
  getVendorProducts,
  updateProduct,
  deleteProduct,
  getVendorOrders,
  approveOrder,
  rejectOrder,
  markOrderPreparing,
  markOrderReadyForPickup,
  markVendorOrderDelivered,
  updateVendorLocation,
  getInventoryLedger,
};
