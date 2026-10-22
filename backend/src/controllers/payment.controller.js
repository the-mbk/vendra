// ══════════════════════════════════════════════════════════════
// Card payments, withdrawals, gateway webhooks and the admin money views
// (logic lives in services/payments.service.js)
// ══════════════════════════════════════════════════════════════

const pool = require('../db');
const payments = require('../services/payments.service');
const { verifyWebhook } = require('../services/gateway.client');
const { asyncHandler, intParam, paging, pageOf, searchPattern } = require('../utils/http');

/** POST /api/payments/topup  { amount, token } */
const topup = asyncHandler(async (req, res) => {
  const data = await payments.startTopup(req.user.userId, req.body);
  res.status(data.payment.status === 'failed' ? 402 : 200).json({
    success: data.payment.status !== 'failed',
    message: data.payment.status === 'failed' ? data.payment.failureMessage || 'Payment failed.' : undefined,
    data,
  });
});

/** POST /api/payments/checkout  { token, items, deliveryType, deliveryAddress, customerLat, customerLng } */
const cardCheckout = asyncHandler(async (req, res) => {
  const data = await payments.startCardCheckout(req.user.userId, req.body);
  res.status(data.payment.status === 'failed' ? 402 : 200).json({
    success: data.payment.status !== 'failed',
    message: data.payment.status === 'failed' ? data.payment.failureMessage || 'Payment failed.' : undefined,
    data,
  });
});

/** GET /api/payments/:id */
const getPayment = asyncHandler(async (req, res) => {
  res.json({ success: true, data: await payments.getPayment(req.user.userId, intParam(req.params.id)) });
});

/** POST /api/payments/:id/refresh — re-reads the payment from the gateway (after the OTP step) */
const refreshPayment = asyncHandler(async (req, res) => {
  res.json({ success: true, data: await payments.refreshPayment(req.user.userId, intParam(req.params.id)) });
});

/** GET /api/payments?limit&offset */
const listMyPayments = asyncHandler(async (req, res) => {
  const page = paging(req.query);
  const { items, meta } = pageOf(await payments.listPayments(req.user.userId, page), page);
  res.json({ success: true, data: items, meta });
});

/** POST /api/withdrawals  { amount, token } */
const withdraw = asyncHandler(async (req, res) => {
  res.status(201).json({ success: true, data: await payments.startWithdrawal(req.user.userId, req.body) });
});

/** GET /api/withdrawals?limit&offset */
const listMyWithdrawals = asyncHandler(async (req, res) => {
  const page = paging(req.query);
  const { items, meta } = pageOf(await payments.listWithdrawals(req.user.userId, page), page);
  res.json({ success: true, data: items, meta });
});

/** POST /api/payments/webhook — signed events from the gateway (raw JSON body) */
const gatewayWebhook = asyncHandler(async (req, res) => {
  const raw = Buffer.isBuffer(req.body) ? req.body.toString('utf8') : '';
  const event = verifyWebhook(raw, req.headers['vendra-signature']);
  if (!event) return res.status(400).json({ success: false, message: 'Invalid signature.' });
  await payments.handleGatewayEvent(event); // a failure returns 500 and the gateway retries
  res.json({ received: true });
});

// ──────────────────────────────────────
// Admin
// ──────────────────────────────────────

/** GET /api/admin/finance/reconciliation */
const adminReconciliation = asyncHandler(async (req, res) => {
  res.json({ success: true, data: await payments.reconciliation() });
});

/** The search box text for exact matches (order number, card last 4): "#VDR-03630" → "3630" */
function exactTerm(text) {
  const t = typeof text === 'string' ? text.trim().replace(/^#?(vdr-|ord-)?0*/i, '') : '';
  return t || null;
}

const withUser = (row, view) => ({ ...view, user: { id: row.user_id, name: row.full_name, email: row.email, role: row.role } });

/** GET /api/admin/payments?status&search&limit&offset (search: customer, gateway id or order) */
const adminListPayments = asyncHandler(async (req, res) => {
  const page = paging(req.query, { defaultLimit: 50 });
  const r = await pool.query(
    `SELECT p.*, u.full_name, u.email, u.role FROM payments p JOIN users u ON u.id = p.user_id
     WHERE ($1::text IS NULL OR p.status = $1)
       AND ($4::text IS NULL OR u.full_name ILIKE $4 OR u.email ILIKE $4 OR p.gateway_intent_id ILIKE $4
            OR p.order_id::text = $5 OR p.card_last4 = $5)
     ORDER BY p.created_at DESC, p.id DESC LIMIT $2 OFFSET $3`,
    [req.query.status || null, page.limit + 1, page.offset, searchPattern(req.query.search), exactTerm(req.query.search)]
  );
  const { items, meta } = pageOf(r.rows.map((p) => withUser(p, payments.paymentView(p))), page);
  res.json({ success: true, data: items, meta });
});

/** GET /api/admin/withdrawals?status&search&limit&offset (search: user, payout id or card) */
const adminListWithdrawals = asyncHandler(async (req, res) => {
  const page = paging(req.query, { defaultLimit: 50 });
  const r = await pool.query(
    `SELECT w.*, u.full_name, u.email, u.role FROM withdrawals w JOIN users u ON u.id = w.user_id
     WHERE ($1::text IS NULL OR w.status = $1)
       AND ($4::text IS NULL OR u.full_name ILIKE $4 OR u.email ILIKE $4 OR w.gateway_payout_id ILIKE $4
            OR w.card_last4 = $5)
     ORDER BY w.created_at DESC, w.id DESC LIMIT $2 OFFSET $3`,
    [req.query.status || null, page.limit + 1, page.offset, searchPattern(req.query.search), exactTerm(req.query.search)]
  );
  const { items, meta } = pageOf(r.rows.map((w) => withUser(w, payments.withdrawalView(w))), page);
  res.json({ success: true, data: items, meta });
});

module.exports = {
  topup,
  cardCheckout,
  getPayment,
  refreshPayment,
  listMyPayments,
  withdraw,
  listMyWithdrawals,
  gatewayWebhook,
  adminReconciliation,
  adminListPayments,
  adminListWithdrawals,
};
