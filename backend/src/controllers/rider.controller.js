// ══════════════════════════════════════════════════════════════
// Vendra Backend - Rider Controller (FR03, FR04)
// Availability, GPS pings, task feed, delivery state, earnings
// ══════════════════════════════════════════════════════════════

const pool = require('../db');
const { consumeOrderLocks } = require('../services/inventory.service');
const { payRider, scheduleEscrowRelease } = require('../services/orderSettlement.service');
const { announceOrder, notifyAdmins } = require('../services/notification.service');
const { getPolicies } = require('../services/policy.service');
const { computeTrip, estimatePayoutPaisa, estimatePayoutBreakdown } = require('../services/riderPayout.service');
const { verifyHandoverOtp, withHandoverOtp } = require('../services/handoverOtp.service');
const { readRiderDocuments } = require('../services/riderDocuments');
const { emitToRiders, emitToTrackers } = require('../realtime');
const { httpError, asyncHandler, withTransaction, intParam, paging, pageOf } = require('../utils/http');
const { FEATURES } = require('../config/mode');
const { haversineKm, isValidCoordinate } = require('../utils/geo');
const { toPaisa, paisaToNumber } = require('../utils/money');
const { shortName, contactWhile } = require('../utils/privacy');

const ACTIVE_STATUSES = ['ready_for_pickup', 'picked', 'on_the_way'];
const num = (v) => (v == null ? null : Number(v));

/**
 * A position from the rider app. source: 'gps' (device) or 'manual' (set by hand or a
 * simulated drive). Manual positions are accepted only while FEATURES.manualLocation is on.
 */
function readPoint(body) {
  const lat = Number(body.lat ?? body.latitude);
  const lng = Number(body.lng ?? body.longitude);
  if (!isValidCoordinate(lat, lng)) throw httpError(400, 'A valid lat and lng are required.');
  if (body.source === 'manual' && !FEATURES.manualLocation) {
    throw httpError(403, 'Manual locations are turned off. Allow location access so the app can use GPS.', { code: 'MANUAL_LOCATION_DISABLED' });
  }
  return { lat, lng };
}

async function riderRow(db, userId) {
  const r = await db.query('SELECT * FROM riders WHERE user_id = $1', [userId]);
  if (r.rows.length === 0) throw httpError(404, 'Rider profile not found.');
  return r.rows[0];
}

/** New riders deliver only after an admin has checked their CNIC, licence and vehicle */
function assertApproved(rider) {
  if (rider.approval_status === 'approved') return;
  throw httpError(403,
    rider.approval_status === 'rejected'
      ? `Your documents were not approved${rider.rejection_reason ? `: ${rider.rejection_reason}` : ''}. Update them in Profile and resubmit.`
      : 'Your documents are being reviewed. You can go online once an admin approves your account.',
    { code: 'RIDER_NOT_APPROVED', approvalStatus: rider.approval_status });
}

async function activeOrderId(db, riderUserId) {
  const r = await db.query(
    `SELECT id FROM orders WHERE rider_user_id = $1 AND status = ANY($2::order_status[]) ORDER BY assigned_at DESC LIMIT 1`,
    [riderUserId, ACTIVE_STATUSES]
  );
  return r.rows[0]?.id || null;
}

const RIDER_ORDER_SELECT = `
  SELECT o.*, v.store_name, v.store_address, v.latitude AS store_lat, v.longitude AS store_lng,
         vu.phone AS store_phone, cu.full_name AS customer_name, cu.phone AS customer_phone,
         (SELECT COALESCE(SUM(quantity), 0) FROM order_items WHERE order_id = o.id) AS item_count,
         pw.weight_grams AS parcel_weight_grams, pw.unweighed_lines
  FROM orders o
  CROSS JOIN LATERAL (
    SELECT COALESCE(SUM(oi.quantity * p.weight_grams), 0) AS weight_grams,
           COUNT(*) FILTER (WHERE p.weight_grams IS NULL) AS unweighed_lines
    FROM order_items oi JOIN products p ON p.id = oi.product_id WHERE oi.order_id = o.id
  ) pw
  JOIN vendors v ON v.id = o.vendor_id
  JOIN users vu ON vu.id = v.user_id
  JOIN users cu ON cu.id = o.customer_id`;

