// ══════════════════════════════════════════════════════════════
// Vendra Backend - Dispute Controller (FR08)
// Any party to an order (customer, vendor, rider) can raise a dispute
// while its escrow is still held. An open dispute freezes the escrow
// until an admin decides: refund the customer, release to the vendor, or
// split (part of the item subtotal back to the customer, the rest to the vendor).
// A rider who can't hand over (customer unavailable) files a GPS-tagged
// photo report from the customer's door; the escrow stays frozen.
// ══════════════════════════════════════════════════════════════

const pool = require('../db');
const { releaseOrderLocks } = require('../services/inventory.service');
const { refundEscrow, releaseEscrow } = require('../services/orderSettlement.service');
const { notify, notifyAdmins, orderParties } = require('../services/notification.service');
const { signedEvidenceUrl, removeEvidenceFiles } = require('../services/storage.service');
const { getPolicies } = require('../services/policy.service');
const { trustCountSql, TRUST_WINDOW_DAYS } = require('../services/trust.service');
const { httpError, asyncHandler, withTransaction, intParam } = require('../utils/http');
const { haversineKm, metersBetween, isValidCoordinate } = require('../utils/geo');
const { shortName } = require('../utils/privacy');
const { recordAudit } = require('../services/audit.service');

const ISSUE_TYPES = [
  'item_not_received', 'damaged_item', 'wrong_item', 'missing_items',
  'quality_issue', 'rider_issue', 'customer_issue', 'customer_unavailable', 'other',
];

/** Rider at the door, customer not answering: the parcel is still with the rider */
const UNAVAILABLE_STATUSES = ['picked', 'on_the_way'];

/** Optional reporter position from the form fields lat / lng */
function readReporterPoint(body) {
  if (body.lat == null || body.lat === '' || body.lng == null || body.lng === '') return null;
  const lat = Number(body.lat);
  const lng = Number(body.lng);
  if (!isValidCoordinate(lat, lng)) throw httpError(400, 'lat and lng must be a valid position.');
  return { lat, lng };
}

/**
 * "Customer unavailable" is the rider's alternative to the handover code: it needs a photo
 * of the door / gate and a GPS fix within the delivery geofence of the customer's pin.
 */
async function assertUnavailableReport(client, order, role, point, files) {
  if (role !== 'rider') throw httpError(403, 'Only the delivering rider can report the customer as unavailable.');
  if (!UNAVAILABLE_STATUSES.includes(order.status)) {
    throw httpError(409, "Report this from the customer's address, after picking up the order.");
  }
  if (files.length === 0) throw httpError(400, 'Add a photo of the door or gate as evidence.');
  if (!point) throw httpError(400, 'Your GPS position is required for this report.', { code: 'LOCATION_REQUIRED' });
  if (order.customer_lat == null) return;
  const { geofence_m: limit } = await getPolicies(client);
  const distanceM = haversineKm(point.lat, point.lng, order.customer_lat, order.customer_lng) * 1000;
  if (distanceM > limit) {
    throw httpError(422,
      `You are ${Math.round(distanceM)} m from the customer's location. Move within ${limit} m to report them unavailable.`,
      { code: 'OUTSIDE_GEOFENCE', distanceMeters: Math.round(distanceM), geofenceMeters: limit });
  }
}

function partyRole(order, userId) {
  if (order.customer_id === userId) return 'customer';
  if (order.vendor_user_id === userId) return 'vendor';
  if (order.rider_user_id === userId) return 'rider';
  return null;
}

const DISPUTE_SELECT = `
  SELECT d.*, u.full_name AS raised_by_name,
         o.status AS order_status, o.escrow_status, o.total_amount, o.rider_payout, o.delivery_type,
         o.customer_id, o.rider_user_id, o.vendor_id, v.store_name, v.user_id AS vendor_user_id,
         cu.full_name AS customer_name, ru.full_name AS rider_name,
         COALESCE((SELECT json_agg(json_build_object('id', e.id, 'url', e.file_url, 'name', e.original_name) ORDER BY e.id)
                   FROM dispute_evidence e WHERE e.dispute_id = d.id), '[]') AS evidence
  FROM disputes d
  JOIN users u ON u.id = d.raised_by
  JOIN orders o ON o.id = d.order_id
  JOIN vendors v ON v.id = o.vendor_id
  JOIN users cu ON cu.id = o.customer_id
  LEFT JOIN users ru ON ru.id = o.rider_user_id`;

