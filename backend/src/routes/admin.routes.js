// ══════════════════════════════════════════════════════════════
// Vendra Backend - Admin Routes
// All routes require admin role authentication
// ══════════════════════════════════════════════════════════════

const express = require('express');
const router = express.Router();
const { authenticate, requireAdmin } = require('../middleware/auth');
const {
  getDashboardStats,
  getAllVendors,
  approveVendor,
  disapproveVendor,
  getAllOrders,
  getAllUsers,
} = require('../controllers/admin.controller');

// All admin routes require authentication + admin role
router.use(authenticate);
router.use(requireAdmin);

// Dashboard stats
router.get('/stats', getDashboardStats);

// Vendor management
router.get('/vendors', getAllVendors);
router.put('/vendors/:id/approve', approveVendor);
router.put('/vendors/:id/disapprove', disapproveVendor);

// Order monitoring
router.get('/orders', getAllOrders);

// User management
router.get('/users', getAllUsers);

module.exports = router;
