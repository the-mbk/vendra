// ══════════════════════════════════════════════════════════════
// Vendra Backend - Customer Routes
// ══════════════════════════════════════════════════════════════

const express = require('express');
const router = express.Router();
const { authenticate, requireCustomer } = require('../middleware/auth');
const {
  getPublicConfig,
  getCategories,
  getProducts,
  getVendorDetails,
  checkout,
  getCustomerOrders,
  getCustomerOrder,
  getOrderTracking,
  cancelOrder,
  topupWallet,
  customerMarkPickedUp,
  customerConfirmOrderDelivered,
} = require('../controllers/customer.controller');

// Public routes - browse the marketplace
router.get('/public-config', getPublicConfig);
router.get('/categories', getCategories);
router.get('/products', getProducts);
router.get('/vendors/:id', getVendorDetails);

// Protected customer routes
router.post('/customer/checkout', authenticate, requireCustomer, checkout);
router.get('/customer/orders', authenticate, requireCustomer, getCustomerOrders);
router.get('/customer/orders/:id', authenticate, requireCustomer, getCustomerOrder);
router.get('/customer/orders/:id/tracking', authenticate, requireCustomer, getOrderTracking);
router.post('/customer/orders/:id/cancel', authenticate, requireCustomer, cancelOrder);
router.post('/customer/orders/:id/picked-up', authenticate, requireCustomer, customerMarkPickedUp);
router.post('/customer/orders/:id/confirm-received', authenticate, requireCustomer, customerConfirmOrderDelivered);
router.post('/customer/wallet/topup', authenticate, requireCustomer, topupWallet);

module.exports = router;
