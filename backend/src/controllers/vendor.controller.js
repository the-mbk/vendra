// ══════════════════════════════════════════════════════════════
// Vendra Backend - Vendor Controller
// Products (dual inventory), walk-in POS sales, order workflow, ledger
// Responses keep the snake_case row shape the vendor app already parses.
// ══════════════════════════════════════════════════════════════

const pool = require('../db');
const { lockProducts, applyStockChange, releaseOrderLocks, consumeOrderLocks, computePublicStock } = require('../services/inventory.service');
const { refundEscrow, scheduleEscrowRelease } = require('../services/orderSettlement.service');
const { announceOrder, notify, notifyAdmins } = require('../services/notification.service');
const { getPolicies } = require('../services/policy.service');
const { emitToRiders, emitStock, broadcast } = require('../realtime');
const { httpError, asyncHandler, withTransaction, intParam, paging, pageOf } = require('../utils/http');
const { productImageUrl, removeProductImage } = require('../services/storage.service');
const { verifyHandoverOtp, withHandoverOtp } = require('../services/handoverOtp.service');
const { formatReview } = require('../services/review.service');
const { haversineKm, isValidCoordinate } = require('../utils/geo');
const { toPaisa, paisaToString, paisaToNumber } = require('../utils/money');

const MAX_GALLERY_PHOTOS = 5; // besides the cover photo

function vendorIdOf(req) {
  if (!req.user.vendorId) throw httpError(400, 'User is not linked to a vendor account.');
  return req.user.vendorId;
}

/** The staff member behind this request, or null for the store owner */
const staffIdOf = (req) => req.user.staff?.id ?? null;

function wholeNumber(value, field, { min = 0 } = {}) {
  const n = Number(value);
  if (!Number.isInteger(n) || n < min) throw httpError(400, `${field} must be a whole number of at least ${min}.`);
  return n;
}

async function assertCategory(db, categoryId) {
  if (categoryId == null || categoryId === '') return null;
  const id = intParam(categoryId, 'category_id');
  const r = await db.query('SELECT id FROM categories WHERE id = $1', [id]);
  if (r.rows.length === 0) throw httpError(400, 'Unknown category.');
  return id;
}

const PRODUCT_SELECT = `
  SELECT p.*, c.name AS category_name, v.store_name,
         CASE WHEN p.rating_count > 0 THEN ROUND(p.rating_sum::numeric / p.rating_count, 1)::float8 END AS average_rating,
         COALESCE((SELECT json_agg(json_build_object('id', pi.id, 'url', pi.url) ORDER BY pi.position, pi.id)
                   FROM product_images pi WHERE pi.product_id = p.id), '[]') AS gallery
  FROM products p
  JOIN vendors v ON v.id = p.vendor_id
  LEFT JOIN categories c ON c.id = p.category_id`;

// ──────────────────────────────────────
// PRODUCTS
// ──────────────────────────────────────

/** POST /api/vendor/products  Body: { name, description, price, private_stock, buffer?, barcode?, category_id? } */
const createProduct = asyncHandler(async (req, res) => {
  const vendorId = vendorIdOf(req);
  const { name, description, barcode } = req.body;
  const price = Number(req.body.price);

  if (!name || !Number.isFinite(price) || price < 0 || req.body.private_stock === undefined) {
    throw httpError(400, 'Name, a valid price and private_stock are required.');
  }
  const privateStock = wholeNumber(req.body.private_stock, 'private_stock');

  const product = await withTransaction(async (client, afterCommit) => {
    const policies = await getPolicies(client);
    const buffer = req.body.buffer === undefined || req.body.buffer === null
      ? policies.default_buffer
      : wholeNumber(req.body.buffer, 'buffer');
    const categoryId = await assertCategory(client, req.body.category_id);
    const isApproved = policies.auto_approve_products >= 1;
    const publicStock = computePublicStock({ private_stock: privateStock, buffer, reserved_quantity: 0 });

    const inserted = (await client.query(
      `INSERT INTO products (vendor_id, name, description, price, private_stock, public_stock, buffer, barcode, category_id, is_approved)
       VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10)
       RETURNING *`,
      [vendorId, name, description || null, paisaToString(toPaisa(price)), privateStock, publicStock, buffer,
        barcode || null, categoryId, isApproved]
    )).rows[0];

    await client.query(
      `INSERT INTO inventory_ledger (product_id, vendor_id, change_type, quantity_change, private_stock_after, public_stock_after, notes)
       VALUES ($1, $2, 'stock_in', $3, $4, $5, 'Initial stock')`,
      [inserted.id, vendorId, privateStock, privateStock, publicStock]
    );

    if (!isApproved) {
      await notifyAdmins(client, afterCommit, {
        type: 'product_pending',
        title: 'Product awaiting approval',
        body: `"${name}" needs review before it appears in the marketplace.`,
      });
    }
    afterCommit.push(() => emitStock(inserted));
    return (await client.query(`${PRODUCT_SELECT} WHERE p.id = $1`, [inserted.id])).rows[0];
  });

  res.status(201).json({
    success: true,
    message: product.is_approved ? 'Product added.' : 'Product added. It will appear to customers once an admin approves it.',
    data: product,
  });
});

/** GET /api/vendor/products */
const getVendorProducts = asyncHandler(async (req, res) => {
  const vendorId = vendorIdOf(req);
  const r = await pool.query(
    `${PRODUCT_SELECT} WHERE p.vendor_id = $1 AND p.is_active = true ORDER BY p.created_at DESC`,
    [vendorId]
  );
  res.json({ success: true, data: r.rows });
});

