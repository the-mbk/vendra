// ══════════════════════════════════════════════════════════════
// Vendra Backend - Dispute Controller (FR08)
// Any party to an order (customer, vendor, rider) can raise a dispute
// while its escrow is still held. An open dispute freezes the escrow
// until an admin decides: refund the customer or release to the vendor.
// ══════════════════════════════════════════════════════════════

const pool = require('../db');
const { releaseOrderLocks } = require('../services/inventory.service');
const { refundEscrow, releaseEscrow } = require('../services/orderSettlement.service');
const { notify, notifyAdmins, orderParties } = require('../services/notification.service');
const { signedEvidenceUrl, removeEvidenceFiles } = require('../services/storage.service');
const { httpError, asyncHandler, withTransaction, intParam } = require('../utils/http');

const ISSUE_TYPES = [
  'item_not_received', 'damaged_item', 'wrong_item', 'missing_items',
  'quality_issue', 'rider_issue', 'customer_issue', 'other',
];

function partyRole(order, userId) {
  if (order.customer_id === userId) return 'customer';
  if (order.vendor_user_id === userId) return 'vendor';
  if (order.rider_user_id === userId) return 'rider';
  return null;
}

const DISPUTE_SELECT = `
  SELECT d.*, u.full_name AS raised_by_name,
         o.status AS order_status, o.escrow_status, o.total_amount, o.rider_payout, o.delivery_type,
         o.customer_id, o.rider_user_id, v.store_name, v.user_id AS vendor_user_id,
         cu.full_name AS customer_name, ru.full_name AS rider_name,
         COALESCE((SELECT json_agg(json_build_object('id', e.id, 'url', e.file_url, 'name', e.original_name) ORDER BY e.id)
                   FROM dispute_evidence e WHERE e.dispute_id = d.id), '[]') AS evidence
  FROM disputes d
  JOIN users u ON u.id = d.raised_by
  JOIN orders o ON o.id = d.order_id
  JOIN vendors v ON v.id = o.vendor_id
  JOIN users cu ON cu.id = o.customer_id
  LEFT JOIN users ru ON ru.id = o.rider_user_id`;

function formatDispute(d) {
  return {
    id: d.id,
    orderId: d.order_id,
    issueType: d.issue_type,
    description: d.description,
    status: d.status,
    resolution: d.resolution,
    adminNote: d.admin_note,
    raisedBy: { id: d.raised_by, name: d.raised_by_name, role: d.raised_by_role },
    order: {
      status: d.order_status,
      escrowStatus: d.escrow_status,
      totalAmount: Number(d.total_amount),
      heldAmount: Number(d.total_amount) - Number(d.rider_payout),
      deliveryType: d.delivery_type,
      storeName: d.store_name,
      customerName: d.customer_name,
      riderName: d.rider_name,
    },
    // Signed, expiring links — only people who can see the dispute get them
    evidence: d.evidence.map((e) => ({ id: e.id, url: signedEvidenceUrl(e.url), name: e.name })),
    createdAt: d.created_at,
    resolvedAt: d.resolved_at,
  };
}

/**
 * POST /api/disputes  (multipart/form-data)
 * Fields: orderId, issueType, description; files: evidence (up to 4 images)
 */
const createDispute = asyncHandler(async (req, res) => {
  const files = req.files || [];
  try {
    const orderId = intParam(req.body.orderId, 'orderId');
    const { issueType } = req.body;
    const description = (req.body.description || '').trim();
    if (!ISSUE_TYPES.includes(issueType)) throw httpError(400, `issueType must be one of: ${ISSUE_TYPES.join(', ')}.`);
    if (description.length < 10) throw httpError(400, 'Describe the problem in at least 10 characters.');

    const dispute = await withTransaction(async (client, afterCommit) => {
      const order = (await client.query(
        `SELECT o.*, v.user_id AS vendor_user_id FROM orders o JOIN vendors v ON v.id = o.vendor_id
         WHERE o.id = $1 FOR UPDATE OF o`,
        [orderId]
      )).rows[0];
      if (!order) throw httpError(404, 'Order not found.');

      const role = partyRole(order, req.user.userId);
      if (!role) throw httpError(403, 'You can only dispute your own orders.');
      if (order.status === 'cancelled') throw httpError(409, 'This order was cancelled and already refunded.');
      if (order.escrow_status === 'disputed') throw httpError(409, 'This order already has an open dispute.');
      if (order.escrow_status !== 'held') {
        throw httpError(409, 'Payment for this order has already been settled, so it can no longer be disputed.');
      }

      const d = (await client.query(
        `INSERT INTO disputes (order_id, raised_by, raised_by_role, issue_type, description)
         VALUES ($1, $2, $3, $4, $5) RETURNING *`,
        [orderId, req.user.userId, role, issueType, description]
      )).rows[0];
      for (const f of files) {
        await client.query(
          'INSERT INTO dispute_evidence (dispute_id, file_url, original_name) VALUES ($1, $2, $3)',
          [d.id, f.filename, f.originalname]
        );
      }
      await client.query(`UPDATE orders SET escrow_status = 'disputed', updated_at = NOW() WHERE id = $1`, [orderId]);

      const others = { customer: order.customer_id, vendor: order.vendor_user_id, rider: order.rider_user_id };
      for (const [otherRole, userId] of Object.entries(others)) {
        if (otherRole !== role && userId) {
          await notify(client, afterCommit, userId, {
            type: 'dispute_opened', orderId,
            title: `Dispute opened on Order #${orderId}`,
            body: 'Payment is on hold until an admin reviews the evidence.',
          });
        }
      }
      await notifyAdmins(client, afterCommit, {
        type: 'dispute_opened', orderId,
        title: `New dispute on Order #${orderId}`,
        body: `${role} reported: ${issueType.replace(/_/g, ' ')}.`,
      });

      return (await client.query(`${DISPUTE_SELECT} WHERE d.id = $1`, [d.id])).rows[0];
    });

    res.status(201).json({ success: true, message: 'Dispute submitted. Payment is on hold while an admin reviews it.', data: formatDispute(dispute) });
  } catch (err) {
    removeEvidenceFiles(files);
    throw err;
  }
});

