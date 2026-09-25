// ══════════════════════════════════════════════════════════════
// Vendra Backend - Rider Routes (all require rider role)
// ══════════════════════════════════════════════════════════════

const express = require('express');
const router = express.Router();
const { authenticate, requireRole } = require('../middleware/auth');
const {
  getProfile,
  setStatus,
  postLocation,
  getTasks,
  acceptTask,
  arrivedAtStore,
  markPicked,
  markOnTheWay,
  deliverOrder,
  getMyOrders,
  getEarnings,
} = require('../controllers/rider.controller');

router.use(authenticate, requireRole('rider'));

// Availability + GPS
router.get('/profile', getProfile);
router.put('/status', setStatus);
router.post('/location', postLocation);

// Task feed
router.get('/tasks', getTasks);
router.post('/tasks/:id/accept', acceptTask);

// Delivery state
router.get('/orders', getMyOrders);
router.post('/orders/:id/arrived', arrivedAtStore);
router.post('/orders/:id/picked', markPicked);
router.post('/orders/:id/on-the-way', markOnTheWay);
router.post('/orders/:id/deliver', deliverOrder);

// Earnings
router.get('/earnings', getEarnings);

module.exports = router;
