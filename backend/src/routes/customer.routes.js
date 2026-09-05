// ══════════════════════════════════════════════════════════════
// Vendra Backend - Customer Routes
// ══════════════════════════════════════════════════════════════

const express = require('express');
const router = express.Router();
const { authenticate, requireCustomer } = require('../middleware/auth');
const {
  getProducts,
  getVendorDetails,
  checkout,
  getCustomerOrders,
  cancelOrder,
  topupWallet,
  customerMarkPickedUp,
  customerConfirmOrderDelivered,
} = require('../controllers/customer.controller');

// Public route - browse products (anyone can view)
router.get('/products', getProducts);

// Public route - get vendor/shop details + products
router.get('/vendors/:id', getVendorDetails);

// Protected customer routes
router.post('/customer/checkout', authenticate, requireCustomer, checkout);
router.get('/customer/orders', authenticate, requireCustomer, getCustomerOrders);
router.post('/customer/orders/:id/cancel', authenticate, requireCustomer, cancelOrder);
router.post('/customer/orders/:id/picked-up', authenticate, requireCustomer, customerMarkPickedUp);
router.post('/customer/orders/:id/confirm-received', authenticate, requireCustomer, customerConfirmOrderDelivered);
router.post('/customer/wallet/topup', authenticate, requireCustomer, topupWallet);

module.exports = router;
