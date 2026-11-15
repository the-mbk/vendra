// ══════════════════════════════════════════════════════════════
// Vendra Backend - Vendor Routes (all require vendor role)
// Shop staff signed in with a PIN reach only what their role allows
// (see STAFF_PERMISSIONS in middleware/auth.js).
// ══════════════════════════════════════════════════════════════

const express = require('express');
const router = express.Router();
const { authenticateAllowStaff, requireVendor, requirePermission, requireOwner } = require('../middleware/auth');
const { productImageUpload } = require('../services/storage.service');
const {
  createProduct,
  getVendorProducts,
  getProductByBarcode,
  updateProduct,
  deleteProduct,
  uploadProductImage,
  deleteProductImage,
  addGalleryImage,
  deleteGalleryImage,
  createPosSale,
  getPosSales,
  getPosSale,
  getReceiptSettings,
  updateReceiptSettings,
  getVendorOrders,
  getVendorOrder,
  approveOrder,
  rejectOrder,
  setItemPacked,
  scanPackItem,
  updateVendorLocation,
  cancelLocationRequest,
  getInventoryLedger,
  getVendorReviews,
  markOrderPreparing,
  markOrderReadyForPickup,
  markVendorOrderDelivered,
} = require('../controllers/vendor.controller');
const { listStaff, getRoster, createStaff, updateStaff, removeStaff, switchStaff } = require('../controllers/staff.controller');

const can = requirePermission;

// All vendor routes require authentication + vendor role (owner or staff)
router.use(authenticateAllowStaff, requireVendor);

// Product CRUD
router.post('/products', can('products.manage'), createProduct);
router.get('/products', can('products.view'), getVendorProducts);
router.get('/products/barcode/:code', can('products.view'), getProductByBarcode);
router.put('/products/:id', can('products.manage'), updateProduct);
router.delete('/products/:id', can('products.manage'), deleteProduct);
router.post('/products/:id/image', can('products.manage'), productImageUpload.single('image'), uploadProductImage);
router.delete('/products/:id/image', can('products.manage'), deleteProductImage);
// Extra gallery photos (the cover stays in /image)
router.post('/products/:id/images', can('products.manage'), productImageUpload.single('image'), addGalleryImage);
router.delete('/products/:id/images/:imageId', can('products.manage'), deleteGalleryImage);
router.get('/reviews', can('products.view'), getVendorReviews);

// Walk-in POS + receipts
router.post('/pos/sales', can('pos'), createPosSale);
router.get('/pos/sales', can('pos'), getPosSales);
router.get('/pos/sales/:id', can('pos'), getPosSale);
router.get('/receipt-settings', can('pos'), getReceiptSettings);
router.put('/receipt-settings', requireOwner, updateReceiptSettings);

// Vendor orders + approval + packing checklist
router.get('/orders', can('orders.view'), getVendorOrders);
router.get('/orders/:id', can('orders.view'), getVendorOrder);
router.put('/orders/:id/approve', can('orders.fulfil'), approveOrder);
router.put('/orders/:id/reject', can('orders.fulfil'), rejectOrder);
router.put('/orders/:id/items/:itemId/pack', can('orders.fulfil'), setItemPacked);
router.post('/orders/:id/scan', can('orders.fulfil'), scanPackItem);
router.put('/orders/:id/prepare', can('orders.fulfil'), markOrderPreparing);
router.put('/orders/:id/ready-for-pickup', can('orders.fulfil'), markOrderReadyForPickup);
router.put('/orders/:id/deliver', can('orders.fulfil'), markVendorOrderDelivered);

// Location
router.put('/location', requireOwner, updateVendorLocation);
router.delete('/location/request', requireOwner, cancelLocationRequest);

// Inventory ledger
router.get('/inventory/ledger', can('ledger'), getInventoryLedger);

// Shop staff: the owner manages them; anyone on the shop's device can switch user with a PIN
router.get('/staff/roster', getRoster);
router.post('/staff/switch', switchStaff);
router.get('/staff', requireOwner, listStaff);
router.post('/staff', requireOwner, createStaff);
router.put('/staff/:id', requireOwner, updateStaff);
router.delete('/staff/:id', requireOwner, removeStaff);

module.exports = router;
