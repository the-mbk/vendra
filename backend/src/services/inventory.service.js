// ══════════════════════════════════════════════════════════════
// Dual inventory — the only place stock numbers change.
//   public_stock = max(0, private_stock - buffer - reserved_quantity)
// Every function expects an open transaction and locks product rows
// in id order so concurrent checkouts / POS sales can't deadlock.
// Lock order across the codebase: order row → products → escrow pool → wallets.
// ══════════════════════════════════════════════════════════════

const { emitStock } = require('../realtime');
const { getPolicy } = require('./policy.service');
const { notify } = require('./notification.service');

function computePublicStock({ private_stock, buffer, reserved_quantity }) {
  return Math.max(0, private_stock - buffer - reserved_quantity);
}

/**
 * Row-locks the given products (returned as a map by id). FOR NO KEY UPDATE still
 * excludes every other stock writer, but unlike FOR UPDATE it doesn't conflict
 * with the FOR KEY SHARE locks that inserting order_items / pos_sale_items
 * (foreign keys to products) take — so a checkout that has already written its
 * order lines can't deadlock with another one waiting for the same product.
 */
async function lockProducts(client, productIds) {
  const ids = [...new Set(productIds.map(Number))].sort((a, b) => a - b);
  const r = await client.query(
    'SELECT * FROM products WHERE id = ANY($1::int[]) ORDER BY id FOR NO KEY UPDATE',
    [ids]
  );
  const map = new Map();
  for (const p of r.rows) map.set(p.id, p);
  return map;
}

/**
 * Writes new private/reserved counts (recomputing public stock), logs the ledger
 * entry and queues a realtime stock update for after commit.
 */
async function applyStockChange(client, afterCommit, product, {
  privateStock = product.private_stock,
  reservedQuantity = product.reserved_quantity,
  buffer = product.buffer,
  ledger,
}) {
  const next = {
    private_stock: privateStock,
    reserved_quantity: reservedQuantity,
    buffer,
  };
  next.public_stock = computePublicStock(next);

  const r = await client.query(
    `UPDATE products
       SET private_stock = $1, reserved_quantity = $2, buffer = $3, public_stock = $4, updated_at = NOW()
     WHERE id = $5
     RETURNING *`,
    [next.private_stock, next.reserved_quantity, next.buffer, next.public_stock, product.id]
  );
  const updated = r.rows[0];

  if (ledger) {
    await client.query(
      `INSERT INTO inventory_ledger
         (product_id, vendor_id, change_type, quantity_change, private_stock_after, public_stock_after, reference_id, notes)
       VALUES ($1, $2, $3, $4, $5, $6, $7, $8)`,
      [
        product.id, product.vendor_id, ledger.type, ledger.quantityChange,
        updated.private_stock, updated.public_stock, ledger.referenceId || null, ledger.notes || null,
      ]
    );
  }

  await alertIfRunningLow(client, afterCommit, product, updated);
  afterCommit.push(() => emitStock(updated));
  return updated;
}

/** Units the store can still sell: on the shelf and not held by online orders */
const freeUnits = (p) => p.private_stock - p.reserved_quantity;

/**
 * Restock alert (FR09): tells the store once, as a product's free units fall to the
 * low_stock_units policy or below. Rising again re-arms it.
 */
async function alertIfRunningLow(client, afterCommit, before, after) {
  const was = freeUnits(before);
  const now = freeUnits(after);
  if (now >= was || !after.is_active) return;
  const threshold = await getPolicy(client, 'low_stock_units');
  if (!(was > threshold && now <= threshold)) return;
  const owner = (await client.query('SELECT user_id FROM vendors WHERE id = $1', [after.vendor_id])).rows[0];
  await notify(client, afterCommit, owner?.user_id, {
    type: 'low_stock',
    title: now > 0 ? `Running low: ${after.name}` : `Out of stock: ${after.name}`,
    body: now > 0
      ? `Only ${now} left to sell (${after.public_stock} online). Scan it in when new stock arrives.`
      : 'Nothing left to sell. Scan it in when new stock arrives.',
  });
}

async function activeLocksForOrder(client, orderId) {
  const r = await client.query(
    `SELECT * FROM inventory_locks WHERE order_id = $1 AND status = 'active' ORDER BY product_id`,
    [orderId]
  );
  return r.rows;
}

/** Cancelled / refunded before delivery: reserved units go back on sale */
async function releaseOrderLocks(client, afterCommit, orderId, notes) {
  const locks = await activeLocksForOrder(client, orderId);
  if (locks.length === 0) return;
  const products = await lockProducts(client, locks.map((l) => l.product_id));

  for (const lock of locks) {
    const p = products.get(lock.product_id);
    const updated = await applyStockChange(client, afterCommit, p, {
      reservedQuantity: Math.max(0, p.reserved_quantity - lock.quantity),
      ledger: { type: 'release', quantityChange: lock.quantity, referenceId: orderId, notes },
    });
    products.set(p.id, updated);
    await client.query(`UPDATE inventory_locks SET status = 'released' WHERE id = $1`, [lock.id]);
  }
}

/** Delivered: reserved units leave the shop for good (private and reserved both drop) */
async function consumeOrderLocks(client, afterCommit, orderId, notes) {
  const locks = await activeLocksForOrder(client, orderId);
  if (locks.length === 0) return;
  const products = await lockProducts(client, locks.map((l) => l.product_id));

  for (const lock of locks) {
    const p = products.get(lock.product_id);
    const updated = await applyStockChange(client, afterCommit, p, {
      privateStock: Math.max(0, p.private_stock - lock.quantity),
      reservedQuantity: Math.max(0, p.reserved_quantity - lock.quantity),
      ledger: { type: 'sale', quantityChange: -lock.quantity, referenceId: orderId, notes },
    });
    products.set(p.id, updated);
    await client.query(`UPDATE inventory_locks SET status = 'consumed' WHERE id = $1`, [lock.id]);
  }
}

module.exports = {
  computePublicStock,
  lockProducts,
  applyStockChange,
  releaseOrderLocks,
  consumeOrderLocks,
};
