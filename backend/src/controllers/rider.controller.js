// ══════════════════════════════════════════════════════════════
// Vendra Backend - Rider Controller (FR03, FR04)
// Availability, GPS pings, task feed, delivery state, earnings
// ══════════════════════════════════════════════════════════════

const pool = require('../db');
const { consumeOrderLocks } = require('../services/inventory.service');
const { payRider, scheduleEscrowRelease } = require('../services/orderSettlement.service');
const { announceOrder } = require('../services/notification.service');
const { getPolicies } = require('../services/policy.service');
const { computeTrip, estimatePayoutPaisa } = require('../services/riderPayout.service');
const { emitToRiders, emitToUser } = require('../realtime');
const { httpError, asyncHandler, withTransaction, intParam, paging, pageOf } = require('../utils/http');
const { haversineKm, isValidCoordinate } = require('../utils/geo');
const { toPaisa, paisaToNumber } = require('../utils/money');

const ACTIVE_STATUSES = ['ready_for_pickup', 'picked', 'on_the_way'];
const num = (v) => (v == null ? null : Number(v));

function readPoint(body) {
  const lat = Number(body.lat ?? body.latitude);
  const lng = Number(body.lng ?? body.longitude);
  if (!isValidCoordinate(lat, lng)) throw httpError(400, 'A valid lat and lng are required.');
  return { lat, lng };
}

async function riderRow(db, userId) {
  const r = await db.query('SELECT * FROM riders WHERE user_id = $1', [userId]);
  if (r.rows.length === 0) throw httpError(404, 'Rider profile not found.');
  return r.rows[0];
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
         (SELECT COALESCE(SUM(quantity), 0) FROM order_items WHERE order_id = o.id) AS item_count
  FROM orders o
  JOIN vendors v ON v.id = o.vendor_id
  JOIN users vu ON vu.id = v.user_id
  JOIN users cu ON cu.id = o.customer_id`;

function formatRiderOrder(o) {
  return {
    id: o.id,
    status: o.status,
    storeName: o.store_name,
    storeAddress: o.store_address,
    storePhone: o.store_phone,
    storeLat: num(o.store_lat),
    storeLng: num(o.store_lng),
    customerName: o.customer_name,
    customerPhone: o.customer_phone,
    deliveryAddress: o.delivery_address,
    customerLat: num(o.customer_lat),
    customerLng: num(o.customer_lng),
    itemCount: Number(o.item_count),
    totalAmount: Number(o.total_amount),
    assignedAt: o.assigned_at,
    arrivedAt: o.rider_arrived_at,
    pickedAt: o.picked_at,
    deliveredAt: o.delivered_at,
    distanceKm: num(o.distance_km),
    waitMinutes: num(o.wait_minutes),
    payout: Number(o.rider_payout),
  };
}

/** GET /api/rider/profile */
const getProfile = asyncHandler(async (req, res) => {
  const r = await riderRow(pool, req.user.userId);
  res.json({
    success: true,
    data: {
      isOnline: r.is_online,
      vehicleType: r.vehicle_type,
      currentLat: num(r.current_lat),
      currentLng: num(r.current_lng),
      lastLocationAt: r.last_location_at,
      activeOrderId: await activeOrderId(pool, req.user.userId),
    },
  });
});

/** PUT /api/rider/status  Body: { isOnline, lat?, lng? } */
const setStatus = asyncHandler(async (req, res) => {
  const isOnline = req.body.isOnline === true;
  const point = req.body.lat != null ? readPoint(req.body) : null;

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
 * against the order (payout distance) and pushed to the customer's map.
 */
const postLocation = asyncHandler(async (req, res) => {
  const point = readPoint(req.body);

  // One round trip: move the rider, find their active delivery, store the ping against it
  const r = await pool.query(
    `WITH moved AS (
       UPDATE riders SET current_lat = $1, current_lng = $2, last_location_at = NOW()
       WHERE user_id = $3 RETURNING user_id
     ), active AS (
       SELECT id, customer_id FROM orders
       WHERE rider_user_id = $3 AND status = ANY($4::order_status[])
       ORDER BY assigned_at DESC LIMIT 1
     ), ping AS (
       INSERT INTO rider_locations (rider_user_id, order_id, latitude, longitude)
       SELECT $3, active.id, $1, $2 FROM active
       RETURNING order_id, recorded_at
     )
     SELECT (SELECT COUNT(*) FROM moved) AS moved, active.id AS order_id, active.customer_id, ping.recorded_at
     FROM (SELECT 1) one
     LEFT JOIN active ON true
     LEFT JOIN ping ON ping.order_id = active.id`,
    [point.lat, point.lng, req.user.userId, ACTIVE_STATUSES]
  );
  const row = r.rows[0];
  if (Number(row.moved) === 0) throw httpError(404, 'Rider profile not found.');

  if (row.order_id) {
    emitToUser(row.customer_id, 'rider:location', {
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
  if (!rider.is_online) return empty('offline');
  if (activeId) return empty('busy');
  if (rider.current_lat == null) return empty('no_location');

  const r = await pool.query(
    `${RIDER_ORDER_SELECT}
     WHERE o.status = 'ready_for_pickup' AND o.delivery_type = 'delivery' AND o.rider_user_id IS NULL
     ORDER BY o.ready_at NULLS LAST, o.created_at`
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
        readyAt: o.ready_at,
        distanceToStoreKm: toStoreKm == null ? null : Math.round(toStoreKm * 100) / 100,
        tripDistanceKm: tripKm == null ? null : Math.round(tripKm * 100) / 100,
        estimatedPayout: paisaToNumber(estimatePayoutPaisa(policies, num(o.store_lat), num(o.store_lng), num(o.customer_lat), num(o.customer_lng))),
      };
    })
    .filter((t) => t.distanceToStoreKm == null || t.distanceToStoreKm <= policies.task_radius_km)
    .sort((a, b) => (a.distanceToStoreKm ?? Infinity) - (b.distanceToStoreKm ?? Infinity));

  res.json({ success: true, data: { tasks, activeOrderId: null, radiusKm: policies.task_radius_km } });
});

/** POST /api/rider/tasks/:id/accept — first rider wins (single conditional UPDATE) */
const acceptTask = asyncHandler(async (req, res) => {
  const orderId = intParam(req.params.id);
  const riderUserId = req.user.userId;

  const order = await withTransaction(async (client, afterCommit) => {
    const rider = (await client.query('SELECT * FROM riders WHERE user_id = $1 FOR UPDATE', [riderUserId])).rows[0];
    if (!rider) throw httpError(404, 'Rider profile not found.');
    if (!rider.is_online) throw httpError(409, 'Go online to accept deliveries.');
    if (await activeOrderId(client, riderUserId)) throw httpError(409, 'Finish your current delivery first.');

    const r = await client.query(
      `UPDATE orders SET rider_user_id = $1, assigned_at = NOW(), updated_at = NOW()
       WHERE id = $2 AND status = 'ready_for_pickup' AND delivery_type = 'delivery' AND rider_user_id IS NULL
       RETURNING *`,
      [riderUserId, orderId]
    );
    if (r.rows.length === 0) throw httpError(409, 'Another rider has already taken this delivery.', { code: 'TASK_TAKEN' });

    await client.query('UPDATE riders SET is_available = false WHERE user_id = $1', [riderUserId]);
    const riderName = (await client.query('SELECT full_name FROM users WHERE id = $1', [riderUserId])).rows[0].full_name;
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

/** POST /api/rider/orders/:id/arrived — at the store; waiting time starts */
const arrivedAtStore = asyncHandler(async (req, res) => {
  const orderId = intParam(req.params.id);
  await withTransaction(async (client, afterCommit) => {
    const o = await lockOwnOrder(client, orderId, req.user.userId, ['ready_for_pickup']);
    if (o.rider_arrived_at) return;
    await client.query('UPDATE orders SET rider_arrived_at = NOW(), updated_at = NOW() WHERE id = $1', [orderId]);
    await announceOrder(client, afterCommit, orderId, 'rider_arrived', {
      vendor: { title: `Rider arrived for #${orderId}`, body: 'Hand the order over to the rider.' },
    });
  });
  res.json({ success: true, message: 'Arrival recorded.' });
});