/** The rider ($1) lost this order once for not reaching the store (task hoarding guard) */
const LAPSED_BY_RIDER = `EXISTS (SELECT 1 FROM trust_events te
  WHERE te.order_id = o.id AND te.user_id = $1 AND te.kind = 'rider_task_timeout')`;

function formatRiderOrder(o) {
  return {
    id: o.id,
    status: o.status,
    storeName: o.store_name,
    storeAddress: o.store_address,
    storePhone: o.store_phone,
    storeLat: num(o.store_lat),
    storeLng: num(o.store_lng),
    // The rider gets a short name, and the number only while delivering
    customerName: shortName(o.customer_name),
    customerPhone: contactWhile(o.status, o.customer_phone),
    deliveryAddress: o.delivery_address,
    deliveryNote: o.delivery_note || null,
    customerLat: num(o.customer_lat),
    customerLng: num(o.customer_lng),
    itemCount: Number(o.item_count),
    // Parcel weight from the products' listed weights; incomplete when some product has none
    parcelWeightGrams: Number(o.parcel_weight_grams),
    parcelWeightComplete: Number(o.unweighed_lines) === 0,
    totalAmount: Number(o.total_amount),
    assignedAt: o.assigned_at,
    arrivedAt: o.rider_arrived_at,
    pickedAt: o.picked_at,
    deliveredAt: o.delivered_at,
    distanceKm: num(o.distance_km),
    waitMinutes: num(o.wait_minutes),
    payout: Number(o.rider_payout),
    payoutBreakdown: o.payout_breakdown || null,
    // The customer's handover code is needed to finish; the rider never sees it
    otpRequired: Boolean(o.delivery_otp) && !o.otp_verified_at,
    customerRating: o.rider_rating ?? null,
  };
}

function riderProfileView(r) {
  return {
    isOnline: r.is_online,
    vehicleType: r.vehicle_type,
    cnic: r.cnic,
    licenseNumber: r.license_number,
    vehicleNumber: r.vehicle_number,
    approvalStatus: r.approval_status,
    rejectionReason: r.approval_status === 'rejected' ? r.rejection_reason : null,
    currentLat: num(r.current_lat),
    currentLng: num(r.current_lng),
    lastLocationAt: r.last_location_at,
  };
}

/** GET /api/rider/profile */
const getProfile = asyncHandler(async (req, res) => {
  const r = await riderRow(pool, req.user.userId);
  res.json({
    success: true,
    data: { ...riderProfileView(r), activeOrderId: await activeOrderId(pool, req.user.userId) },
  });
});

/**
 * PUT /api/rider/documents  Body: { cnic, licenseNumber, vehicleNumber, vehicleType? }
 * Fills in or corrects the documents; a rejected rider goes back in the review queue.
 * An approved rider who changes them is reviewed again too (they go offline).
 */
const updateDocuments = asyncHandler(async (req, res) => {
  const rider = await withTransaction(async (client, afterCommit) => {
    const current = (await client.query('SELECT * FROM riders WHERE user_id = $1 FOR UPDATE', [req.user.userId])).rows[0];
    if (!current) throw httpError(404, 'Rider profile not found.');
    const docs = readRiderDocuments({ ...req.body, vehicleType: req.body.vehicleType || current.vehicle_type });
    if (await activeOrderId(client, req.user.userId)) throw httpError(409, 'Finish your active delivery before changing your documents.');
    const changed = current.cnic !== docs.cnic || current.license_number !== docs.licenseNumber
      || current.vehicle_number !== docs.vehicleNumber || (docs.vehicleType && docs.vehicleType !== current.vehicle_type);
    const resubmit = current.approval_status === 'rejected' || (changed && current.approval_status === 'approved');
    const r = await client.query(
      `UPDATE riders SET cnic = $1, license_number = $2, vehicle_number = $3, vehicle_type = COALESCE($4, vehicle_type),
              approval_status = CASE WHEN $5::boolean THEN 'pending' ELSE approval_status END,
              is_online = CASE WHEN $5::boolean THEN false ELSE is_online END,
              rejection_reason = CASE WHEN $5::boolean THEN NULL ELSE rejection_reason END
       WHERE user_id = $6 RETURNING *`,
      [docs.cnic, docs.licenseNumber, docs.vehicleNumber, docs.vehicleType, resubmit, req.user.userId]
    );
    if (resubmit) {
      const name = (await client.query('SELECT full_name FROM users WHERE id = $1', [req.user.userId])).rows[0].full_name;
      await notifyAdmins(client, afterCommit, {
        type: 'rider_pending',
        title: `${name} sent rider documents`,
        body: 'Check the CNIC, licence and vehicle in Riders.',
      });
    }
    return r.rows[0];
  });
  res.json({
    success: true,
    message: rider.approval_status === 'pending' ? 'Documents sent. An admin will review them shortly.' : 'Documents saved.',
    data: riderProfileView(rider),
  });
});

