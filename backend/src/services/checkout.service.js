// ══════════════════════════════════════════════════════════════
// Checkout: validate the cart, price it, and place the order.
// placeOrder is the only code that creates orders. It reserves stock
// (FR02) and holds the total in escrow from the customer's wallet (FR03).
// ══════════════════════════════════════════════════════════════

const { lockEscrowRow, creditEscrowPool } = require('./escrowPool.service');
const { lockProducts, applyStockChange } = require('./inventory.service');
const { debitWallet } = require('./wallet.service');
const { announceOrder } = require('./notification.service');
const { getPolicies } = require('./policy.service');
const { httpError } = require('../utils/http');
const { isValidCoordinate } = require('../utils/geo');
const { deliveryDistanceKm, deliveryFeePaisa, assertDeliversTo } = require('./deliveryFee');
const { toPaisa, paisaToString, paisaToNumber } = require('../utils/money');

const num = (v) => (v == null ? null : Number(v));

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

/** Validates a checkout request body (wallet and card checkout share it) */
function readCheckoutInput(body) {
  const deliveryType = body.deliveryType || 'delivery';
  const input = {
    deliveryType,
    deliveryAddress: body.deliveryAddress || null,
    customerLat: num(body.customerLat),
    customerLng: num(body.customerLng),
    items: parseCheckoutItems(body.items),
  };
  if (!['delivery', 'self_pickup'].includes(deliveryType)) {
    throw httpError(400, "deliveryType must be 'delivery' or 'self_pickup'.");
  }
  if (deliveryType === 'delivery' && !isValidCoordinate(input.customerLat, input.customerLng)) {
    throw httpError(400, 'Set your delivery location on the map before placing a delivery order.');
  }
  return input;
}

/**
 * What the cart costs right now (paisa), after the same availability checks the
 * order makes. No locks: the cart screen shows this, a card is charged exactly
 * totalPaisa, then the order re-checks everything under lock (placeOrder).
 * @returns {{ subtotalPaisa, deliveryFeePaisa, totalPaisa, distanceKm, vendorId }}
 */
async function quoteCheckout(db, input) {
  const r = await db.query(
    `SELECT p.id, p.name, p.price, p.public_stock, p.is_active, p.is_approved, p.vendor_id,
            v.is_approved AS store_open, v.latitude, v.longitude
     FROM products p JOIN vendors v ON v.id = p.vendor_id WHERE p.id = ANY($1::int[])`,
    [input.items.map((i) => i.productId)]
  );
  const byId = new Map(r.rows.map((p) => [p.id, p]));
  let subtotal = 0;
  let vendorId = null;
  let store = null;
  for (const item of input.items) {
    const p = byId.get(item.productId);
    store = p ?? store;
    if (!p) throw httpError(404, `Product ${item.productId} not found.`);
    if (!p.is_active || !p.is_approved) throw httpError(400, `"${p.name}" is no longer available.`);
    if (p.public_stock < item.quantity) {
      throw httpError(409, `Insufficient stock for "${p.name}". Available: ${p.public_stock}, requested: ${item.quantity}.`, {
        code: 'INSUFFICIENT_STOCK', productId: p.id, available: p.public_stock,
      });
    }
    if (vendorId === null) vendorId = p.vendor_id;
    else if (p.vendor_id !== vendorId) throw httpError(400, 'All items must be from the same vendor.');
    if (!p.store_open) throw httpError(400, 'This store is not accepting orders right now.');
    subtotal += toPaisa(p.price) * item.quantity;
  }
  const policies = await getPolicies(db);
  const delivery = input.deliveryType === 'delivery';
  const distanceKm = delivery ? deliveryDistanceKm(store, { lat: input.customerLat, lng: input.customerLng }) : 0;
  if (delivery) assertDeliversTo(policies, distanceKm);
  const fee = delivery ? deliveryFeePaisa(policies, distanceKm) : 0;
  return { subtotalPaisa: subtotal, deliveryFeePaisa: fee, totalPaisa: subtotal + fee, distanceKm, vendorId };
}

/**
 * ATOMIC ORDER RESERVATION (FR02) + ESCROW HOLD (FR03). Runs inside a transaction.
 * The total always comes out of the customer's wallet; a card checkout first puts
 * the card payment into the wallet (payments.service), so escrow has one entry path.
 */
async function placeOrder(client, afterCommit, customerId, input, { paymentMethod = 'wallet' } = {}) {
  const { deliveryType, deliveryAddress, customerLat, customerLng, items } = input;
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

  const km = deliveryType === 'delivery' ? deliveryDistanceKm(vendor, { lat: customerLat, lng: customerLng }) : 0;
  if (deliveryType === 'delivery') assertDeliversTo(policies, km);
  const deliveryFee = deliveryType === 'delivery' ? deliveryFeePaisa(policies, km) : 0;
  const total = subtotal + deliveryFee;

  let estimatedMinutes = null;
  if (deliveryType === 'delivery' && vendor.latitude != null) {
    estimatedMinutes = Math.max(15, Math.round(km * 3));
  }

  // Step 3: create the order (pending vendor approval)
  const order = (await client.query(
    `INSERT INTO orders (customer_id, vendor_id, status, subtotal, delivery_fee, total_amount,
                         delivery_type, delivery_address, customer_lat, customer_lng, estimated_minutes, escrow_status,
                         payment_method)
     VALUES ($1, $2, 'pending', $3, $4, $5, $6, $7, $8, $9, $10, 'held', $11)
     RETURNING *`,
    [customerId, vendorId, paisaToString(subtotal), paisaToString(deliveryFee), paisaToString(total),
      deliveryType, deliveryAddress || null, customerLat, customerLng, estimatedMinutes, paymentMethod]
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
    paymentMethod,
    walletBalance: paisaToNumber(walletAfter),
    items: lines.map((l) => ({
      productId: l.product.id,
      productName: l.product.name,
      quantity: l.quantity,
      unitPrice: paisaToNumber(l.unitPaisa),
    })),
  };
}

module.exports = { readCheckoutInput, quoteCheckout, placeOrder };
