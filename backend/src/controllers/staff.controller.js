// ══════════════════════════════════════════════════════════════
// Vendra Backend - Shop Staff Controller (SRDS §1.3, Table 1.1)
// The store owner adds cashiers, packers and inventory managers, each with
// a 4–6 digit PIN. On the shop's device anyone can "switch user" with their
// PIN and gets a token limited to their role (middleware/auth.js). Going
// back to the owner needs the owner's password (a normal login).
// ══════════════════════════════════════════════════════════════

const bcrypt = require('bcrypt');
const jwt = require('jsonwebtoken');
const pool = require('../db');
const { SALT_ROUNDS } = require('./auth.controller');
const { permissionsOf, STAFF_PERMISSIONS } = require('../middleware/auth');
const { httpError, asyncHandler, intParam } = require('../utils/http');

const ROLES = Object.keys(STAFF_PERMISSIONS);
const STAFF_TOKEN_EXPIRY = '12h'; // one shift
const MAX_PIN_ATTEMPTS = 5;
const PIN_LOCK_MINUTES = 5;
const MAX_STAFF = 20;

function readPin(pin) {
  const s = String(pin ?? '');
  if (!/^\d{4,6}$/.test(s)) throw httpError(400, 'PIN must be 4 to 6 digits.');
  return s;
}

function readRole(role) {
  if (!ROLES.includes(role)) throw httpError(400, `Role must be one of: ${ROLES.join(', ')}.`);
  return role;
}

function readName(name) {
  const s = typeof name === 'string' ? name.trim() : '';
  if (s.length < 2 || s.length > 100) throw httpError(400, 'Enter the staff member\'s name (2–100 characters).');
  return s;
}

function formatStaff(s) {
  return {
    id: s.id,
    fullName: s.full_name,
    role: s.role,
    isActive: s.is_active,
    permissions: permissionsOf(s.role),
    lastLoginAt: s.last_login_at,
    lockedUntil: s.pin_locked_until && new Date(s.pin_locked_until) > new Date() ? s.pin_locked_until : null,
    createdAt: s.created_at,
  };
}

/** GET /api/vendor/staff — owner only */
const listStaff = asyncHandler(async (req, res) => {
  const r = await pool.query(
    'SELECT * FROM vendor_staff WHERE vendor_id = $1 ORDER BY is_active DESC, full_name',
    [req.user.vendorId]
  );
  res.json({ success: true, data: r.rows.map(formatStaff), meta: { roles: STAFF_PERMISSIONS } });
});

/** GET /api/vendor/staff/roster — names and roles for the switch-user PIN pad (owner or staff) */
const getRoster = asyncHandler(async (req, res) => {
  const r = await pool.query(
    'SELECT id, full_name, role FROM vendor_staff WHERE vendor_id = $1 AND is_active ORDER BY full_name',
    [req.user.vendorId]
  );
  res.json({ success: true, data: r.rows.map((s) => ({ id: s.id, fullName: s.full_name, role: s.role })) });
});

/** POST /api/vendor/staff  Body: { fullName, role, pin } */
const createStaff = asyncHandler(async (req, res) => {
  const fullName = readName(req.body.fullName);
  const role = readRole(req.body.role);
  const pin = readPin(req.body.pin);
  const count = await pool.query('SELECT COUNT(*)::int AS n FROM vendor_staff WHERE vendor_id = $1 AND is_active', [req.user.vendorId]);
  if (count.rows[0].n >= MAX_STAFF) throw httpError(409, `A store can have up to ${MAX_STAFF} active staff.`);

  const r = await pool.query(
    `INSERT INTO vendor_staff (vendor_id, full_name, role, pin_hash) VALUES ($1, $2, $3, $4) RETURNING *`,
    [req.user.vendorId, fullName, role, await bcrypt.hash(pin, SALT_ROUNDS)]
  );
  res.status(201).json({ success: true, message: `${fullName} added as ${role.replace('_', ' ')}.`, data: formatStaff(r.rows[0]) });
});