/** POST /api/rider/orders/:id/picked — ready_for_pickup → picked */
const markPicked = asyncHandler(async (req, res) => {
  const orderId = intParam(req.params.id);
  await withTransaction(async (client, afterCommit) => {
    await lockOwnOrder(client, orderId, req.user.userId, ['ready_for_pickup']);
    await client.query(
      `UPDATE orders SET status = 'picked', picked_at = NOW(),
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
 * POST /api/rider/orders/:id/deliver  Body: { lat, lng }
 * Geofence (SSR 02): the rider must be within `geofence_m` of the customer's pin.
 * Then stock is deducted, the rider is paid from escrow, and the dispute window starts.
 */
const deliverOrder = asyncHandler(async (req, res) => {
  const orderId = intParam(req.params.id);
  const point = readPoint(req.body);
  const riderUserId = req.user.userId;

  const result = await withTransaction(async (client, afterCommit) => {
    const order = await lockOwnOrder(client, orderId, riderUserId, ['picked', 'on_the_way']);
    const policies = await getPolicies(client);

    if (order.customer_lat == null) throw httpError(409, 'This order has no customer location to verify against.');
    const distanceM = haversineKm(point.lat, point.lng, order.customer_lat, order.customer_lng) * 1000;
    if (distanceM > policies.geofence_m) {
      throw httpError(422,
        `You are ${Math.round(distanceM)} m from the customer's location. Move within ${policies.geofence_m} m to confirm delivery.`,
        { code: 'OUTSIDE_GEOFENCE', distanceMeters: Math.round(distanceM), geofenceMeters: policies.geofence_m });
    }

    await client.query(
      `INSERT INTO rider_locations (rider_user_id, order_id, latitude, longitude) VALUES ($1, $2, $3, $4)`,
      [riderUserId, orderId, point.lat, point.lng]
    );
    const trip = await computeTrip(client, order, policies, point);

    await client.query(
      `UPDATE orders SET status = 'delivered', delivered_at = NOW(), updated_at = NOW(),
              delivery_lat = $1, delivery_lng = $2, distance_km = $3, wait_minutes = $4
       WHERE id = $5`,
      [point.lat, point.lng, trip.distanceKm, trip.waitMinutes, orderId]
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
       COALESCE(SUM(distance_km), 0) AS total_km
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
      walletBalance: paisaToNumber(toPaisa(wallet.rows[0].wallet_balance)),
      recent: recent.rows.map(formatRiderOrder),
    },
  });
});

module.exports = {
  getProfile,
  setStatus,
  postLocation,
  getTasks,
  acceptTask,
  arrivedAtStore,
  markPicked,
  markOnTheWay,
  deliverOrder,
  getMyOrders,
  getEarnings,
};
