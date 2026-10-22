// ══════════════════════════════════════════════════════════════
// Delivery fee: a base amount plus a rate per km of straight-line distance
// from the store to the customer's pin, rounded to the nearest Rs 10.
// Both parts are admin policies (delivery_fee, delivery_fee_per_km).
// Riders are paid per km too, so the fee grows with the trip it pays for.
// ══════════════════════════════════════════════════════════════

const { haversineKm } = require('../utils/geo');
const { httpError } = require('../utils/http');

/** @returns {number} km between the store and the pin, or 0 when the store has no location */
function deliveryDistanceKm(store, pin) {
  if (store?.latitude == null || store?.longitude == null || pin?.lat == null || pin?.lng == null) return 0;
  return haversineKm(Number(store.latitude), Number(store.longitude), pin.lat, pin.lng);
}

/** @returns {number} fee in paisa */
function deliveryFeePaisa(policies, km) {
  const rupees = policies.delivery_fee + (policies.delivery_fee_per_km || 0) * km;
  return Math.round(rupees / 10) * 1000;
}

/** Refuses delivery beyond the max_delivery_km policy (0 = no limit) */
function assertDeliversTo(policies, km) {
  const max = policies.max_delivery_km;
  if (max > 0 && km > max) {
    throw httpError(400, `This store is ${km.toFixed(1)} km from your pin. Delivery is available up to ${max} km, so choose self pickup.`, {
      code: 'OUT_OF_DELIVERY_RANGE', distanceKm: Number(km.toFixed(2)), maxDeliveryKm: max,
    });
  }
}

module.exports = { deliveryDistanceKm, deliveryFeePaisa, assertDeliversTo };
