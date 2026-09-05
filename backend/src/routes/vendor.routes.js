// ══════════════════════════════════════════════════════════════
// Vendra Backend - Vendor Routes (all require vendor role)
// ══════════════════════════════════════════════════════════════

const express = require('express');
const router = express.Router();
const { authenticate, requireVendor } = require('../middleware/auth');
const {
  createProduct,
  getVendorProducts,
  updateProduct,
  deleteProduct,
  getVendorOrders,
  approveOrder,
  rejectOrder,
  updateVendorLocation,
  getInventoryLedger,
  markOrderPreparing,
  markOrderReadyForPickup,
  markVendorOrderDelivered,
} = require('../controllers/vendor.controller');

// All vendor routes require authentication + vendor role
router.use(authenticate, requireVendor);

// Product CRUD
router.post('/products', createProduct);
router.get('/products', getVendorProducts);
router.put('/products/:id', updateProduct);
router.delete('/products/:id', deleteProduct);

// Vendor orders + approval
router.get('/orders', getVendorOrders);
router.put('/orders/:id/approve', approveOrder);
router.put('/orders/:id/reject', rejectOrder);
router.put('/orders/:id/prepare', markOrderPreparing);
router.put('/orders/:id/ready-for-pickup', markOrderReadyForPickup);
router.put('/orders/:id/deliver', markVendorOrderDelivered);

// Location
router.put('/location', updateVendorLocation);

// Inventory ledger
router.get('/inventory/ledger', getInventoryLedger);

module.exports = router;
