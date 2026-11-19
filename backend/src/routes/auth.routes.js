// ══════════════════════════════════════════════════════════════
// Vendra Backend - Auth Routes
// ══════════════════════════════════════════════════════════════

const express = require('express');
const router = express.Router();
const { signup, login, getMe, changePassword } = require('../controllers/auth.controller');
const { updateProfile, uploadProfilePhoto, deleteProfilePhoto } = require('../controllers/profile.controller');
const { authenticate, authenticateAllowStaff } = require('../middleware/auth');
const { productImageUpload } = require('../services/storage.service');

// Public routes
router.post('/signup', signup);
router.post('/login', login);

// Protected routes
router.get('/me', authenticateAllowStaff, getMe);
router.post('/change-password', authenticate, changePassword);

// Own profile: name, phone, photo (not for store staff signed in with a PIN)
router.put('/profile', authenticate, updateProfile);
router.post('/profile/photo', authenticate, productImageUpload.single('image'), uploadProfilePhoto);
router.delete('/profile/photo', authenticate, deleteProfilePhoto);

module.exports = router;