/** GET /api/vendor/products/barcode/:code — POS / stock-in scan lookup */
const getProductByBarcode = asyncHandler(async (req, res) => {
  const vendorId = vendorIdOf(req);
  const r = await pool.query(
    `${PRODUCT_SELECT} WHERE p.vendor_id = $1 AND p.barcode = $2 AND p.is_active = true LIMIT 1`,
    [vendorId, req.params.code]
  );
  if (r.rows.length === 0) throw httpError(404, `No product with barcode ${req.params.code} in your store.`);
  res.json({ success: true, data: r.rows[0] });
});

/**
 * PUT /api/vendor/products/:id
 * Locks the row so a concurrent checkout can't be overwritten with stale numbers.
 */
const updateProduct = asyncHandler(async (req, res) => {
  const vendorId = vendorIdOf(req);
  const productId = intParam(req.params.id);
  const { name, description, barcode } = req.body;

  const product = await withTransaction(async (client, afterCommit) => {
    const current = (await lockProducts(client, [productId])).get(productId);
    if (!current || current.vendor_id !== vendorId || !current.is_active) throw httpError(404, 'Product not found');

    const privateStock = req.body.private_stock !== undefined ? wholeNumber(req.body.private_stock, 'private_stock') : current.private_stock;
    const buffer = req.body.buffer !== undefined ? wholeNumber(req.body.buffer, 'buffer') : current.buffer;
    if (privateStock < current.reserved_quantity) {
      throw httpError(409, `Stock can't go below ${current.reserved_quantity} — those units are reserved for online orders.`, {
        code: 'BELOW_RESERVED', reserved: current.reserved_quantity,
      });
    }

    let price = null;
    if (req.body.price !== undefined) {
      price = Number(req.body.price);
      if (!Number.isFinite(price) || price < 0) throw httpError(400, 'Price must be a positive number.');
      price = paisaToString(toPaisa(price));
    }
    const categoryId = req.body.category_id !== undefined ? await assertCategory(client, req.body.category_id) : current.category_id;

    await client.query(
      `UPDATE products SET name = COALESCE($1, name), description = COALESCE($2, description),
              price = COALESCE($3, price), barcode = COALESCE($4, barcode), category_id = $5
       WHERE id = $6`,
      [name || null, description ?? null, price, barcode || null, categoryId, productId]
    );

    const change = privateStock - current.private_stock;
    await applyStockChange(client, afterCommit, current, {
      privateStock,
      buffer,
      ledger: change !== 0
        ? { type: change > 0 ? 'stock_in' : 'adjustment', quantityChange: change, notes: 'Manual stock update' }
        : undefined,
    });

    return (await client.query(`${PRODUCT_SELECT} WHERE p.id = $1`, [productId])).rows[0];
  });

  res.json({ success: true, data: product });
});

/** DELETE /api/vendor/products/:id — soft delete, refused while units are reserved */
const deleteProduct = asyncHandler(async (req, res) => {
  const vendorId = vendorIdOf(req);
  const productId = intParam(req.params.id);

  await withTransaction(async (client, afterCommit) => {
    const p = (await lockProducts(client, [productId])).get(productId);
    if (!p || p.vendor_id !== vendorId || !p.is_active) throw httpError(404, 'Product not found');
    if (p.reserved_quantity > 0) {
      throw httpError(409, `This product has ${p.reserved_quantity} unit(s) reserved for open orders. Finish those orders first.`);
    }
    const r = await client.query(
      `UPDATE products SET is_active = false, public_stock = 0, updated_at = NOW() WHERE id = $1 RETURNING *`,
      [productId]
    );
    afterCommit.push(() => emitStock(r.rows[0]));
  });

  res.json({ success: true, message: 'Product deleted' });
});

/** POST /api/vendor/products/:id/image  (multipart, field "image") — replaces any existing photo */
const uploadProductImage = asyncHandler(async (req, res) => {
  const vendorId = vendorIdOf(req);
  const productId = intParam(req.params.id);
  if (!req.file) throw httpError(400, 'Attach a photo in the "image" field.');

  let old;
  try {
    const r = await pool.query(
      `UPDATE products p SET image_url = $1, updated_at = NOW()
       FROM (SELECT image_url AS old_url FROM products WHERE id = $2 AND vendor_id = $3 AND is_active FOR NO KEY UPDATE) prev
       WHERE p.id = $2 RETURNING prev.old_url`,
      [productImageUrl(req.file), productId, vendorId]
    );
    if (r.rows.length === 0) throw httpError(404, 'Product not found');
    old = r.rows[0].old_url;
  } catch (err) {
    removeProductImage(productImageUrl(req.file));
    throw err;
  }
  removeProductImage(old);

  const product = (await pool.query(`${PRODUCT_SELECT} WHERE p.id = $1`, [productId])).rows[0];
  broadcast('catalog:update', { productId, vendorId });
  res.json({ success: true, message: 'Photo updated.', data: product });
});

/** DELETE /api/vendor/products/:id/image */
const deleteProductImage = asyncHandler(async (req, res) => {
  const vendorId = vendorIdOf(req);
  const productId = intParam(req.params.id);
  const r = await pool.query(
    `UPDATE products p SET image_url = NULL, updated_at = NOW()
     FROM (SELECT image_url AS old_url FROM products WHERE id = $1 AND vendor_id = $2 AND is_active FOR NO KEY UPDATE) prev
     WHERE p.id = $1 RETURNING prev.old_url`,
    [productId, vendorId]
  );
  if (r.rows.length === 0) throw httpError(404, 'Product not found');
  removeProductImage(r.rows[0].old_url);
  broadcast('catalog:update', { productId, vendorId });
  res.json({ success: true, message: 'Photo removed.' });
});

