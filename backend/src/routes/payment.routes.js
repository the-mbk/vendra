// ══════════════════════════════════════════════════════════════
// Vendra Backend - Payment Routes (card top-ups, card checkout, withdrawals)
// The gateway webhook is mounted in app.js, before the JSON parser, because
// its signature is checked against the raw body.
// ══════════════════════════════════════════════════════════════

const express = require('express');
const router = express.Router();
const { authenticate, requireCustomer } = require('../middleware/auth');
const {
  topup,
  cardCheckout,
  getPayment,
  refreshPayment,
  listMyPayments,
  withdraw,
  listMyWithdrawals,
  getPayoutAccount,
  startPayoutOnboarding,
  payoutDashboard,
  onboardingDone,
  onboardingExpired,
  payoneerIpcn,
} = require('../controllers/payment.controller');

router.post('/payments/topup', authenticate, requireCustomer, topup);
router.post('/payments/checkout', authenticate, requireCustomer, cardCheckout);
router.get('/payments', authenticate, listMyPayments);
router.get('/payments/:id', authenticate, getPayment);
router.post('/payments/:id/refresh', authenticate, refreshPayment);

// Every wallet owner can withdraw: vendors and riders their earnings, customers their balance
router.post('/withdrawals', authenticate, withdraw);
router.get('/withdrawals', authenticate, listMyWithdrawals);

// Payout accounts (Payoneer or Stripe Connect): set up once before the first withdrawal
router.get('/payouts/account', authenticate, getPayoutAccount);
router.post('/payouts/account/onboarding', authenticate, startPayoutOnboarding);
router.post('/payouts/account/dashboard', authenticate, payoutDashboard);
router.get('/payouts/onboarding/done', onboardingDone);
router.get('/payouts/onboarding/expired', onboardingExpired);
router.get('/payouts/payoneer/ipcn', payoneerIpcn);

module.exports = router;
