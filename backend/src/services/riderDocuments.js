// ══════════════════════════════════════════════════════════════
// Rider documents: CNIC, driving licence and vehicle registration.
// An admin checks them before the rider can go online. A bicycle needs
// neither licence nor registration.
// ══════════════════════════════════════════════════════════════

const { httpError } = require('../utils/http');

const VEHICLE_TYPES = ['motorcycle', 'motorbike', 'scooter', 'bicycle', 'car'];

/** 13 digits in any layout → 12345-1234567-1 */
function normalizeCnic(value) {
  const digits = String(value ?? '').replace(/\D/g, '');
  if (digits.length !== 13) throw httpError(400, 'CNIC must have 13 digits (e.g. 35202-1234567-1).');
  return `${digits.slice(0, 5)}-${digits.slice(5, 12)}-${digits.slice(12)}`;
}

function code(value, label, { min, max }) {
  const s = String(value ?? '').trim().toUpperCase().replace(/\s+/g, ' ');
  if (s.length < min || s.length > max || !/^[A-Z0-9 /-]+$/.test(s)) {
    throw httpError(400, `${label} must be ${min}–${max} letters, digits or dashes.`);
  }
  return s;
}

/** Body → { cnic, licenseNumber, vehicleNumber, vehicleType } or a 400 */
function readRiderDocuments(body = {}) {
  const vehicleType = body.vehicleType ? String(body.vehicleType).toLowerCase() : null;
  if (vehicleType && !VEHICLE_TYPES.includes(vehicleType)) {
    throw httpError(400, `Vehicle must be one of: ${VEHICLE_TYPES.join(', ')}.`);
  }
  const motorised = vehicleType !== 'bicycle';
  return {
    cnic: normalizeCnic(body.cnic),
    licenseNumber: motorised ? code(body.licenseNumber, 'Licence number', { min: 5, max: 30 }) : null,
    vehicleNumber: motorised ? code(body.vehicleNumber, 'Vehicle registration number', { min: 3, max: 20 }) : null,
    vehicleType,
  };
}

module.exports = { readRiderDocuments, normalizeCnic, VEHICLE_TYPES };
