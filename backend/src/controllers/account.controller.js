// ══════════════════════════════════════════════════════════════
// Vendra Backend - Account Controller
// Notifications inbox (FR09) and wallet history, for every role
// ══════════════════════════════════════════════════════════════

const pool = require('../db');
const { formatNotification } = require('../services/notification.service');
const { asyncHandler, httpError, intParam, paging, pageOf } = require('../utils/http');

/**
 * GET /api/notifications?limit=50&offset=0&unread=true — the inbox, newest first.
 * meta.hasMore / nextOffset page back through older alerts.
 */
const getNotifications = asyncHandler(async (req, res) => {
  const page = paging(req.query, { defaultLimit: 50, maxLimit: 200 });
  const unreadOnly = req.query.unread === 'true';
  const [list, unread] = await Promise.all([
    pool.query(
      `SELECT * FROM notifications WHERE user_id = $1 ${unreadOnly ? 'AND is_read = false' : ''}
       ORDER BY created_at DESC, id DESC LIMIT $2 OFFSET $3`,
      [req.user.userId, page.limit + 1, page.offset]
    ),
    pool.query('SELECT COUNT(*) FROM notifications WHERE user_id = $1 AND is_read = false', [req.user.userId]),
  ]);
  const { items, meta } = pageOf(list.rows, page);
  res.json({
    success: true,
    data: { notifications: items.map(formatNotification), unreadCount: Number(unread.rows[0].count) },
    meta,
  });
});

/** PUT /api/notifications/:id/read */
const markNotificationRead = asyncHandler(async (req, res) => {
  const r = await pool.query(
    'UPDATE notifications SET is_read = true WHERE id = $1 AND user_id = $2 RETURNING id',
    [intParam(req.params.id), req.user.userId]
  );
  if (r.rows.length === 0) throw httpError(404, 'Notification not found.');
  res.json({ success: true });
});

/** PUT /api/notifications/read-all */
const markAllNotificationsRead = asyncHandler(async (req, res) => {
  await pool.query('UPDATE notifications SET is_read = true WHERE user_id = $1 AND is_read = false', [req.user.userId]);
  res.json({ success: true });
});

/** GET /api/wallet?limit=50 — balance + latest movements (max 200) */
const getWallet = asyncHandler(async (req, res) => {
  const limit = Math.min(Number(req.query.limit) || 50, 200);
  const [user, ledger] = await Promise.all([
    pool.query('SELECT wallet_balance FROM users WHERE id = $1', [req.user.userId]),
    pool.query(
      `SELECT id, order_id, transaction_type, amount, balance_after, description, reference, created_at
       FROM wallet_ledger WHERE user_id = $1 ORDER BY created_at DESC, id DESC LIMIT $2`,
      [req.user.userId, limit]
    ),
  ]);
  if (user.rows.length === 0) throw httpError(404, 'User not found.');
  res.json({
    success: true,
    data: {
      balance: Number(user.rows[0].wallet_balance),
      transactions: ledger.rows.map((t) => ({
        id: t.id,
        orderId: t.order_id,
        type: t.transaction_type,
        amount: Number(t.amount),
        balanceAfter: Number(t.balance_after),
        description: t.description,
        reference: t.reference,
        createdAt: t.created_at,
      })),
    },
  });
});

module.exports = { getNotifications, markNotificationRead, markAllNotificationsRead, getWallet };
