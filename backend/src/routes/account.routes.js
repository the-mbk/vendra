// ══════════════════════════════════════════════════════════════
// Vendra Backend - Account Routes (any signed-in role)
// Notifications, wallet history, disputes
// ══════════════════════════════════════════════════════════════

const express = require('express');
const router = express.Router();
const { authenticate } = require('../middleware/auth');
const { evidenceUpload, MAX_EVIDENCE_FILES } = require('../services/storage.service');
const { getNotifications, markNotificationRead, markAllNotificationsRead, getWallet } = require('../controllers/account.controller');
const { createDispute, getMyDisputes, getDispute } = require('../controllers/dispute.controller');

// Notifications
router.get('/notifications', authenticate, getNotifications);
router.put('/notifications/read-all', authenticate, markAllNotificationsRead);
router.put('/notifications/:id/read', authenticate, markNotificationRead);

// Wallet
router.get('/wallet', authenticate, getWallet);

// Disputes (multipart: orderId, issueType, description + up to 4 "evidence" images)
router.post('/disputes', authenticate, evidenceUpload.array('evidence', MAX_EVIDENCE_FILES), createDispute);
router.get('/disputes/mine', authenticate, getMyDisputes);
router.get('/disputes/:id', authenticate, getDispute);

module.exports = router;
