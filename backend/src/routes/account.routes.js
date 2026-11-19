// ══════════════════════════════════════════════════════════════
// Vendra Backend - Account Routes (any signed-in role)
// Notifications, wallet history, disputes, order chat
// ══════════════════════════════════════════════════════════════

const express = require('express');
const router = express.Router();
const { authenticate, authenticateAllowStaff } = require('../middleware/auth');
const { evidenceUpload, MAX_EVIDENCE_FILES } = require('../services/storage.service');
const { getNotifications, markNotificationRead, markAllNotificationsRead, getWallet } = require('../controllers/account.controller');
const { createDispute, getMyDisputes, getDispute } = require('../controllers/dispute.controller');
const { getMessages, postMessage } = require('../controllers/chat.controller');

// Notifications
// Store staff on the shop's device see the store's notifications too
router.get('/notifications', authenticateAllowStaff, getNotifications);
router.put('/notifications/read-all', authenticateAllowStaff, markAllNotificationsRead);
router.put('/notifications/:id/read', authenticateAllowStaff, markNotificationRead);

// Wallet
router.get('/wallet', authenticate, getWallet);

// Disputes (multipart: orderId, issueType, description + up to 4 "evidence" images)
router.post('/disputes', authenticate, evidenceUpload.array('evidence', MAX_EVIDENCE_FILES), createDispute);
router.get('/disputes/mine', authenticate, getMyDisputes);
router.get('/disputes/:id', authenticate, getDispute);

// Order chat: the customer and the assigned rider
router.get('/orders/:id/messages', authenticate, getMessages);
router.post('/orders/:id/messages', authenticate, postMessage);

module.exports = router;
