// ══════════════════════════════════════════════════════════════
// Delivery handover OTP (anti GPS-spoofing)
// Every order gets a 4-digit code at checkout that only the customer sees.
// The rider (or the store, for self pickup) must enter it to hand the order
// over, so a faked GPS position alone can't complete a delivery and release
// escrow. Five wrong codes lock the order's handover for 10 minutes and
// tell the customer.
//
// The check runs inside the handover transaction, which rolls back on a
// wrong code — so the failure is counted afterwards by withHandoverOtp().
// ══════════════════════════════════════════════════════════════

const crypto = require('crypto');
const pool = require('../db');
const { httpError, withTransaction } = require('../utils/http');
const { notify } = require('./notification.service');

const MAX_ATTEMPTS = 5;
const LOCK_MINUTES = 10;

const generateOtp = () => String(crypto.randomInt(0, 10000)).padStart(4, '0');

/** Constant-time comparison, so response timing doesn't leak digits */
function sameCode(a, b) {
  const x = Buffer.from(String(a ?? ''));
  const y = Buffer.from(String(b ?? ''));
  return x.length === y.length && crypto.timingSafeEqual(x, y);
}

/** Checks the code for an order row the caller has locked FOR UPDATE */
async function verifyHandoverOtp(client, order, otp) {
  if (!order.delivery_otp) return; // orders placed before handover codes existed
  if (order.otp_locked_until && new Date(order.otp_locked_until) > new Date()) {
    const mins = Math.ceil((new Date(order.otp_locked_until) - new Date()) / 60000);
    throw httpError(429, `Too many wrong codes. Handover is locked for ${mins} more min.`, {
      code: 'OTP_LOCKED', lockedUntil: order.otp_locked_until,
    });
  }
  const code = String(otp ?? '').trim();
  if (!code) {
    throw httpError(400, 'Ask the customer for their 4-digit delivery code.', { code: 'OTP_REQUIRED' });
  }
  if (!sameCode(code, order.delivery_otp)) {
    const err = httpError(422, 'Wrong delivery code.', { code: 'WRONG_OTP' });
    err.otpFailedOrder = order;
    throw err;
  }
  await client.query('UPDATE orders SET otp_verified_at = NOW(), otp_failed_attempts = 0 WHERE id = $1', [order.id]);
}

/** Counts a wrong code (after the handover transaction rolled back) and locks at the limit */
async function recordFailure(err) {
  const order = err.otpFailedOrder;
  const result = await withTransaction(async (client, afterCommit) => {
    const r = await client.query(
      `UPDATE orders SET otp_failed_attempts = otp_failed_attempts + 1,
              otp_locked_until = CASE WHEN otp_failed_attempts + 1 >= $2 THEN NOW() + ($3 * INTERVAL '1 minute') END
       WHERE id = $1 RETURNING otp_failed_attempts, otp_locked_until`,
      [order.id, MAX_ATTEMPTS, LOCK_MINUTES]
    );
    const row = r.rows[0];
    if (row.otp_locked_until) {
      await notify(client, afterCommit, order.customer_id, {
        type: 'otp_locked',
        orderId: order.id,
        title: `Delivery code blocked for Order #${order.id}`,
        body: `${MAX_ATTEMPTS} wrong codes were entered. Never share your code before you have your items.`,
      });
    }
    return row;
  });
  const left = Math.max(0, MAX_ATTEMPTS - result.otp_failed_attempts);
  return httpError(422,
    left ? `Wrong delivery code. ${left} attempt(s) left.` : `Wrong delivery code. Handover locked for ${LOCK_MINUTES} minutes.`,
    { code: 'WRONG_OTP', attemptsLeft: left });
}

/** withTransaction() for a handover: a wrong code is counted once the transaction has rolled back */
async function withHandoverOtp(fn) {
  try {
    return await withTransaction(fn);
  } catch (err) {
    if (err.otpFailedOrder) throw await recordFailure(err);
    throw err;
  }
}

/** Fresh code, stored for the order (resend after a lockout or for old orders) */
async function assignOtp(db, orderId) {
  const r = await db.query('UPDATE orders SET delivery_otp = $1 WHERE id = $2 RETURNING delivery_otp', [generateOtp(), orderId]);
  return r.rows[0]?.delivery_otp;
}

module.exports = { generateOtp, verifyHandoverOtp, withHandoverOtp, assignOtp, OTP_MAX_ATTEMPTS: MAX_ATTEMPTS };