/** POST /api/vendor/products/:id/images  (multipart, field "image") — adds a gallery photo after the cover */
const addGalleryImage = asyncHandler(async (req, res) => {
  const vendorId = vendorIdOf(req);
  const productId = intParam(req.params.id);
  if (!req.file) throw httpError(400, 'Attach a photo in the "image" field.');
  const url = productImageUrl(req.file);

  try {
    await withTransaction(async (client) => {
      const p = await client.query('SELECT id FROM products WHERE id = $1 AND vendor_id = $2 AND is_active FOR NO KEY UPDATE', [productId, vendorId]);
      if (p.rows.length === 0) throw httpError(404, 'Product not found');
      const n = (await client.query('SELECT COUNT(*)::int AS n, COALESCE(MAX(position), -1) AS last FROM product_images WHERE product_id = $1', [productId])).rows[0];
      if (n.n >= MAX_GALLERY_PHOTOS) throw httpError(409, `A product can have up to ${MAX_GALLERY_PHOTOS} extra photos besides the cover.`);
      await client.query('INSERT INTO product_images (product_id, url, position) VALUES ($1, $2, $3)', [productId, url, n.last + 1]);
      // The first photo of a product without a cover becomes the cover
      await client.query('UPDATE products SET image_url = COALESCE(image_url, $1), updated_at = NOW() WHERE id = $2', [url, productId]);
    });
  } catch (err) {
    removeProductImage(url);
    throw err;
  }

  const product = (await pool.query(`${PRODUCT_SELECT} WHERE p.id = $1`, [productId])).rows[0];
  broadcast('catalog:update', { productId, vendorId });
  res.status(201).json({ success: true, message: 'Photo added to the gallery.', data: product });
});

/** DELETE /api/vendor/products/:id/images/:imageId */
const deleteGalleryImage = asyncHandler(async (req, res) => {
  const vendorId = vendorIdOf(req);
  const productId = intParam(req.params.id);
  const r = await pool.query(
    `DELETE FROM product_images pi USING products p
     WHERE pi.id = $1 AND pi.product_id = $2 AND p.id = pi.product_id AND p.vendor_id = $3
     RETURNING pi.url`,
    [intParam(req.params.imageId, 'imageId'), productId, vendorId]
  );
  if (r.rows.length === 0) throw httpError(404, 'Photo not found.');
  // The cover may point at the same file; keep it if so
  const stillCover = await pool.query('SELECT 1 FROM products WHERE id = $1 AND image_url = $2', [productId, r.rows[0].url]);
  if (stillCover.rows.length === 0) removeProductImage(r.rows[0].url);
  const product = (await pool.query(`${PRODUCT_SELECT} WHERE p.id = $1`, [productId])).rows[0];
  broadcast('catalog:update', { productId, vendorId });
  res.json({ success: true, message: 'Photo removed.', data: product });
});

/** GET /api/vendor/reviews?limit=&offset= — what customers say about this store's products */
const getVendorReviews = asyncHandler(async (req, res) => {
  const vendorId = vendorIdOf(req);
  const page = paging(req.query);
  const [r, summary] = await Promise.all([
    pool.query(
      `SELECT pr.id, pr.order_id, pr.product_id, p.name AS product_name, pr.rating, pr.comment, pr.created_at,
              u.full_name AS customer_name
       FROM product_reviews pr JOIN products p ON p.id = pr.product_id JOIN users u ON u.id = pr.customer_id
       WHERE pr.vendor_id = $1 ORDER BY pr.created_at DESC, pr.id DESC LIMIT $2 OFFSET $3`,
      [vendorId, page.limit + 1, page.offset]
    ),
    pool.query(
      `SELECT COUNT(*)::int AS count, ROUND(AVG(rating), 1)::float8 AS average FROM product_reviews WHERE vendor_id = $1`,
      [vendorId]
    ),
  ]);
  const { items, meta } = pageOf(r.rows, page);
  res.json({
    success: true,
    data: items.map(formatReview),
    meta: { ...meta, count: summary.rows[0].count, average: summary.rows[0].average },
  });
});

// ──────────────────────────────────────
// WALK-IN POS SALES (FR01 / FR02)
// ──────────────────────────────────────

/**
 * POST /api/vendor/pos/sales  Body: { items: [{ productId, quantity }] }
 * A cashier may sell from the buffer, but never units reserved for online orders:
 *   sellable = private_stock − reserved_quantity
 */
