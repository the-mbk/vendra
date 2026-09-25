// ══════════════════════════════════════════════════════════════
// GPS-based rider payout (FR04)
//   payout = base fee
//          + rate per km × GPS distance from pickup to drop-off
//          + rate per min × waiting minutes beyond the free allowance
// Distance comes from the rider's location pings for this order. With fewer
// than two pings (GPS lost) it falls back to the straight line store → customer.
// ══════════════════════════════════════════════════════════════

const { haversineKm, pathLengthKm } = require('../utils/geo');
const { toPaisa } = require('../utils/money');

function waitingMinutes(order, pickedAt = order.picked_at) {
  if (!order.rider_arrived_at || !pickedAt) return 0;
  const ms = new Date(pickedAt) - new Date(order.rider_arrived_at);
  return Math.max(0, ms / 60000);
}

function payoutPaisa(policies, distanceKm, waitMin) {
  const paidWait = Math.max(0, waitMin - policies.rider_free_wait_min);
  const rupees =
    policies.rider_base_fee +
    policies.rider_per_km * distanceKm +
    policies.rider_per_wait_min * paidWait;
  return toPaisa(rupees);
}

/** Estimate shown on a task card before the trip: straight-line distance, no waiting */
function estimatePayoutPaisa(policies, storeLat, storeLng, customerLat, customerLng) {
  if ([storeLat, storeLng, customerLat, customerLng].some((v) => v == null)) {
    return toPaisa(policies.rider_base_fee);
  }
  return payoutPaisa(policies, haversineKm(storeLat, storeLng, customerLat, customerLng), 0);
}

/**
 * Final trip figures at delivery. `finalPoint` is the rider's position when
 * they mark delivered.
 */
async function computeTrip(client, order, policies, finalPoint) {
  const pings = await client.query(
    `SELECT latitude AS lat, longitude AS lng FROM rider_locations
     WHERE order_id = $1 AND recorded_at >= $2
     ORDER BY recorded_at`,
    [order.id, order.picked_at || order.assigned_at]
  );

  let distanceKm;
  let source;
  if (pings.rows.length >= 2) {
    distanceKm = pathLengthKm([...pings.rows, finalPoint]);
    source = 'gps';
  } else {
    const store = await client.query('SELECT latitude, longitude FROM vendors WHERE id = $1', [order.vendor_id]);
    const s = store.rows[0];
    distanceKm = s?.latitude != null
      ? haversineKm(s.latitude, s.longitude, order.customer_lat, order.customer_lng)
      : 0;
    source = 'straight_line';
  }

  const waitMin = waitingMinutes(order);
  return {
    distanceKm: Math.round(distanceKm * 1000) / 1000,
    waitMinutes: Math.round(waitMin * 100) / 100,
    payoutPaisa: payoutPaisa(policies, distanceKm, waitMin),
    distanceSource: source,
  };
}

module.exports = { computeTrip, estimatePayoutPaisa, payoutPaisa, waitingMinutes };
