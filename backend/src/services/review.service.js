// ══════════════════════════════════════════════════════════════
// Customer reviews & ratings (SRDS §2.3, Fig 2.3)
// After an order is delivered the customer rates each product (1–5 stars,
// optional comment) and, for deliveries, the rider. One review per order,
// no edits. Products keep a running rating_sum / rating_count so lists can
// show stars without aggregating every review.
// ══════════════════════════════════════════════════════════════

const { httpError } = require('../utils/http');
const { shortName } = require('../utils/privacy');
const { notify } = require('./notification.service');

const MAX_COMMENT = 500;

function readRating(value, what) {
  const n = Number(value);
  if (!Number.isInteger(n) || n < 1 || n > 5) throw httpError(400, `${what} must be a whole number of stars from 1 to 5.`);
  return n;
}

function formatReview(r) {
  return {
    id: r.id,
    orderId: r.order_id,
    productId: r.product_id,
    productName: r.product_name,
    rating: r.rating,
    comment: r.comment,
    // Reviews show who wrote them without the full name
    customerName: shortName(r.customer_name, 'Customer'),
    createdAt: r.created_at,
  };
}

/**
 * Saves the customer's review of a delivered order. Runs inside a transaction.
 * body: { items: [{ productId, rating, comment? }], riderRating? }
 */
async function submitOrderReview(client, afterCommit, customerId, orderId, body) {
  const order = (await client.query(
    `SELECT o.*, v.user_id AS vendor_user_id FROM orders o JOIN vendors v ON v.id = o.vendor_id
     WHERE o.id = $1 AND o.customer_id = $2 FOR UPDATE OF o`,
    [orderId, customerId]
  )).rows[0];
  if (!order) throw httpError(404, 'Order not found.');
  if (order.status !== 'delivered') throw httpError(409, 'You can review an order once it has been delivered.', { code: 'NOT_DELIVERED' });
  if (order.reviewed_at) throw httpError(409, 'You have already reviewed this order.', { code: 'ALREADY_REVIEWED' });

  const items = Array.isArray(body?.items) ? body.items : [];
  if (items.length === 0) throw httpError(400, 'Rate at least one product.');
  const ordered = new Set((await client.query('SELECT product_id FROM order_items WHERE order_id = $1', [orderId])).rows.map((r) => r.product_id));

  const seen = new Set();
  const reviews = items.map((item) => {
    const productId = Number(item?.productId);
    if (!ordered.has(productId)) throw httpError(400, `Product ${item?.productId} is not part of this order.`);
    if (seen.has(productId)) throw httpError(400, 'Rate each product once.');
    seen.add(productId);
    const comment = typeof item.comment === 'string' ? item.comment.trim() : '';
    if (comment.length > MAX_COMMENT) throw httpError(400, `Comments can be up to ${MAX_COMMENT} characters.`);
    return { productId, rating: readRating(item.rating, 'Rating'), comment: comment || null };
  });

  let riderRating = null;
  if (body.riderRating != null) {
    if (!order.rider_user_id) throw httpError(400, 'This order had no rider to rate.');
    riderRating = readRating(body.riderRating, 'Rider rating');
  }

  for (const r of reviews) {
    await client.query(
      `INSERT INTO product_reviews (order_id, product_id, vendor_id, customer_id, rating, comment) VALUES ($1, $2, $3, $4, $5, $6)`,
      [orderId, r.productId, order.vendor_id, customerId, r.rating, r.comment]
    );
    await client.query(
      'UPDATE products SET rating_sum = rating_sum + $1, rating_count = rating_count + 1 WHERE id = $2',
      [r.rating, r.productId]
    );
  }
  await client.query('UPDATE orders SET reviewed_at = NOW(), rider_rating = $1 WHERE id = $2', [riderRating, orderId]);

  const avg = reviews.reduce((s, r) => s + r.rating, 0) / reviews.length;
  await notify(client, afterCommit, order.vendor_user_id, {
    type: 'review_received',
    orderId,
    title: `New ${avg.toFixed(1)}★ review on Order #${orderId}`,
    body: reviews.find((r) => r.comment)?.comment?.slice(0, 120) || `${reviews.length} product(s) rated.`,
  });
  if (riderRating) {
    await notify(client, afterCommit, order.rider_user_id, {
      type: 'rider_rated',
      orderId,
      title: `You got ${riderRating}★ for Order #${orderId}`,
    });
  }
  return { orderId, reviewed: reviews.length, riderRating };
}

module.exports = { submitOrderReview, formatReview };