const createPosSale = asyncHandler(async (req, res) => {
  const vendorId = vendorIdOf(req);
  const items = req.body.items;
  if (!Array.isArray(items) || items.length === 0) throw httpError(400, 'Add at least one item to the sale.');

  const merged = new Map();
  for (const item of items) {
    const productId = intParam(item?.productId, 'productId');
    merged.set(productId, (merged.get(productId) || 0) + wholeNumber(item?.quantity, 'quantity', { min: 1 }));
  }

  const sale = await withTransaction(async (client, afterCommit) => {
    const products = await lockProducts(client, [...merged.keys()]);
    let total = 0;
    const lines = [];

    for (const [productId, quantity] of merged) {
      const p = products.get(productId);
      if (!p || p.vendor_id !== vendorId || !p.is_active) throw httpError(404, `Product ${productId} not found in your store.`);
      const sellable = p.private_stock - p.reserved_quantity;
      if (quantity > sellable) {
        throw httpError(409,
          p.reserved_quantity > 0
            ? `Only ${Math.max(0, sellable)} "${p.name}" can be sold — ${p.reserved_quantity} are reserved for online orders.`
            : `Only ${Math.max(0, sellable)} "${p.name}" in stock.`,
          { code: 'RESERVED_STOCK', productId, sellable: Math.max(0, sellable), reserved: p.reserved_quantity });
      }
      const unit = toPaisa(p.price);
      total += unit * quantity;
      lines.push({ product: p, quantity, unit });
    }

    const saleRow = (await client.query(
      `INSERT INTO pos_sales (vendor_id, cashier_user_id, staff_id, total_amount) VALUES ($1, $2, $3, $4) RETURNING *`,
      [vendorId, req.user.userId, staffIdOf(req), paisaToString(total)]
    )).rows[0];

    const soldItems = [];
    for (const line of lines) {
      await client.query(
        `INSERT INTO pos_sale_items (sale_id, product_id, quantity, unit_price) VALUES ($1, $2, $3, $4)`,
        [saleRow.id, line.product.id, line.quantity, paisaToString(line.unit)]
      );
      const updated = await applyStockChange(client, afterCommit, line.product, {
        privateStock: line.product.private_stock - line.quantity,
        ledger: { type: 'pos_sale', quantityChange: -line.quantity, referenceId: saleRow.id, notes: `Walk-in sale #${saleRow.id}` },
      });
      soldItems.push({
        product_id: updated.id,
        product_name: updated.name,
        quantity: line.quantity,
        unit_price: paisaToNumber(line.unit),
        private_stock_after: updated.private_stock,
        public_stock_after: updated.public_stock,
        reserved_quantity: updated.reserved_quantity,
      });
    }

    return { id: saleRow.id, total_amount: paisaToNumber(total), created_at: saleRow.created_at, items: soldItems };
  });

  sale.receipt = await receiptFor(pool, vendorId, sale.id);
  res.status(201).json({ success: true, message: `Sale #${sale.id} completed.`, data: sale });
});

const SALE_SELECT = `
  SELECT s.id, s.total_amount::float8 AS total_amount, s.created_at,
         COALESCE(st.full_name, cu.full_name) AS cashier_name, st.role AS cashier_role,
         json_agg(json_build_object('product_id', i.product_id, 'product_name', p.name, 'barcode', p.barcode,
                  'quantity', i.quantity, 'unit_price', i.unit_price::float8) ORDER BY i.id) AS items
  FROM pos_sales s
  JOIN pos_sale_items i ON i.sale_id = s.id
  JOIN products p ON p.id = i.product_id
  LEFT JOIN vendor_staff st ON st.id = s.staff_id
  LEFT JOIN users cu ON cu.id = s.cashier_user_id`;

/** Everything a printed slip needs: store header/footer, payment QR account, who rang it up */
async function receiptFor(db, vendorId, saleId) {
  const [store, sale] = await Promise.all([
    db.query(
      `SELECT v.store_name, v.store_address, v.receipt_header, v.receipt_footer, v.payment_account, v.payment_account_title,
              u.phone FROM vendors v JOIN users u ON u.id = v.user_id WHERE v.id = $1`,
      [vendorId]
    ),
    db.query(`${SALE_SELECT} WHERE s.id = $1 AND s.vendor_id = $2 GROUP BY s.id, st.id, cu.id`, [saleId, vendorId]),
  ]);
  const v = store.rows[0];
  const s = sale.rows[0];
  if (!s) return null;
  return {
    receipt_number: `POS-${String(s.id).padStart(6, '0')}`,
    store: {
      name: v.store_name,
      address: v.store_address,
      phone: v.phone,
      header: v.receipt_header,
      footer: v.receipt_footer || 'Thank you for shopping with us!',
    },
    sale: s,
    cashier: s.cashier_name,
    // Scan-to-pay: the QR on the slip carries the store's account and the amount
    payment_qr: v.payment_account
      ? {
          account: v.payment_account,
          title: v.payment_account_title || v.store_name,
          payload: `vendra-pay:${encodeURIComponent(v.payment_account)}?name=${encodeURIComponent(v.payment_account_title || v.store_name)}`
            + `&amount=${s.total_amount.toFixed(2)}&ref=POS-${s.id}`,
        }
      : null,
  };
}

/** GET /api/vendor/pos/sales — today's walk-in sales + totals */
const getPosSales = asyncHandler(async (req, res) => {
  const vendorId = vendorIdOf(req);
  const r = await pool.query(
    `${SALE_SELECT}
     WHERE s.vendor_id = $1 AND s.created_at::date = CURRENT_DATE
     GROUP BY s.id, st.id, cu.id
     ORDER BY s.created_at DESC`,
    [vendorId]
  );
  const todayTotal = r.rows.reduce((sum, s) => sum + toPaisa(s.total_amount), 0);
  res.json({
    success: true,
    data: { sales: r.rows, today_count: r.rows.length, today_total: paisaToNumber(todayTotal) },
  });
});

/** GET /api/vendor/pos/sales/:id — one sale with its receipt (reprint / share) */
const getPosSale = asyncHandler(async (req, res) => {
  const receipt = await receiptFor(pool, vendorIdOf(req), intParam(req.params.id));
  if (!receipt) throw httpError(404, 'Sale not found.');
  res.json({ success: true, data: receipt });
});

const RECEIPT_FIELDS = {
  receiptHeader: ['receipt_header', 200],
  receiptFooter: ['receipt_footer', 200],
  paymentAccount: ['payment_account', 60],
  paymentAccountTitle: ['payment_account_title', 100],
};