/** Admins see full names; the parties to an order see each other's short names */
function formatDispute(d, { admin = false } = {}) {
  const name = admin ? (n) => n : (n) => shortName(n);
  return {
    id: d.id,
    orderId: d.order_id,
    issueType: d.issue_type,
    description: d.description,
    status: d.status,
    resolution: d.resolution,
    refundPct: d.refund_pct == null ? null : Number(d.refund_pct),
    adminNote: d.admin_note,
    reporterLat: d.reporter_lat,
    reporterLng: d.reporter_lng,
    raisedBy: { id: d.raised_by, name: name(d.raised_by_name), role: d.raised_by_role },
    order: {
      status: d.order_status,
      escrowStatus: d.escrow_status,
      totalAmount: Number(d.total_amount),
      heldAmount: Number(d.total_amount) - Number(d.rider_payout),
      deliveryType: d.delivery_type,
      storeName: d.store_name,
      customerName: name(d.customer_name),
      riderName: name(d.rider_name),
    },
    // Signed, expiring links — only people who can see the dispute get them
    evidence: d.evidence.map((e) => ({ id: e.id, url: signedEvidenceUrl(e.url), name: e.name })),
    createdAt: d.created_at,
    resolvedAt: d.resolved_at,
  };
}

/**
 * POST /api/disputes  (multipart/form-data)
 * Fields: orderId, issueType, description, lat?, lng?; files: evidence (up to 4 images)
 */