/** PUT /api/rider/status  Body: { isOnline, lat?, lng? } */
const setStatus = asyncHandler(async (req, res) => {
  const isOnline = req.body.isOnline === true;
  const point = req.body.lat != null ? readPoint(req.body) : null;

  if (isOnline) assertApproved(await riderRow(pool, req.user.userId));
  if (!isOnline && await activeOrderId(pool, req.user.userId)) {
    throw httpError(409, 'Finish your active delivery before going offline.', { code: 'ACTIVE_DELIVERY' });
  }
  const r = await pool.query(
    `UPDATE riders SET is_online = $1,
            current_lat = COALESCE($2, current_lat), current_lng = COALESCE($3, current_lng),
            last_location_at = CASE WHEN $2::float8 IS NULL THEN last_location_at ELSE NOW() END
     WHERE user_id = $4 RETURNING is_online`,
    [isOnline, point?.lat ?? null, point?.lng ?? null, req.user.userId]
  );
  if (r.rows.length === 0) throw httpError(404, 'Rider profile not found.');
  res.json({ success: true, message: isOnline ? 'You are online.' : 'You are offline.', data: { isOnline: r.rows[0].is_online } });
});

/**
 * POST /api/rider/location  Body: { lat, lng }
 * Sent every 10 s while online (PR 03). During a delivery the point is stored
 * against the order (payout distance) and pushed to whoever is watching that
 * order's map right now (track:<orderId>); nobody watching, nothing is sent.
 */
const postLocation = asyncHandler(async (req, res) => {
  const point = readPoint(req.body);

  // One round trip: move the rider, find their active delivery, store the ping against it
  const r = await pool.query(
    `WITH moved AS (
       UPDATE riders SET current_lat = $1, current_lng = $2, last_location_at = NOW()
       WHERE user_id = $3 RETURNING user_id
     ), active AS (
       SELECT id FROM orders
       WHERE rider_user_id = $3 AND status = ANY($4::order_status[])
       ORDER BY assigned_at DESC LIMIT 1
     ), ping AS (
       INSERT INTO rider_locations (rider_user_id, order_id, latitude, longitude)
       SELECT $3, active.id, $1, $2 FROM active
       RETURNING order_id, recorded_at
     )
     SELECT (SELECT COUNT(*) FROM moved) AS moved, active.id AS order_id, ping.recorded_at
     FROM (SELECT 1) one
     LEFT JOIN active ON true
     LEFT JOIN ping ON ping.order_id = active.id`,
    [point.lat, point.lng, req.user.userId, ACTIVE_STATUSES]
  );
  const row = r.rows[0];
  if (Number(row.moved) === 0) throw httpError(404, 'Rider profile not found.');

  if (row.order_id) {
    emitToTrackers(row.order_id, 'rider:location', {
      orderId: row.order_id, lat: point.lat, lng: point.lng, at: row.recorded_at,
    });
  }
  res.json({ success: true, data: { orderId: row.order_id || null } });
});

/**
 * GET /api/rider/tasks — ready delivery orders from stores within the policy radius
 */