function receiptSettingsView(v) {
  return {
    receiptHeader: v.receipt_header,
    receiptFooter: v.receipt_footer,
    paymentAccount: v.payment_account,
    paymentAccountTitle: v.payment_account_title,
  };
}

/** GET /api/vendor/receipt-settings */
const getReceiptSettings = asyncHandler(async (req, res) => {
  const r = await pool.query('SELECT * FROM vendors WHERE id = $1', [vendorIdOf(req)]);
  res.json({ success: true, data: receiptSettingsView(r.rows[0]) });
});

/** PUT /api/vendor/receipt-settings  Body: { receiptHeader?, receiptFooter?, paymentAccount?, paymentAccountTitle? } ('' clears) */
const updateReceiptSettings = asyncHandler(async (req, res) => {
  const sets = [];
  const params = [];
  for (const [field, [column, max]] of Object.entries(RECEIPT_FIELDS)) {
    if (req.body[field] === undefined) continue;
    const value = req.body[field] === null ? '' : String(req.body[field]).trim();
    if (value.length > max) throw httpError(400, `${field} must be at most ${max} characters.`);
    params.push(value || null);
    sets.push(`${column} = $${params.length}`);
  }
  if (sets.length === 0) throw httpError(400, 'Nothing to update.');
  params.push(vendorIdOf(req));
  const r = await pool.query(`UPDATE vendors SET ${sets.join(', ')} WHERE id = $${params.length} RETURNING *`, params);
  res.json({ success: true, message: 'Receipt settings saved.', data: receiptSettingsView(r.rows[0]) });
});

// ──────────────────────────────────────
// ORDERS (FR07 pick → pack → ready)
// ──────────────────────────────────────

const VENDOR_ORDER_SELECT = `
  SELECT o.*,
         u.full_name AS customer_name, u.phone AS customer_phone,
         v.store_name,
         rd.full_name AS rider_name, rd.phone AS rider_phone,
         (SELECT json_build_object('id', d.id, 'status', d.status, 'resolution', d.resolution, 'issue_type', d.issue_type)
            FROM disputes d WHERE d.order_id = o.id ORDER BY d.created_at DESC LIMIT 1) AS latest_dispute,
         (SELECT json_agg(json_build_object(
             'id', oi.id, 'product_id', oi.product_id, 'product_name', p.name,
             'quantity', oi.quantity, 'unit_price', oi.unit_price, 'image_url', p.image_url,
             'barcode', p.barcode, 'packed_quantity', oi.packed_quantity,
             'subtotal', COALESCE(oi.subtotal, oi.unit_price * oi.quantity)) ORDER BY oi.id)
            FROM order_items oi JOIN products p ON p.id = oi.product_id WHERE oi.order_id = o.id) AS items,
         pk.full_name AS packed_by_name
  FROM orders o
  JOIN users u ON u.id = o.customer_id
  JOIN vendors v ON v.id = o.vendor_id
  LEFT JOIN users rd ON rd.id = o.rider_user_id
  LEFT JOIN vendor_staff pk ON pk.id = o.packed_by_staff_id`;

const FINAL_STATUSES = ['delivered', 'cancelled'];

/** The handover code is the customer's alone: never send it (or its counters) to the store */
function vendorOrderView(o) {
  if (!o) return o;
  const { delivery_otp: _otp, otp_failed_attempts: _tries, otp_locked_until: _lock, ...rest } = o;
  return { ...rest, otp_required: Boolean(_otp) && !o.otp_verified_at };
}

/**
 * GET /api/vendor/orders?scope=active|history|all&limit=&offset=
 *   active  — every order still in progress (no paging; the working set)
 *   history — delivered/cancelled, newest first, paginated
 *   all     — everything, newest first, paginated (default)
 */
const getVendorOrders = asyncHandler(async (req, res) => {
  const vendorId = vendorIdOf(req);
  const scope = ['active', 'history'].includes(req.query.scope) ? req.query.scope : 'all';

  if (scope === 'active') {
    const r = await pool.query(
      `${VENDOR_ORDER_SELECT} WHERE o.vendor_id = $1 AND NOT (o.status = ANY($2::order_status[]))
       ORDER BY o.created_at DESC, o.id DESC`,
      [vendorId, FINAL_STATUSES]
    );
    return res.json({ success: true, data: r.rows.map(vendorOrderView), meta: { scope, hasMore: false, nextOffset: null } });
  }

  const page = paging(req.query, { defaultLimit: 30 });
  const statusFilter = scope === 'history' ? 'AND o.status = ANY($4::order_status[])' : '';
  const params = [vendorId, page.limit + 1, page.offset];
  if (scope === 'history') params.push(FINAL_STATUSES);
  const r = await pool.query(
    `${VENDOR_ORDER_SELECT} WHERE o.vendor_id = $1 ${statusFilter}
     ORDER BY o.created_at DESC, o.id DESC LIMIT $2 OFFSET $3`,
    params
  );
  const { items, meta } = pageOf(r.rows, page);
  res.json({ success: true, data: items.map(vendorOrderView), meta: { scope, ...meta } });
});

/** GET /api/vendor/orders/:id — one order (refresh after an order:update event) */
const getVendorOrder = asyncHandler(async (req, res) => {
  const vendorId = vendorIdOf(req);
  const r = await pool.query(`${VENDOR_ORDER_SELECT} WHERE o.id = $1 AND o.vendor_id = $2`, [intParam(req.params.id), vendorId]);
  if (r.rows.length === 0) throw httpError(404, 'Order not found.');
  res.json({ success: true, data: vendorOrderView(r.rows[0]) });
});

