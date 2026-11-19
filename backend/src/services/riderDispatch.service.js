// ══════════════════════════════════════════════════════════════
// Rider dispatch — offers a delivery to the online riders near its store.
// Used when the store marks an order ready, and when a rider who let an
// accepted delivery lapse loses it (task hoarding guard).
// ══════════════════════════════════════════════════════════════

const { notify } = require('./notification.service');
const { getPolicies } = require('./policy.service');
const { emitToRiders } = require('../realtime');
const { haversineKm } = require('../utils/geo');

/**
 * Online riders within the policy radius of the store get a task notification,
 * and every rider app refreshes its task list.
 * @param exceptUserId a rider who must not be offered it again
 */
async function broadcastTask(client, afterCommit, order, { exceptUserId = null } = {}) {
  const policies = await getPolicies(client);
  const store = (await client.query('SELECT store_name, latitude, longitude FROM vendors WHERE id = $1', [order.vendor_id])).rows[0];
  const riders = await client.query(
    `SELECT user_id, current_lat, current_lng FROM riders
     WHERE is_online = true AND current_lat IS NOT NULL AND user_id IS DISTINCT FROM $1`,
    [exceptUserId]
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

module.exports = { broadcastTask };
