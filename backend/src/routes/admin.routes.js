// ══════════════════════════════════════════════════════════════
// Vendra Backend - Admin Routes
// All routes require admin role authentication
// ══════════════════════════════════════════════════════════════

const express = require('express');
const router = express.Router();
const { authenticate, requireAdmin } = require('../middleware/auth');
const {
  resetUserPassword,
  getDashboardStats,
  getAllVendors,
  approveVendor,
  disapproveVendor,
  approveVendorLocation,
  rejectVendorLocation,
  getProducts,
  approveProduct,
  hideProduct,
  getPolicies,
  updatePolicies,
  getRiders,
  getFinance,
  getAllOrders,
  getAllUsers,
} = require('../controllers/admin.controller');
const { adminListDisputes, adminResolveDispute } = require('../controllers/dispute.controller');
const { adminReconciliation, adminListPayments, adminListWithdrawals } = require('../controllers/payment.controller');

// All admin routes require authentication + admin role
router.use(authenticate);
router.use(requireAdmin);

// Dashboard stats
router.get('/stats', getDashboardStats);

// Vendor management
router.get('/vendors', getAllVendors);
router.put('/vendors/:id/approve', approveVendor);
router.put('/vendors/:id/disapprove', disapproveVendor);
router.put('/vendors/:id/location/approve', approveVendorLocation);
router.put('/vendors/:id/location/reject', rejectVendorLocation);

// Product catalog approval
router.get('/products', getProducts);
router.put('/products/:id/approve', approveProduct);
router.put('/products/:id/hide', hideProduct);

// Policy engine
router.get('/policies', getPolicies);
router.put('/policies', updatePolicies);

// Disputes
router.get('/disputes', adminListDisputes);
router.put('/disputes/:id/resolve', adminResolveDispute);

// Riders + finance
router.get('/riders', getRiders);
router.get('/finance', getFinance);
router.get('/finance/reconciliation', adminReconciliation);
router.get('/payments', adminListPayments);
router.get('/withdrawals', adminListWithdrawals);

// Order monitoring
router.get('/orders', getAllOrders);

// User management
router.get('/users', getAllUsers);
router.put('/users/:id/reset-password', resetUserPassword);

module.exports = router;