/** Moves an order from one status to the next, or throws 404/409 */
async function transition(client, orderId, vendorId, from, to, extraSet = '') {
  const r = await client.query(
    `UPDATE orders SET status = $1, updated_at = NOW() ${extraSet}
     WHERE id = $2 AND vendor_id = $3 AND status = $4
     RETURNING *`,
    [to, orderId, vendorId, from]
  );
  if (r.rows.length === 0) {
    const exists = await client.query('SELECT status FROM orders WHERE id = $1 AND vendor_id = $2', [orderId, vendorId]);
    if (exists.rows.length === 0) throw httpError(404, 'Order not found.');
    throw httpError(409, `Order is ${exists.rows[0].status}, expected ${from}.`);
  }
  return r.rows[0];
}

/** PUT /api/vendor/orders/:id/approve — pending → confirmed */
const approveOrder = asyncHandler(async (req, res) => {
  const vendorId = vendorIdOf(req);
  const orderId = intParam(req.params.id);
  const order = await withTransaction(async (client, afterCommit) => {
    const o = await transition(client, orderId, vendorId, 'pending', 'confirmed');
    await announceOrder(client, afterCommit, orderId, 'order_confirmed', {
      customer: { title: `Order #${orderId} accepted`, body: 'The store is preparing your order.' },
    });
    return o;
  });
  res.json({ success: true, message: 'Order approved!', data: vendorOrderView(order) });
});

/** PUT /api/vendor/orders/:id/reject — pending → cancelled, stock released, full refund */
const rejectOrder = asyncHandler(async (req, res) => {
  const vendorId = vendorIdOf(req);
  const orderId = intParam(req.params.id);
  await withTransaction(async (client, afterCommit) => {
    await transition(client, orderId, vendorId, 'pending', 'cancelled', `, cancellation_reason = 'Vendor cancelled'`);
    await releaseOrderLocks(client, afterCommit, orderId, 'Order rejected by vendor');
    const { refund } = await refundEscrow(client, afterCommit, orderId, { note: `Escrow refund for rejected Order #${orderId}` });
    await announceOrder(client, afterCommit, orderId, 'order_cancelled', {
      customer: { title: `Order #${orderId} declined`, body: `The store couldn't take this order. Rs. ${refund.toFixed(2)} refunded to your wallet.` },
    });
  });
  res.json({ success: true, message: 'Order rejected. Stock has been released.' });
});

// ── Packing checklist: every line ticked (or scanned) before the order can be "packed"

/** Locks a confirmed order of this store for packing */
async function lockForPacking(client, orderId, vendorId) {
  const r = await client.query('SELECT id, status FROM orders WHERE id = $1 AND vendor_id = $2 FOR UPDATE', [orderId, vendorId]);
  if (r.rows.length === 0) throw httpError(404, 'Order not found.');
  if (r.rows[0].status !== 'confirmed') throw httpError(409, `Packing is done on accepted orders; this one is ${r.rows[0].status}.`);
}

async function packingView(db, orderId) {
  const r = await db.query(
    `SELECT oi.id, oi.product_id, p.name AS product_name, p.barcode, p.image_url, oi.quantity, oi.packed_quantity
     FROM order_items oi JOIN products p ON p.id = oi.product_id WHERE oi.order_id = $1 ORDER BY oi.id`,
    [orderId]
  );
  const items = r.rows;
  return {
    order_id: orderId,
    items,
    packed_units: items.reduce((s, i) => s + i.packed_quantity, 0),
    total_units: items.reduce((s, i) => s + i.quantity, 0),
    complete: items.every((i) => i.packed_quantity >= i.quantity),
  };
}

/** PUT /api/vendor/orders/:id/items/:itemId/pack  Body: { packed: bool } or { packedQuantity } */
const setItemPacked = asyncHandler(async (req, res) => {
  const vendorId = vendorIdOf(req);
  const orderId = intParam(req.params.id);
  const itemId = intParam(req.params.itemId, 'itemId');
  const view = await withTransaction(async (client) => {
    await lockForPacking(client, orderId, vendorId);
    const item = (await client.query('SELECT quantity FROM order_items WHERE id = $1 AND order_id = $2', [itemId, orderId])).rows[0];
    if (!item) throw httpError(404, 'That item is not part of this order.');
    let packed;
    if (req.body.packedQuantity !== undefined) {
      packed = wholeNumber(req.body.packedQuantity, 'packedQuantity');
      if (packed > item.quantity) throw httpError(400, `Only ${item.quantity} of this item were ordered.`);
    } else {
      packed = req.body.packed === false ? 0 : item.quantity;
    }
    await client.query('UPDATE order_items SET packed_quantity = $1 WHERE id = $2', [packed, itemId]);
    return packingView(client, orderId);
  });
  res.json({ success: true, data: view });
});

/**
 * POST /api/vendor/orders/:id/scan  Body: { barcode }
 * Scanning an item packs one unit of it. A product that isn't in the order,
 * or one already fully packed, is refused, so the wrong item can't go in the bag.
 */
