// ══════════════════════════════════════════════════════════════
// Geo helpers — distances between GPS points
// ══════════════════════════════════════════════════════════════

const EARTH_RADIUS_KM = 6371;

/** Great-circle distance in km between two lat/lng points (Haversine) */
function haversineKm(lat1, lon1, lat2, lon2) {
  const toRad = (d) => (d * Math.PI) / 180;
  const dLat = toRad(lat2 - lat1);
  const dLon = toRad(lon2 - lon1);
  const a =
    Math.sin(dLat / 2) ** 2 +
    Math.cos(toRad(lat1)) * Math.cos(toRad(lat2)) * Math.sin(dLon / 2) ** 2;
  return EARTH_RADIUS_KM * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
}

/** Whole metres between two points, or null when either is missing (evidence views) */
function metersBetween(aLat, aLng, bLat, bLng) {
  if ([aLat, aLng, bLat, bLng].some((v) => v == null)) return null;
  return Math.round(haversineKm(Number(aLat), Number(aLng), Number(bLat), Number(bLng)) * 1000);
}

/** Total length in km of a path of { lat, lng } points */
function pathLengthKm(points) {
  let total = 0;
  for (let i = 1; i < points.length; i++) {
    total += haversineKm(points[i - 1].lat, points[i - 1].lng, points[i].lat, points[i].lng);
  }
  return total;
}

function isValidCoordinate(lat, lng) {
  return (
    typeof lat === 'number' && typeof lng === 'number' &&
    Number.isFinite(lat) && Number.isFinite(lng) &&
    lat >= -90 && lat <= 90 && lng >= -180 && lng <= 180
  );
}

module.exports = { haversineKm, metersBetween, pathLengthKm, isValidCoordinate };