const getTasks = asyncHandler(async (req, res) => {
  const rider = await riderRow(pool, req.user.userId);
  const activeId = await activeOrderId(pool, req.user.userId);
  const policies = await getPolicies();
  const empty = (reason) => res.json({
    success: true,
    data: { tasks: [], activeOrderId: activeId, reason, radiusKm: policies.task_radius_km },
  });
  if (rider.approval_status !== 'approved') return empty('not_approved');
  if (!rider.is_online) return empty('offline');
  if (activeId) return empty('busy');
  if (rider.current_lat == null) return empty('no_location');

  const r = await pool.query(
    `${RIDER_ORDER_SELECT}
     WHERE o.status = 'ready_for_pickup' AND o.delivery_type = 'delivery' AND o.rider_user_id IS NULL
       AND NOT ${LAPSED_BY_RIDER}
     ORDER BY o.ready_at NULLS LAST, o.created_at`,
    [req.user.userId]
  );

  const tasks = r.rows
    .map((o) => {
      const toStoreKm = o.store_lat != null
        ? haversineKm(rider.current_lat, rider.current_lng, o.store_lat, o.store_lng)
        : null;
      const tripKm = o.store_lat != null && o.customer_lat != null
        ? haversineKm(o.store_lat, o.store_lng, o.customer_lat, o.customer_lng)
        : null;
      return {
        ...formatRiderOrder(o),
        // Open tasks go to every nearby rider: no customer identity until one accepts
        customerName: null,
        customerPhone: null,
        deliveryNote: null, // may hold a gate code: only for the rider who accepts
        readyAt: o.ready_at,
        distanceToStoreKm: toStoreKm == null ? null : Math.round(toStoreKm * 100) / 100,
        tripDistanceKm: tripKm == null ? null : Math.round(tripKm * 100) / 100,
        estimatedPayout: paisaToNumber(estimatePayoutPaisa(policies, num(o.store_lat), num(o.store_lng), num(o.customer_lat), num(o.customer_lng))),
        estimatedPayoutBreakdown: estimatePayoutBreakdown(policies, num(o.store_lat), num(o.store_lng), num(o.customer_lat), num(o.customer_lng)),
      };
    })
    .filter((t) => t.distanceToStoreKm == null || t.distanceToStoreKm <= policies.task_radius_km)
    .sort((a, b) => (a.distanceToStoreKm ?? Infinity) - (b.distanceToStoreKm ?? Infinity));

  res.json({ success: true, data: { tasks, activeOrderId: null, radiusKm: policies.task_radius_km } });
});

/** Busy-ness of one store for idle riders: orders placed in the last hour and deliveries waiting for a rider */
function demandLevel(lastHour, waiting) {
  if (waiting >= 2 || lastHour >= 6) return 'high';
  if (waiting >= 1 || lastHour >= 2) return 'medium';
  return 'low';
}

/**
 * GET /api/rider/demand — where the work is (idle riders, "demand map").
 * Stores within DEMAND_RADIUS_KM of the rider with delivery orders today: orders in the
 * last hour, orders waiting for a rider now, and a level (high / medium / low).
 * Counts only; no customer data.
 */
const DEMAND_RADIUS_KM = 25;
const getDemand = asyncHandler(async (req, res) => {
  const rider = await riderRow(pool, req.user.userId);
  const r = await pool.query(
    `SELECT v.id, v.store_name, v.latitude, v.longitude,
            COUNT(o.id) FILTER (WHERE o.created_at >= NOW() - INTERVAL '1 hour')::int AS last_hour,
            COUNT(o.id)::int AS today,
            COUNT(o.id) FILTER (WHERE o.status = 'ready_for_pickup' AND o.rider_user_id IS NULL)::int AS waiting
     FROM vendors v
     JOIN orders o ON o.vendor_id = v.id AND o.delivery_type = 'delivery' AND o.status <> 'cancelled'
                  AND o.created_at >= date_trunc('day', NOW())
     WHERE v.is_approved AND v.latitude IS NOT NULL
     GROUP BY v.id`
  );
  const near = (s) => rider.current_lat == null
    || haversineKm(rider.current_lat, rider.current_lng, s.latitude, s.longitude) <= DEMAND_RADIUS_KM;
  const zones = r.rows.filter(near).map((s) => ({
    vendorId: s.id,
    storeName: s.store_name,
    lat: Number(s.latitude),
    lng: Number(s.longitude),
    ordersLastHour: s.last_hour,
    ordersToday: s.today,
    waitingForRider: s.waiting,
    level: demandLevel(s.last_hour, s.waiting),
  }));
  const rank = { high: 0, medium: 1, low: 2 };
  zones.sort((a, b) => rank[a.level] - rank[b.level] || b.ordersLastHour - a.ordersLastHour);
  res.json({ success: true, data: { zones, radiusKm: DEMAND_RADIUS_KM } });
});

