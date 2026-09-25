// ══════════════════════════════════════════════════════════════
// Vendra Backend - Auth Routes
// ══════════════════════════════════════════════════════════════

const express = require('express');
const router = express.Router();
const { signup, login, getMe, changePassword } = require('../controllers/auth.controller');
const { authenticate } = require('../middleware/auth');

// Public routes
router.post('/signup', signup);
router.post('/login', login);

// Protected routes
router.get('/me', authenticate, getMe);
router.post('/change-password', authenticate, changePassword);

module.exports = router;