const scanPackItem = asyncHandler(async (req, res) => {
  const vendorId = vendorIdOf(req);
  const orderId = intParam(req.params.id);
  const barcode = typeof req.body.barcode === 'string' ? req.body.barcode.trim() : '';
  if (!barcode) throw httpError(400, 'Scan a barcode.');

  const result = await withTransaction(async (client) => {
    await lockForPacking(client, orderId, vendorId);
    const lines = (await client.query(
      `SELECT oi.id, oi.quantity, oi.packed_quantity, p.name FROM order_items oi JOIN products p ON p.id = oi.product_id
       WHERE oi.order_id = $1 AND p.barcode = $2 ORDER BY oi.id`,
      [orderId, barcode]
    )).rows;
    if (lines.length === 0) {
      throw httpError(422, `Barcode ${barcode} is not in Order #${orderId}. Check you picked the right item.`, { code: 'WRONG_ITEM' });
    }
    const line = lines.find((l) => l.packed_quantity < l.quantity);
    if (!line) throw httpError(409, `All "${lines[0].name}" for this order are already packed.`, { code: 'ALREADY_PACKED' });
    await client.query('UPDATE order_items SET packed_quantity = packed_quantity + 1 WHERE id = $1', [line.id]);
    return { scanned: { item_id: line.id, product_name: line.name, packed_quantity: line.packed_quantity + 1, quantity: line.quantity }, ...(await packingView(client, orderId)) };
  });
  res.json({ success: true, message: `${result.scanned.product_name}: ${result.scanned.packed_quantity}/${result.scanned.quantity} packed.`, data: result });
});

/** PUT /api/vendor/orders/:id/prepare — confirmed → packed, once the packing checklist is complete */
const markOrderPreparing = asyncHandler(async (req, res) => {
  const vendorId = vendorIdOf(req);
  const orderId = intParam(req.params.id);
  const order = await withTransaction(async (client, afterCommit) => {
    await lockForPacking(client, orderId, vendorId);
    const packing = await packingView(client, orderId);
    if (!packing.complete) {
      const missing = packing.items.filter((i) => i.packed_quantity < i.quantity)
        .map((i) => ({ item_id: i.id, product_name: i.product_name, missing: i.quantity - i.packed_quantity }));
      throw httpError(409, `Pack every item first: ${missing.map((m) => `${m.missing} × ${m.product_name}`).join(', ')} still missing.`, {
        code: 'PACKING_INCOMPLETE', missing,
      });
    }
    const o = await transition(client, orderId, vendorId, 'confirmed', 'packed', `, packed_by_staff_id = ${staffIdOf(req) ?? 'NULL'}`);
    await announceOrder(client, afterCommit, orderId, 'order_packed', {
      customer: { title: `Order #${orderId} packed`, body: 'Your items are packed.' },
    });
    return o;
  });
  res.json({ success: true, message: 'Order marked as packed.', data: vendorOrderView(order) });
});

/**
 * Online riders within the policy radius of the store get a task notification.
 */
async function broadcastTask(client, afterCommit, order) {
  const policies = await getPolicies(client);
  const store = (await client.query('SELECT store_name, latitude, longitude FROM vendors WHERE id = $1', [order.vendor_id])).rows[0];
  const riders = await client.query(
    `SELECT user_id, current_lat, current_lng FROM riders WHERE is_online = true AND current_lat IS NOT NULL`
  );
  const nearby = riders.rows.filter((r) =>
    store.latitude == null ||
    haversineKm(r.current_lat, r.current_lng, store.latitude, store.longitude) <= policies.task_radius_km
  );
  for (const r of nearby) {
    await notify(client, afterCommit, r.user_id, {
      type: 'task_available',
      orderId: order.id,
      title: 'New delivery nearby',
      body: `Pickup from ${store.store_name}. Open Tasks to accept.`,
    });
  }
  afterCommit.push(() => emitToRiders('task:new', {
    orderId: order.id,
    vendorId: order.vendor_id,
    storeName: store.store_name,
    storeLat: store.latitude,
    storeLng: store.longitude,
  }));
}

/** PUT /api/vendor/orders/:id/ready-for-pickup — packed → ready_for_pickup; delivery orders go to riders */
const markOrderReadyForPickup = asyncHandler(async (req, res) => {
  const vendorId = vendorIdOf(req);
  const orderId = intParam(req.params.id);
  const order = await withTransaction(async (client, afterCommit) => {
    const o = await transition(client, orderId, vendorId, 'packed', 'ready_for_pickup', ', ready_at = NOW()');
    const isDelivery = o.delivery_type === 'delivery';
    await announceOrder(client, afterCommit, orderId, 'order_ready', {
      customer: isDelivery
        ? { title: `Order #${orderId} is ready`, body: 'Finding a rider to bring it to you.' }
        : { title: `Order #${orderId} is ready for pickup`, body: 'You can collect it from the store now.' },
    });
    if (isDelivery) await broadcastTask(client, afterCommit, o);
    return o;
  });
  res.json({
    success: true,
    message: order.delivery_type === 'delivery'
      ? 'Order ready. Nearby riders have been notified.'
      : 'Order ready. The customer has been told to collect it.',
    data: vendorOrderView(order),
  });
});

/**
 * PUT /api/vendor/orders/:id/deliver  Body: { otp } — self pickup handed over; dispute window starts.
 * The customer shows their 4-digit code at the counter.
 */
const markVendorOrderDelivered = asyncHandler(async (req, res) => {
  const vendorId = vendorIdOf(req);
  const orderId = intParam(req.params.id);
  await withHandoverOtp(async (client, afterCommit) => {
    const o = (await client.query(
      `SELECT * FROM orders WHERE id = $1 AND vendor_id = $2 AND delivery_type = 'self_pickup' AND status IN ('ready_for_pickup', 'picked')
       FOR UPDATE`,
      [orderId, vendorId]
    )).rows[0];
    if (!o) {
      throw httpError(400, 'Mark as Delivered is only available for self pickup orders in Ready or Picked-up state.');
    }
    await verifyHandoverOtp(client, o, req.body?.otp);
    await client.query(`UPDATE orders SET status = 'delivered', delivered_at = NOW(), updated_at = NOW() WHERE id = $1`, [orderId]);
    await consumeOrderLocks(client, afterCommit, orderId, 'Self pickup handed over');
    await scheduleEscrowRelease(client, afterCommit, orderId);
    await announceOrder(client, afterCommit, orderId, 'order_delivered', {
      customer: { title: `Order #${orderId} completed`, body: 'Something wrong? You can raise a dispute before payment is released.' },
    });
  });
  res.json({ success: true, message: 'Order marked delivered. Payment will be released after the dispute window.' });
});