/** POST /api/rider/tasks/:id/accept — first rider wins (single conditional UPDATE) */
const acceptTask = asyncHandler(async (req, res) => {
  const orderId = intParam(req.params.id);
  const riderUserId = req.user.userId;

  const order = await withTransaction(async (client, afterCommit) => {
    const rider = (await client.query('SELECT * FROM riders WHERE user_id = $1 FOR UPDATE', [riderUserId])).rows[0];
    if (!rider) throw httpError(404, 'Rider profile not found.');
    assertApproved(rider);
    if (!rider.is_online) throw httpError(409, 'Go online to accept deliveries.');
    if (await activeOrderId(client, riderUserId)) throw httpError(409, 'Finish your current delivery first.');
    const lapsed = await client.query(`SELECT 1 FROM orders o WHERE o.id = $2 AND ${LAPSED_BY_RIDER}`, [riderUserId, orderId]);
    if (lapsed.rows.length) {
      throw httpError(409, 'You let this delivery lapse before, so it is offered to other riders.', { code: 'TASK_LAPSED' });
    }

    const r = await client.query(
      `UPDATE orders SET rider_user_id = $1, assigned_at = NOW(), updated_at = NOW()
       WHERE id = $2 AND status = 'ready_for_pickup' AND delivery_type = 'delivery' AND rider_user_id IS NULL
       RETURNING *`,
      [riderUserId, orderId]
    );
    if (r.rows.length === 0) throw httpError(409, 'Another rider has already taken this delivery.', { code: 'TASK_TAKEN' });

    await client.query('UPDATE riders SET is_available = false WHERE user_id = $1', [riderUserId]);
    const riderName = shortName((await client.query('SELECT full_name FROM users WHERE id = $1', [riderUserId])).rows[0].full_name);
    await announceOrder(client, afterCommit, orderId, 'rider_assigned', {
      customer: { title: `Rider assigned to Order #${orderId}`, body: `${riderName} is heading to the store.` },
      vendor: { title: `Rider on the way for #${orderId}`, body: `${riderName} will collect this order.` },
    });
    afterCommit.push(() => emitToRiders('task:taken', { orderId }));
    return (await client.query(`${RIDER_ORDER_SELECT} WHERE o.id = $1`, [orderId])).rows[0];
  });

  res.json({ success: true, message: 'Delivery accepted. Head to the store.', data: formatRiderOrder(order) });
});

/** Loads the rider's own order and checks its status, inside a transaction */
async function lockOwnOrder(client, orderId, riderUserId, allowed) {
  const r = await client.query('SELECT * FROM orders WHERE id = $1 AND rider_user_id = $2 FOR UPDATE', [orderId, riderUserId]);
  if (r.rows.length === 0) throw httpError(404, 'Delivery not found.');
  if (!allowed.includes(r.rows[0].status)) throw httpError(409, `Order is ${r.rows[0].status}.`);
  return r.rows[0];
}

/** Pickup geofence: the rider must be within `pickup_geofence_m` of the store to say they're there */
async function assertAtStore(client, order, point) {
  const store = (await client.query('SELECT latitude, longitude FROM vendors WHERE id = $1', [order.vendor_id])).rows[0];
  if (!store || store.latitude == null) throw httpError(409, 'This store has no location to verify against.');
  const policies = await getPolicies(client);
  const limit = policies.pickup_geofence_m ?? policies.geofence_m;
  const distanceM = haversineKm(point.lat, point.lng, store.latitude, store.longitude) * 1000;
  if (distanceM > limit) {
    throw httpError(422,
      `You are ${Math.round(distanceM)} m from the store. Move within ${limit} m to continue.`,
      { code: 'OUTSIDE_PICKUP_GEOFENCE', distanceMeters: Math.round(distanceM), geofenceMeters: limit });
  }
}

/** POST /api/rider/orders/:id/arrived  Body: { lat, lng } — at the store (geofenced); waiting time starts */
const arrivedAtStore = asyncHandler(async (req, res) => {
  const orderId = intParam(req.params.id);
  const point = readPoint(req.body);
  await withTransaction(async (client, afterCommit) => {
    const o = await lockOwnOrder(client, orderId, req.user.userId, ['ready_for_pickup']);
    if (o.rider_arrived_at) return;
    await assertAtStore(client, o, point);
    await client.query('UPDATE orders SET rider_arrived_at = NOW(), updated_at = NOW() WHERE id = $1', [orderId]);
    await announceOrder(client, afterCommit, orderId, 'rider_arrived', {
      vendor: { title: `Rider arrived for #${orderId}`, body: 'Hand the order over to the rider.' },
    });
  });
  res.json({ success: true, message: 'Arrival recorded.' });
});