/** PUT /api/vendor/staff/:id  Body: { fullName?, role?, pin?, isActive? } — a new PIN also lifts a lockout */
const updateStaff = asyncHandler(async (req, res) => {
  const id = intParam(req.params.id);
  const fullName = req.body.fullName !== undefined ? readName(req.body.fullName) : null;
  const role = req.body.role !== undefined ? readRole(req.body.role) : null;
  const pinHash = req.body.pin !== undefined ? await bcrypt.hash(readPin(req.body.pin), SALT_ROUNDS) : null;
  const isActive = typeof req.body.isActive === 'boolean' ? req.body.isActive : null;

  const r = await pool.query(
    `UPDATE vendor_staff SET full_name = COALESCE($1, full_name), role = COALESCE($2, role),
            pin_hash = COALESCE($3, pin_hash), is_active = COALESCE($4, is_active),
            pin_failed_attempts = CASE WHEN $3::text IS NULL THEN pin_failed_attempts ELSE 0 END,
            pin_locked_until = CASE WHEN $3::text IS NULL THEN pin_locked_until ELSE NULL END
     WHERE id = $5 AND vendor_id = $6 RETURNING *`,
    [fullName, role, pinHash, isActive, id, req.user.vendorId]
  );
  if (r.rows.length === 0) throw httpError(404, 'Staff member not found.');
  res.json({ success: true, message: 'Staff member updated.', data: formatStaff(r.rows[0]) });
});

/** DELETE /api/vendor/staff/:id — deactivates (sales and packing history keep the name) */
const removeStaff = asyncHandler(async (req, res) => {
  const r = await pool.query(
    'UPDATE vendor_staff SET is_active = false WHERE id = $1 AND vendor_id = $2 RETURNING id',
    [intParam(req.params.id), req.user.vendorId]
  );
  if (r.rows.length === 0) throw httpError(404, 'Staff member not found.');
  res.json({ success: true, message: 'Staff member removed. Their sessions end straight away.' });
});

/**
 * POST /api/vendor/staff/switch  Body: { staffId, pin }
 * From the owner's or any staff session of the same store. Five wrong PINs
 * lock that staff member for five minutes.
 */
const switchStaff = asyncHandler(async (req, res) => {
  const staffId = intParam(req.body.staffId, 'staffId');
  const pin = String(req.body.pin ?? '');
  const r = await pool.query(
    'SELECT * FROM vendor_staff WHERE id = $1 AND vendor_id = $2 AND is_active',
    [staffId, req.user.vendorId]
  );
  const staff = r.rows[0];
  if (!staff) throw httpError(404, 'Staff member not found.');
  if (staff.pin_locked_until && new Date(staff.pin_locked_until) > new Date()) {
    const mins = Math.ceil((new Date(staff.pin_locked_until) - new Date()) / 60000);
    throw httpError(429, `Too many wrong PINs. Try again in ${mins} min or ask the owner to reset the PIN.`, {
      code: 'PIN_LOCKED', lockedUntil: staff.pin_locked_until,
    });
  }

  if (!(await bcrypt.compare(pin, staff.pin_hash))) {
    const u = await pool.query(
      `UPDATE vendor_staff SET pin_failed_attempts = pin_failed_attempts + 1,
              pin_locked_until = CASE WHEN pin_failed_attempts + 1 >= $2 THEN NOW() + ($3 * INTERVAL '1 minute') END
       WHERE id = $1 RETURNING pin_failed_attempts`,
      [staff.id, MAX_PIN_ATTEMPTS, PIN_LOCK_MINUTES]
    );
    const left = Math.max(0, MAX_PIN_ATTEMPTS - u.rows[0].pin_failed_attempts);
    throw httpError(401, left ? `Wrong PIN. ${left} attempt(s) left.` : `Wrong PIN. Locked for ${PIN_LOCK_MINUTES} minutes.`, {
      code: 'WRONG_PIN', attemptsLeft: left,
    });
  }

  await pool.query(
    'UPDATE vendor_staff SET pin_failed_attempts = 0, pin_locked_until = NULL, last_login_at = NOW() WHERE id = $1',
    [staff.id]
  );
  const token = jwt.sign(
    { userId: req.user.userId, role: 'vendor', vendorId: req.user.vendorId, staffId: staff.id, staffRole: staff.role },
    process.env.JWT_SECRET,
    { expiresIn: STAFF_TOKEN_EXPIRY }
  );
  res.json({
    success: true,
    message: `Signed in as ${staff.full_name}.`,
    data: { token, staff: { id: staff.id, fullName: staff.full_name, role: staff.role, permissions: permissionsOf(staff.role) } },
  });
});

module.exports = { listStaff, getRoster, createStaff, updateStaff, removeStaff, switchStaff };