/** GET /api/disputes/mine — disputes on orders the user is part of */
const getMyDisputes = asyncHandler(async (req, res) => {
  const uid = req.user.userId;
  const r = await pool.query(
    `${DISPUTE_SELECT} WHERE o.customer_id = $1 OR v.user_id = $1 OR o.rider_user_id = $1 ORDER BY d.created_at DESC`,
    [uid]
  );
  res.json({ success: true, data: r.rows.map(formatDispute) });
});

/** GET /api/disputes/:id — party to the order or admin */
const getDispute = asyncHandler(async (req, res) => {
  const r = await pool.query(`${DISPUTE_SELECT} WHERE d.id = $1`, [intParam(req.params.id)]);
  const d = r.rows[0];
  if (!d) throw httpError(404, 'Dispute not found.');
  const uid = req.user.userId;
  const isParty = [d.customer_id, d.vendor_user_id, d.rider_user_id].includes(uid);
  if (!isParty && req.user.role !== 'admin') throw httpError(403, 'Not your dispute.');
  res.json({ success: true, data: formatDispute(d) });
});

/** GET /api/admin/disputes?status=open|resolved|all */
const adminListDisputes = asyncHandler(async (req, res) => {
  const status = ['open', 'resolved'].includes(req.query.status) ? req.query.status : null;
  const r = await pool.query(
    `${DISPUTE_SELECT} ${status ? 'WHERE d.status = $1' : ''} ORDER BY (d.status = 'open') DESC, d.created_at DESC`,
    status ? [status] : []
  );
  res.json({ success: true, data: r.rows.map(formatDispute) });
});

/**
 * PUT /api/admin/disputes/:id/resolve  Body: { resolution: 'refund'|'release', note }
 * refund  → everything still held goes back to the customer; an undelivered order is cancelled
 * release → delivered orders pay the vendor now; undelivered orders carry on as normal
 */
const adminResolveDispute = asyncHandler(async (req, res) => {
  const disputeId = intParam(req.params.id);
  const { resolution } = req.body;
  const note = (req.body.note || '').trim() || null;
  if (!['refund', 'release'].includes(resolution)) throw httpError(400, "resolution must be 'refund' or 'release'.");

  const result = await withTransaction(async (client, afterCommit) => {
    const d = (await client.query('SELECT * FROM disputes WHERE id = $1 FOR UPDATE', [disputeId])).rows[0];
    if (!d) throw httpError(404, 'Dispute not found.');
    if (d.status !== 'open') throw httpError(409, 'This dispute has already been resolved.');

    const order = (await client.query('SELECT * FROM orders WHERE id = $1 FOR UPDATE', [d.order_id])).rows[0];
    let outcome;

    if (resolution === 'refund') {
      if (order.status !== 'delivered') {
        await releaseOrderLocks(client, afterCommit, order.id, `Refunded after dispute #${disputeId}`);
        await client.query(
          `UPDATE orders SET status = 'cancelled', cancellation_reason = $1, updated_at = NOW() WHERE id = $2`,
          [`Refunded after dispute #${disputeId}`, order.id]
        );
        if (order.rider_user_id) await client.query('UPDATE riders SET is_available = true WHERE user_id = $1', [order.rider_user_id]);
      }
      const { refund } = await refundEscrow(client, afterCommit, order.id, {
        note: `Dispute #${disputeId} refund for Order #${order.id}`, allowFrom: ['disputed'],
      });
      outcome = `Rs. ${refund.toFixed(2)} refunded to the customer.`;
    } else if (order.status === 'delivered') {
      const { vendorShare } = await releaseEscrow(client, afterCommit, order.id, {
        note: `Dispute #${disputeId} resolved — escrow released for Order #${order.id}`, allowFrom: ['disputed'],
      });
      outcome = `Rs. ${vendorShare.toFixed(2)} released to the store.`;
    } else {
      await client.query(`UPDATE orders SET escrow_status = 'held', updated_at = NOW() WHERE id = $1`, [order.id]);
      outcome = 'Order continues; payment will be released after delivery.';
    }

    await client.query(
      `UPDATE disputes SET status = 'resolved', resolution = $1, admin_note = $2, resolved_by = $3, resolved_at = NOW()
       WHERE id = $4`,
      [resolution, note, req.user.userId, disputeId]
    );

    const parties = await orderParties(client, order.id);
    for (const userId of [parties.customer_id, parties.vendor_user_id, parties.rider_user_id]) {
      await notify(client, afterCommit, userId, {
        type: 'dispute_resolved', orderId: order.id,
        title: `Dispute on Order #${order.id} resolved`,
        body: note ? `${outcome} Admin note: ${note}` : outcome,
      });
    }
    return { disputeId, resolution, outcome };
  });

  res.json({ success: true, message: result.outcome, data: result });
});

module.exports = {
  ISSUE_TYPES,
  createDispute,
  getMyDisputes,
  getDispute,
  adminListDisputes,
  adminResolveDispute,
};