/** POST /api/rider/orders/:id/picked  Body: { lat, lng } — ready_for_pickup → picked (geofenced at the store) */
const markPicked = asyncHandler(async (req, res) => {
  const orderId = intParam(req.params.id);
  const point = readPoint(req.body);
  await withTransaction(async (client, afterCommit) => {
    const o = await lockOwnOrder(client, orderId, req.user.userId, ['ready_for_pickup']);
    await assertAtStore(client, o, point);
    await client.query(
      `UPDATE orders SET status = 'picked', picked_at = NOW(), pickup_confirmed_by = 'rider',
              rider_arrived_at = COALESCE(rider_arrived_at, NOW()), updated_at = NOW()
       WHERE id = $1`,
      [orderId]
    );
    await announceOrder(client, afterCommit, orderId, 'order_picked', {
      customer: { title: `Order #${orderId} picked up`, body: 'The rider has your order.' },
      vendor: { title: `Order #${orderId} collected`, body: 'The rider picked up the order.' },
    });
  });
  res.json({ success: true, message: 'Order picked up.' });
});

/** POST /api/rider/orders/:id/on-the-way — picked → on_the_way */
const markOnTheWay = asyncHandler(async (req, res) => {
  const orderId = intParam(req.params.id);
  await withTransaction(async (client, afterCommit) => {
    await lockOwnOrder(client, orderId, req.user.userId, ['picked']);
    await client.query(`UPDATE orders SET status = 'on_the_way', updated_at = NOW() WHERE id = $1`, [orderId]);
    await announceOrder(client, afterCommit, orderId, 'order_on_the_way', {
      customer: { title: `Order #${orderId} is on the way`, body: 'Track your rider live on the map.' },
    });
  });
  res.json({ success: true, message: 'On the way.' });
});

/**
 * POST /api/rider/orders/:id/deliver  Body: { lat, lng, otp }
 * Geofence (SSR 02): the rider must be within `geofence_m` of the customer's pin,
 * and enter the customer's 4-digit handover code (a spoofed GPS fix alone can't
 * complete a delivery). Then stock is deducted, the rider is paid from escrow,
 * and the dispute window starts.
 */
const deliverOrder = asyncHandler(async (req, res) => {
  const orderId = intParam(req.params.id);
  const point = readPoint(req.body);
  const riderUserId = req.user.userId;

  const result = await withHandoverOtp(async (client, afterCommit) => {
    const order = await lockOwnOrder(client, orderId, riderUserId, ['picked', 'on_the_way']);
    const policies = await getPolicies(client);

    if (order.customer_lat == null) throw httpError(409, 'This order has no customer location to verify against.');
    const distanceM = haversineKm(point.lat, point.lng, order.customer_lat, order.customer_lng) * 1000;
    if (distanceM > policies.geofence_m) {
      throw httpError(422,
        `You are ${Math.round(distanceM)} m from the customer's location. Move within ${policies.geofence_m} m to confirm delivery.`,
        { code: 'OUTSIDE_GEOFENCE', distanceMeters: Math.round(distanceM), geofenceMeters: policies.geofence_m });
    }
    await verifyHandoverOtp(client, order, req.body.otp);

    await client.query(
      `INSERT INTO rider_locations (rider_user_id, order_id, latitude, longitude) VALUES ($1, $2, $3, $4)`,
      [riderUserId, orderId, point.lat, point.lng]
    );
    const trip = await computeTrip(client, order, policies, point);

    await client.query(
      `UPDATE orders SET status = 'delivered', delivered_at = NOW(), updated_at = NOW(),
              delivery_lat = $1, delivery_lng = $2, distance_km = $3, wait_minutes = $4, payout_breakdown = $5
       WHERE id = $6`,
      [point.lat, point.lng, trip.distanceKm, trip.waitMinutes, JSON.stringify(trip.breakdown), orderId]
    );
    await consumeOrderLocks(client, afterCommit, orderId, 'Delivered by rider');
    await payRider(client, order, trip.payoutPaisa);
    await scheduleEscrowRelease(client, afterCommit, orderId);
    await client.query('UPDATE riders SET is_available = true WHERE user_id = $1', [riderUserId]);

    await announceOrder(client, afterCommit, orderId, 'order_delivered', {
      customer: { title: `Order #${orderId} delivered`, body: 'Something wrong? You can raise a dispute before payment is released.' },
      vendor: { title: `Order #${orderId} delivered`, body: 'Payment will be released after the dispute window.' },
      rider: { title: `Rs. ${paisaToNumber(trip.payoutPaisa).toFixed(2)} earned`, body: `${trip.distanceKm} km for Order #${orderId}.` },
    });

    return {
      orderId,
      distanceKm: trip.distanceKm,
      distanceSource: trip.distanceSource,
      waitMinutes: trip.waitMinutes,
      payout: paisaToNumber(trip.payoutPaisa),
      payoutBreakdown: trip.breakdown,
      distanceFromCustomerMeters: Math.round(distanceM),
    };
  });

  res.json({ success: true, message: 'Delivery confirmed.', data: result });
});