const createDispute = asyncHandler(async (req, res) => {
  const files = req.files || [];
  try {
    const orderId = intParam(req.body.orderId, 'orderId');
    const { issueType } = req.body;
    const description = (req.body.description || '').trim();
    if (!ISSUE_TYPES.includes(issueType)) throw httpError(400, `issueType must be one of: ${ISSUE_TYPES.join(', ')}.`);
    if (description.length < 10) throw httpError(400, 'Describe the problem in at least 10 characters.');
    const point = readReporterPoint(req.body);

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
      if (issueType === 'customer_unavailable') await assertUnavailableReport(client, order, role, point, files);

      const d = (await client.query(
        `INSERT INTO disputes (order_id, raised_by, raised_by_role, issue_type, description, reporter_lat, reporter_lng)
         VALUES ($1, $2, $3, $4, $5, $6, $7) RETURNING *`,
        [orderId, req.user.userId, role, issueType, description, point?.lat ?? null, point?.lng ?? null]
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
  res.json({ success: true, data: formatDispute(d, { admin: !isParty }) });
});

/** GET /api/admin/disputes?status=open|resolved|all */
const adminListDisputes = asyncHandler(async (req, res) => {
  const status = ['open', 'resolved'].includes(req.query.status) ? req.query.status : null;
  const r = await pool.query(
    `${DISPUTE_SELECT} ${status ? 'WHERE d.status = $1' : ''} ORDER BY (d.status = 'open') DESC, d.created_at DESC`,
    status ? [status] : []
  );
  res.json({ success: true, data: r.rows.map((x) => formatDispute(x, { admin: true })) });
});

/**
 * PUT /api/admin/disputes/:id/resolve  Body: { resolution: 'refund'|'release'|'split', refundPct?, note }
 * refund  → everything still held goes back to the customer; an undelivered order is cancelled
 * release → delivered orders pay the vendor now; undelivered orders carry on as normal
 * split   → delivered orders only: refundPct (1–99) % of the item subtotal back to the
 *           customer, the rest released to the vendor (commission on its part only)
 */
const adminResolveDispute = asyncHandler(async (req, res) => {
  const disputeId = intParam(req.params.id);
  const { resolution } = req.body;
  const note = (req.body.note || '').trim() || null;
  if (!['refund', 'release', 'split'].includes(resolution)) {
    throw httpError(400, "resolution must be 'refund', 'release' or 'split'.");
  }
  const refundPct = resolution === 'split' ? Number(req.body.refundPct) : null;
  if (resolution === 'split' && !(Number.isFinite(refundPct) && refundPct >= 1 && refundPct <= 99)) {
    throw httpError(400, 'refundPct must be between 1 and 99 for a split.');
  }

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
    } else if (resolution === 'split') {
      if (order.status !== 'delivered') throw httpError(409, 'A split is only possible once the order has been delivered.');
      const { vendorShare, customerRefund } = await releaseEscrow(client, afterCommit, order.id, {
        note: `Dispute #${disputeId} split: ${100 - refundPct}% of items released for Order #${order.id}`,
        allowFrom: ['disputed'],
        refundPct,
      });
      outcome = `Rs. ${customerRefund.toFixed(2)} refunded to the customer and Rs. ${vendorShare.toFixed(2)} released to the store.`;
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
      `UPDATE disputes SET status = 'resolved', resolution = $1, admin_note = $2, resolved_by = $3, resolved_at = NOW(),
              refund_pct = $5
       WHERE id = $4`,
      [resolution, note, req.user.userId, disputeId, refundPct]
    );
    await recordAudit(client, req, {
      action: 'dispute_resolved',
      targetType: 'dispute',
      targetId: disputeId,
      summary: `Ruled ${resolution}${resolution === 'split' ? ` (${refundPct}% back)` : ''} on dispute #${disputeId} (Order #${order.id}): ${outcome}`,
      details: { orderId: order.id, resolution, refundPct, note },
    });

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

const num = (v) => (v == null ? null : Number(v));

/**
 * GET /api/admin/disputes/:id/dossier — the evidence an admin compares side by side (FR08):
 *   claim    what was reported, by whom, the photos and (riders) where they stood
 *   store    the order lines as listed in the catalog and the packing record (FR07)
 *   delivery the rider's timeline, waiting time, handover position and GPS trail
 *   history  each party's track record: the customer's earlier claims and how they
 *            ended (false-dispute trap), the store's and the rider's abuse signals
 * The trail is kept until the escrow settles, so it is there while a dispute is open.
 */
const adminDisputeDossier = asyncHandler(async (req, res) => {
  const r = await pool.query(`${DISPUTE_SELECT} WHERE d.id = $1`, [intParam(req.params.id)]);
  const d = r.rows[0];
  if (!d) throw httpError(404, 'Dispute not found.');

  const [orderRes, itemsRes, trailRes, historyRes, policies] = await Promise.all([
    pool.query(
      `SELECT o.*, v.store_name, v.store_address, v.latitude AS store_lat, v.longitude AS store_lng,
              cu.full_name AS customer_name, cu.phone AS customer_phone,
              ru.full_name AS rider_name, ru.phone AS rider_phone, pk.full_name AS packed_by_name
       FROM orders o
       JOIN vendors v ON v.id = o.vendor_id
       JOIN users cu ON cu.id = o.customer_id
       LEFT JOIN users ru ON ru.id = o.rider_user_id
       LEFT JOIN vendor_staff pk ON pk.id = o.packed_by_staff_id
       WHERE o.id = $1`,
      [d.order_id]
    ),
    pool.query(
      `SELECT oi.id, oi.product_id, oi.quantity, oi.unit_price, oi.packed_quantity,
              p.name, p.image_url, p.barcode, p.weight_grams, c.name AS category_name
       FROM order_items oi JOIN products p ON p.id = oi.product_id LEFT JOIN categories c ON c.id = p.category_id
       WHERE oi.order_id = $1 ORDER BY oi.id`,
      [d.order_id]
    ),
    pool.query(
      `SELECT latitude, longitude, recorded_at FROM rider_locations WHERE order_id = $1 ORDER BY recorded_at LIMIT 500`,
      [d.order_id]
    ),
    pool.query(
      `SELECT
         (SELECT COUNT(*)::int FROM orders WHERE customer_id = $2 AND status = 'delivered') AS customer_orders,
         (SELECT COUNT(*)::int FROM disputes WHERE raised_by = $2 AND id <> $1) AS customer_claims,
         (SELECT COUNT(*)::int FROM disputes WHERE raised_by = $2 AND id <> $1 AND resolution = 'release') AS customer_claims_rejected,
         (SELECT COUNT(*)::int FROM disputes WHERE raised_by = $2 AND id <> $1 AND resolution IN ('refund', 'split')) AS customer_claims_upheld,
         ${trustCountSql('walk_in_override', 'vendor_id', '$3')} AS store_walk_in_overrides,
         (SELECT COUNT(*)::int FROM disputes x JOIN orders xo ON xo.id = x.order_id
           WHERE xo.vendor_id = $3 AND x.id <> $1 AND x.resolution IN ('refund', 'split')) AS store_claims_upheld,
         (SELECT COUNT(*)::int FROM orders WHERE rider_user_id = $4 AND status = 'delivered') AS rider_deliveries,
         ${trustCountSql('rider_task_timeout', 'user_id', '$4')} AS rider_task_timeouts,
         ${trustCountSql('handover_lockout', 'user_id', '$4')} AS rider_handover_lockouts`,
      [d.id, d.customer_id, d.vendor_id, d.rider_user_id]
    ),
    getPolicies(),
  ]);
  const o = orderRes.rows[0];
  const waitMinutes = o.wait_minutes != null
    ? Number(o.wait_minutes)
    : (o.rider_arrived_at
      ? Math.max(0, (new Date(o.picked_at || Date.now()) - new Date(o.rider_arrived_at)) / 60000)
      : null);

  res.json({
    success: true,
    data: {
      dispute: formatDispute(d, { admin: true }),
      claim: {
        role: d.raised_by_role,
        name: d.raised_by_name,
        issueType: d.issue_type,
        description: d.description,
        createdAt: d.created_at,
        reporterLat: num(d.reporter_lat),
        reporterLng: num(d.reporter_lng),
        reporterDistanceFromPinMeters: metersBetween(d.reporter_lat, d.reporter_lng, o.customer_lat, o.customer_lng),
        evidence: formatDispute(d, { admin: true }).evidence,
      },
      store: {
        name: o.store_name,
        address: o.store_address,
        items: itemsRes.rows.map((i) => ({
          id: i.id,
          productId: i.product_id,
          name: i.name,
          category: i.category_name,
          quantity: i.quantity,
          unitPrice: Number(i.unit_price),
          packedQuantity: i.packed_quantity,
          imageUrl: i.image_url,
          barcode: i.barcode,
          weightGrams: i.weight_grams,
        })),
        packedAt: o.packed_at,
        packedByName: o.packed_by_name,
        readyAt: o.ready_at,
        fullyPacked: itemsRes.rows.length > 0 && itemsRes.rows.every((i) => i.packed_quantity >= i.quantity),
      },
      delivery: {
        orderId: o.id,
        status: o.status,
        deliveryType: o.delivery_type,
        escrowStatus: o.escrow_status,
        escrowReleaseDueAt: o.escrow_release_due_at,
        placedAt: o.created_at,
        subtotal: Number(o.subtotal ?? o.total_amount),
        deliveryFee: Number(o.delivery_fee),
        totalAmount: Number(o.total_amount),
        riderPayout: Number(o.rider_payout),
        heldAmount: Number(o.total_amount) - Number(o.rider_payout),
        customerName: o.customer_name,
        customerPhone: o.customer_phone,
        riderName: o.rider_name,
        riderPhone: o.rider_phone,
        assignedAt: o.assigned_at,
        arrivedAt: o.rider_arrived_at,
        pickedAt: o.picked_at,
        deliveredAt: o.delivered_at,
        handoverCodeVerifiedAt: o.otp_verified_at,
        waitMinutes: waitMinutes == null ? null : Math.round(waitMinutes * 10) / 10,
        freeWaitMinutes: policies.rider_free_wait_min,
        distanceKm: num(o.distance_km),
        store: { lat: num(o.store_lat), lng: num(o.store_lng) },
        customerPin: { lat: num(o.customer_lat), lng: num(o.customer_lng) },
        handover: o.delivery_lat == null ? null : { lat: num(o.delivery_lat), lng: num(o.delivery_lng) },
        handoverDistanceFromPinMeters: metersBetween(o.delivery_lat, o.delivery_lng, o.customer_lat, o.customer_lng),
        geofenceMeters: policies.geofence_m,
        trail: trailRes.rows.map((t) => ({ lat: num(t.latitude), lng: num(t.longitude), at: t.recorded_at })),
      },
      history: historyView(historyRes.rows[0], d.rider_user_id != null),
      commissionPct: policies.commission_pct,
    },
  });
});

/** The parties' track records for the dossier (abuse signals over the last 30 days) */
function historyView(h, hasRider) {
  return {
    customer: {
      deliveredOrders: h.customer_orders,
      earlierClaims: h.customer_claims,
      claimsRejected: h.customer_claims_rejected,
      claimsUpheld: h.customer_claims_upheld,
    },
    store: { walkInOverrides: h.store_walk_in_overrides, claimsUpheld: h.store_claims_upheld },
    rider: hasRider
      ? { deliveries: h.rider_deliveries, taskTimeouts: h.rider_task_timeouts, handoverLockouts: h.rider_handover_lockouts }
      : null,
    windowDays: TRUST_WINDOW_DAYS,
  };
}

module.exports = {
  ISSUE_TYPES,
  createDispute,
  getMyDisputes,
  getDispute,
  adminListDisputes,
  adminResolveDispute,
  adminDisputeDossier,
};
