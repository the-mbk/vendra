// ══════════════════════════════════════════════════════════════
// Vendra Backend - Own profile (customers, riders, store owners)
//   PUT    /api/auth/profile        { fullName?, phone? }
//   POST   /api/auth/profile/photo  multipart "image" — replaces the photo
//   DELETE /api/auth/profile/photo
// Email stays fixed (it is the login). An approved rider's name matches the
// CNIC an admin verified, so it can only be changed through support.
// The photo is what the other side of a delivery sees (chat, tracking).
// ══════════════════════════════════════════════════════════════

const pool = require('../db');
const { httpError, asyncHandler } = require('../utils/http');
const { productImageUrl, removeProductImage } = require('../services/storage.service');

const NAME_MIN = 2;
const NAME_MAX = 100;

/** Pakistani mobile number → "03XX-XXXXXXX"; null when it isn't one */
function normalizePhone(raw) {
  const digits = String(raw ?? '').replace(/[\s-]/g, '');
  const m = /^(?:\+92|0092|92|0)?(3\d{9})$/.exec(digits);
  if (!m) return null;
  const local = `0${m[1]}`;
  return `${local.slice(0, 4)}-${local.slice(4)}`;
}

async function profileRow(userId) {
  const r = await pool.query(
    `SELECT u.id, u.full_name, u.phone, u.avatar_url, u.role, r.approval_status
     FROM users u LEFT JOIN riders r ON r.user_id = u.id WHERE u.id = $1`,
    [userId]
  );
  if (r.rows.length === 0) throw httpError(404, 'User not found.');
  return r.rows[0];
}

const profileView = (u) => ({ fullName: u.full_name, phone: u.phone, avatarUrl: u.avatar_url || null });

const updateProfile = asyncHandler(async (req, res) => {
  const current = await profileRow(req.user.userId);
  const sets = [];
  const params = [];

  if (req.body.fullName !== undefined) {
    const name = String(req.body.fullName).trim().replace(/\s+/g, ' ');
    if (name.length < NAME_MIN || name.length > NAME_MAX) {
      throw httpError(400, `Your name must be ${NAME_MIN} to ${NAME_MAX} characters.`);
    }
    if (name !== current.full_name) {
      if (current.role === 'rider' && current.approval_status === 'approved') {
        throw httpError(409, 'Your name matches your verified CNIC. Contact Vendra support to change it.', { code: 'NAME_LOCKED' });
      }
      params.push(name);
      sets.push(`full_name = $${params.length}`);
    }
  }

  if (req.body.phone !== undefined) {
    const phone = normalizePhone(req.body.phone);
    if (!phone) throw httpError(400, 'Enter a Pakistani mobile number, e.g. 0300-1234567.');
    if (phone !== current.phone) {
      params.push(phone);
      sets.push(`phone = $${params.length}`);
    }
  }

  if (sets.length === 0) return res.json({ success: true, message: 'Nothing to change.', data: profileView(current) });
  params.push(req.user.userId);
  const r = await pool.query(
    `UPDATE users SET ${sets.join(', ')} WHERE id = $${params.length} RETURNING full_name, phone, avatar_url`,
    params
  );
  res.json({ success: true, message: 'Profile saved.', data: profileView(r.rows[0]) });
});

/** Sets (url) or clears (null) the photo and deletes the file it replaces */
async function setPhoto(userId, url) {
  const r = await pool.query(
    `UPDATE users u SET avatar_url = $1
     FROM (SELECT avatar_url AS old_url FROM users WHERE id = $2 FOR NO KEY UPDATE) prev
     WHERE u.id = $2 RETURNING prev.old_url, u.full_name, u.phone, u.avatar_url`,
    [url, userId]
  );
  if (r.rows.length === 0) throw httpError(404, 'User not found.');
  if (r.rows[0].old_url && r.rows[0].old_url !== url) removeProductImage(r.rows[0].old_url);
  return profileView(r.rows[0]);
}

const uploadProfilePhoto = asyncHandler(async (req, res) => {
  const uploaded = req.file ? productImageUrl(req.file) : null;
  try {
    if (!uploaded) throw httpError(400, 'Attach a photo in the "image" field.');
    res.json({ success: true, message: 'Photo updated.', data: await setPhoto(req.user.userId, uploaded) });
  } catch (err) {
    removeProductImage(uploaded);
    throw err;
  }
});

const deleteProfilePhoto = asyncHandler(async (req, res) => {
  res.json({ success: true, message: 'Photo removed.', data: await setPhoto(req.user.userId, null) });
});

module.exports = { updateProfile, uploadProfilePhoto, deleteProfilePhoto, normalizePhone };