/** GET /api/rider/orders?scope=active|history&limit=&offset= (history is paginated) */
const getMyOrders = asyncHandler(async (req, res) => {
  const scope = req.query.scope === 'history' ? 'history' : 'active';
  if (scope === 'active') {
    const r = await pool.query(
      `${RIDER_ORDER_SELECT} WHERE o.rider_user_id = $1 AND o.status = ANY($2::order_status[]) ORDER BY o.assigned_at DESC`,
      [req.user.userId, ACTIVE_STATUSES]
    );
    return res.json({ success: true, data: r.rows.map(formatRiderOrder), meta: { scope, hasMore: false, nextOffset: null } });
  }
  const page = paging(req.query);
  const r = await pool.query(
    `${RIDER_ORDER_SELECT} WHERE o.rider_user_id = $1 AND NOT (o.status = ANY($2::order_status[]))
     ORDER BY COALESCE(o.delivered_at, o.assigned_at) DESC, o.id DESC LIMIT $3 OFFSET $4`,
    [req.user.userId, ACTIVE_STATUSES, page.limit + 1, page.offset]
  );
  const { items, meta } = pageOf(r.rows, page);
  res.json({ success: true, data: items.map(formatRiderOrder), meta: { scope, ...meta } });
});

/** GET /api/rider/earnings — totals + recent deliveries */
const getEarnings = asyncHandler(async (req, res) => {
  const userId = req.user.userId;
  const totals = await pool.query(
    `SELECT
       COALESCE(SUM(rider_payout) FILTER (WHERE delivered_at::date = CURRENT_DATE), 0) AS today,
       COUNT(*) FILTER (WHERE delivered_at::date = CURRENT_DATE) AS today_count,
       COALESCE(SUM(rider_payout) FILTER (WHERE delivered_at >= date_trunc('week', NOW())), 0) AS week,
       COUNT(*) FILTER (WHERE delivered_at >= date_trunc('week', NOW())) AS week_count,
       COALESCE(SUM(rider_payout), 0) AS all_time,
       COUNT(*) AS all_time_count,
       COALESCE(SUM(distance_km), 0) AS total_km,
       ROUND(AVG(rider_rating), 1)::float8 AS average_rating,
       COUNT(rider_rating) AS rating_count
     FROM orders WHERE rider_user_id = $1 AND status = 'delivered'`,
    [userId]
  );
  const wallet = await pool.query('SELECT wallet_balance FROM users WHERE id = $1', [userId]);
  const recent = await pool.query(
    `${RIDER_ORDER_SELECT} WHERE o.rider_user_id = $1 AND o.status = 'delivered' ORDER BY o.delivered_at DESC LIMIT 20`,
    [userId]
  );
  const t = totals.rows[0];
  res.json({
    success: true,
    data: {
      today: Number(t.today),
      todayCount: Number(t.today_count),
      week: Number(t.week),
      weekCount: Number(t.week_count),
      allTime: Number(t.all_time),
      allTimeCount: Number(t.all_time_count),
      totalKm: Number(t.total_km),
      averageRating: t.average_rating,
      ratingCount: Number(t.rating_count),
      walletBalance: paisaToNumber(toPaisa(wallet.rows[0].wallet_balance)),
      recent: recent.rows.map(formatRiderOrder),
    },
  });
});

module.exports = {
  getProfile,
  updateDocuments,
  setStatus,
  postLocation,
  getDemand,
  getTasks,
  acceptTask,
  arrivedAtStore,
  markPicked,
  markOnTheWay,
  deliverOrder,
  getMyOrders,
  getEarnings,
};