// ──────────────────────────────────────
// LOCATION + LEDGER
// ──────────────────────────────────────

/** The vendor's location and any change waiting for the admin */
function locationView(v) {
  return {
    latitude: v.latitude,
    longitude: v.longitude,
    storeAddress: v.store_address,
    pendingLocation: v.location_requested_at
      ? { latitude: v.pending_latitude, longitude: v.pending_longitude, address: v.pending_address, requestedAt: v.location_requested_at }
      : null,
    locationRejectionReason: v.location_rejection_reason,
  };
}

/**
 * PUT /api/vendor/location  Body: { latitude, longitude, storeAddress? }
 * A store waiting for approval sets its location directly (the admin reviews it
 * with the store). An approved store can't move itself: this files a request
 * (202) and the store stays put until an admin approves it. A new request
 * replaces an earlier one.
 */
const updateVendorLocation = asyncHandler(async (req, res) => {
  const vendorId = vendorIdOf(req);
  const latitude = Number(req.body.latitude);
  const longitude = Number(req.body.longitude);
  if (!isValidCoordinate(latitude, longitude)) throw httpError(400, 'Valid latitude and longitude are required.');
  const address = typeof req.body.storeAddress === 'string' && req.body.storeAddress.trim() ? req.body.storeAddress.trim() : null;

  const result = await withTransaction(async (client, afterCommit) => {
    const v = (await client.query('SELECT * FROM vendors WHERE id = $1 FOR UPDATE', [vendorId])).rows[0];
    if (!v) throw httpError(404, 'Vendor not found.');
    if (!v.is_approved) {
      const r = await client.query(
        `UPDATE vendors SET latitude = $1, longitude = $2, store_address = COALESCE($3, store_address),
                pending_latitude = NULL, pending_longitude = NULL, pending_address = NULL,
                location_requested_at = NULL, location_rejection_reason = NULL
         WHERE id = $4 RETURNING *`,
        [latitude, longitude, address, vendorId]
      );
      return { applied: true, vendor: r.rows[0] };
    }
    const r = await client.query(
      `UPDATE vendors SET pending_latitude = $1, pending_longitude = $2, pending_address = $3,
              location_requested_at = NOW(), location_rejection_reason = NULL
       WHERE id = $4 RETURNING *`,
      [latitude, longitude, address, vendorId]
    );
    const movedKm = v.latitude != null ? haversineKm(v.latitude, v.longitude, latitude, longitude) : null;
    await notifyAdmins(client, afterCommit, {
      type: 'location_change_requested',
      title: `${v.store_name} wants to move`,
      body: movedKm != null
        ? `New store location ${movedKm.toFixed(1)} km from the current one. Review it in Vendors.`
        : 'The store has asked to set its location. Review it in Vendors.',
    });
    afterCommit.push(() => broadcast('vendors:update', { vendorId }));
    return { applied: false, vendor: r.rows[0] };
  });

  res.status(result.applied ? 200 : 202).json({
    success: true,
    message: result.applied
      ? 'Location updated'
      : 'Sent to Vendra for approval. Customers and riders keep seeing your current location until an admin approves the change.',
    data: { applied: result.applied, ...locationView(result.vendor) },
  });
});

/** DELETE /api/vendor/location/request — withdraw a location change that's waiting for review */
const cancelLocationRequest = asyncHandler(async (req, res) => {
  const vendorId = vendorIdOf(req);
  const r = await pool.query(
    `UPDATE vendors SET pending_latitude = NULL, pending_longitude = NULL, pending_address = NULL, location_requested_at = NULL
     WHERE id = $1 RETURNING *`,
    [vendorId]
  );
  res.json({ success: true, message: 'Location change withdrawn.', data: locationView(r.rows[0]) });
});

/** GET /api/vendor/inventory/ledger */
const getInventoryLedger = asyncHandler(async (req, res) => {
  const vendorId = vendorIdOf(req);
  const r = await pool.query(
    `SELECT il.*, p.name AS product_name
     FROM inventory_ledger il JOIN products p ON p.id = il.product_id
     WHERE il.vendor_id = $1
     ORDER BY il.created_at DESC, il.id DESC
     LIMIT 100`,
    [vendorId]
  );
  res.json({ success: true, data: r.rows });
});

module.exports = {
  createProduct,
  getVendorProducts,
  getProductByBarcode,
  updateProduct,
  deleteProduct,
  uploadProductImage,
  deleteProductImage,
  addGalleryImage,
  deleteGalleryImage,
  getVendorReviews,
  createPosSale,
  getPosSales,
  getPosSale,
  getReceiptSettings,
  updateReceiptSettings,
  getVendorOrders,
  getVendorOrder,
  approveOrder,
  rejectOrder,
  setItemPacked,
  scanPackItem,
  markOrderPreparing,
  markOrderReadyForPickup,
  markVendorOrderDelivered,
  updateVendorLocation,
  cancelLocationRequest,
  getInventoryLedger,
};
