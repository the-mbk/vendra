// ══════════════════════════════════════════════════════════════
// Card money in and out (FR03 escrow funding).
//
//   Top-up        card → gateway → customer wallet
//   Card checkout card → gateway → customer wallet → escrow (placeOrder), in that order,
//                 so escrow has a single entry path and a failed order leaves the money
//                 safely in the wallet
//   Withdrawal    wallet → gateway payout → card; a bounced payout returns to the wallet
//
// The gateway is the source of truth. Every change arrives by one of three routes and
// all of them converge on syncPayment / syncWithdrawal, which are idempotent:
// the API response, the signed webhook, and the reconcile sweep (for anything missed).
// ══════════════════════════════════════════════════════════════

const pool = require('../db');
const gateway = require('./gateway.client');
const { creditWallet, debitWallet } = require('./wallet.service');
const { notify } = require('./notification.service');
const { getPolicies } = require('./policy.service');
const { readCheckoutInput, quoteCheckout, placeOrder } = require('./checkout.service');
const { FEATURES } = require('../config/mode');
const { httpError, withTransaction } = require('../utils/http');
const { toPaisa, paisaToString, paisaToNumber } = require('../utils/money');

const TOPUP_MIN_RS = 100;
const TOPUP_MAX_RS = 500000;
const TERMINAL = new Set(['succeeded', 'failed', 'canceled']);
const RETRY_AFTER_SEC = 20;

const cardLabel = (brand, last4) => (last4 ? `${brand ? brand[0].toUpperCase() + brand.slice(1) : 'Card'} •••• ${last4}` : 'card');
const rs = (paisa) => `Rs. ${paisaToString(paisa)}`;

function readToken(body) {
  const token = String(body?.token ?? '');
  if (!/^tok_[\w-]{8,}$/.test(token)) {
    throw httpError(400, 'Enter your card details to continue.', { code: 'CARD_TOKEN_REQUIRED' });
  }
  return token;
}

function readAmountPaisa(value, minRs, maxRs, what) {
  const amount = Number(value);
  if (!Number.isFinite(amount) || amount < minRs || amount > maxRs) {
    throw httpError(400, `${what} must be between Rs. ${minRs.toLocaleString()} and Rs. ${maxRs.toLocaleString()}.`, { code: 'AMOUNT_OUT_OF_RANGE' });
  }
  const paisa = toPaisa(amount);
  if (paisa / 100 !== Math.round(amount * 100) / 100) throw httpError(400, 'Amounts can have at most two decimal places.');
  return paisa;
}

// ──────────────────────────────────────
// Views
// ──────────────────────────────────────

function paymentView(p, intent) {
  const otp = p.status === 'requires_action';
  return {
    id: p.id,
    purpose: p.purpose,
    amount: Number(p.amount),
    status: p.status,
    card: p.card_last4 ? { brand: p.card_brand, last4: p.card_last4 } : null,
    gatewayIntentId: p.gateway_intent_id,
    nextAction: otp
      ? {
        type: 'otp',
        attemptsLeft: intent?.next_action?.attempts_left ?? null,
        // The sandbox code is only shown while test-card helpers are on
        hint: FEATURES.testCards ? intent?.next_action?.otp_hint ?? null : null,
      }
      : null,
    failureMessage: p.failure_message,
    orderId: p.order_id,
    orderError: p.order_error,
    createdAt: p.created_at,
  };
}

function withdrawalView(w) {
  return {
    id: w.id,
    amount: Number(w.amount),
    status: w.status,
    card: w.card_last4 ? { brand: w.card_brand, last4: w.card_last4 } : null,
    gatewayPayoutId: w.gateway_payout_id,
    failureMessage: w.failure_message,
    createdAt: w.created_at,
    settledAt: w.settled_at,
  };
}

const walletBalance = async (userId) =>
  Number((await pool.query('SELECT wallet_balance FROM users WHERE id = $1', [userId])).rows[0]?.wallet_balance ?? 0);

// ──────────────────────────────────────
// Payments (money in)
// ──────────────────────────────────────

/** Applies the gateway's view of a payment. Credits the wallet exactly once on success. */
async function syncPayment(paymentId, intent) {
  return withTransaction(async (client, afterCommit) => {
    const p = (await client.query('SELECT * FROM payments WHERE id = $1 FOR UPDATE', [paymentId])).rows[0];
    if (!p) throw httpError(404, 'Payment not found.');

    // Never move back from a final state (a stale event can arrive late), but the
    // gateway can turn a payment we marked failed (lost connection) into a success
    let status = intent.status === 'processing' ? 'processing' : intent.status;
    if (p.status === 'succeeded' || (TERMINAL.has(p.status) && !TERMINAL.has(status))) status = p.status;

    const r = await client.query(
      `UPDATE payments SET gateway_intent_id = COALESCE(gateway_intent_id, $2), status = $3,
              card_brand = COALESCE($4, card_brand), card_last4 = COALESCE($5, card_last4),
              failure_message = $6, updated_at = NOW()
       WHERE id = $1 RETURNING *`,
      [p.id, intent.id, status, intent.card?.brand ?? null, intent.card?.last4 ?? null,
        status === 'succeeded' ? null : intent.last_payment_error?.message ?? null]
    );
    let row = r.rows[0];

    if (status === 'succeeded' && !p.credited_at) {
      const card = cardLabel(row.card_brand, row.card_last4);
      await creditWallet(client, {
        userId: p.user_id,
        amountPaisa: intent.amount,
        type: 'deposit',
        reference: intent.id,
        description: p.purpose === 'topup' ? `Card top-up (${card})` : `Card payment for checkout (${card})`,
      });
      row = (await client.query('UPDATE payments SET credited_at = NOW() WHERE id = $1 RETURNING *', [p.id])).rows[0];
      if (p.purpose === 'topup') {
        await notify(client, afterCommit, p.user_id, {
          type: 'wallet_topup',
          title: `${rs(intent.amount)} added to your wallet`,
          body: `Paid with ${card}. Reference ${intent.id}.`,
        });
      }
    }
    return row;
  });
}

/** After a card checkout payment succeeds: place the order from the saved cart, once */
async function placeCardOrder(paymentId) {
  try {
    return await withTransaction(async (client, afterCommit) => {
      const p = (await client.query('SELECT * FROM payments WHERE id = $1 FOR UPDATE', [paymentId])).rows[0];
      if (!p || p.purpose !== 'checkout' || !p.credited_at || p.order_id || p.order_error) return null;
      const order = await placeOrder(client, afterCommit, p.user_id, readCheckoutInput(p.checkout), { paymentMethod: 'card' });
      await client.query('UPDATE payments SET order_id = $2, updated_at = NOW() WHERE id = $1', [p.id, order.id]);
      return order;
    });
  } catch (err) {
    if (!err.statusCode) throw err; // unexpected: the reconcile sweep retries
    // The cart can't be ordered any more (sold out, price rose…): the money stays in the wallet
    await withTransaction(async (client, afterCommit) => {
      const p = (await client.query('SELECT * FROM payments WHERE id = $1 FOR UPDATE', [paymentId])).rows[0];
      if (p.order_id || p.order_error) return;
      await client.query('UPDATE payments SET order_error = $2, updated_at = NOW() WHERE id = $1', [p.id, err.message]);
      await notify(client, afterCommit, p.user_id, {
        type: 'payment_order_failed',
        title: "Your order couldn't be placed",
        body: `${err.message} The ${rs(toPaisa(p.amount))} you paid is in your Vendra wallet.`,
      });
    });
    return null;
  }
}

/** Applies an intent and, for a checkout, places the order. Returns { payment, order }. */
async function settlePayment(paymentId, intent) {
  let row = await syncPayment(paymentId, intent);
  let order = null;
  if (row.purpose === 'checkout' && row.status === 'succeeded') {
    order = await placeCardOrder(paymentId);
    row = (await pool.query('SELECT * FROM payments WHERE id = $1', [paymentId])).rows[0];
  }
  return { payment: paymentView(row, intent), order };
}

async function chargeCard(userId, { purpose, amountPaisa, token, checkout, description }) {
  const p = (await pool.query(
    `INSERT INTO payments (user_id, purpose, amount, checkout) VALUES ($1, $2, $3, $4) RETURNING *`,
    [userId, purpose, paisaToString(amountPaisa), checkout ? JSON.stringify(checkout) : null]
  )).rows[0];

  let intent;
  try {
    intent = await gateway.createPaymentIntent({
      amount: amountPaisa,
      token,
      description,
      metadata: { vendra_ref: `payment:${p.id}`, user_id: String(userId), purpose },
    }, `vendra-payment-${p.id}`);
  } catch (err) {
    await pool.query(
      `UPDATE payments SET status = 'failed', failure_message = $2, updated_at = NOW() WHERE id = $1`,
      [p.id, err.message]
    );
    throw err;
  }
  const result = await settlePayment(p.id, intent);
  return { ...result, walletBalance: await walletBalance(userId) };
}

/** POST /api/payments/topup */
async function startTopup(userId, body) {
  const amountPaisa = readAmountPaisa(body?.amount, TOPUP_MIN_RS, TOPUP_MAX_RS, 'A top-up');
  return chargeCard(userId, {
    purpose: 'topup',
    amountPaisa,
    token: readToken(body),
    description: `Vendra wallet top-up`,
  });
}

/** POST /api/payments/checkout — the checkout body plus a card token; charges exactly the order total */
async function startCardCheckout(userId, body) {
  const token = readToken(body);
  const input = readCheckoutInput(body);
  const { totalPaisa: amountPaisa } = await quoteCheckout(pool, input); // fails before charging if the cart can't be ordered
  return chargeCard(userId, {
    purpose: 'checkout',
    amountPaisa,
    token,
    checkout: input,
    description: `Vendra order (${input.items.length} item${input.items.length === 1 ? '' : 's'})`,
  });
}

async function ownPayment(userId, paymentId) {
  const p = (await pool.query('SELECT * FROM payments WHERE id = $1 AND user_id = $2', [paymentId, userId])).rows[0];
  if (!p) throw httpError(404, 'Payment not found.');
  return p;
}

/** GET /api/payments/:id */
async function getPayment(userId, paymentId) {
  return paymentView(await ownPayment(userId, paymentId));
}

/** POST /api/payments/:id/refresh — after the app finishes the OTP step at the gateway */
async function refreshPayment(userId, paymentId) {
  const p = await ownPayment(userId, paymentId);
  if (!p.gateway_intent_id) return { payment: paymentView(p), order: null, walletBalance: await walletBalance(userId) };
  const intent = await gateway.getPaymentIntent(p.gateway_intent_id);
  const result = await settlePayment(p.id, intent);
  return { ...result, walletBalance: await walletBalance(userId) };
}

/** GET /api/payments — the user's own card payments, newest first */
async function listPayments(userId, { limit, offset }) {
  const r = await pool.query(
    'SELECT * FROM payments WHERE user_id = $1 ORDER BY created_at DESC, id DESC LIMIT $2 OFFSET $3',
    [userId, limit + 1, offset]
  );
  return r.rows.map((p) => paymentView(p));
}

// ──────────────────────────────────────
// Withdrawals (money out)
// ──────────────────────────────────────

/** Applies the gateway's view of a payout; a failed payout returns the money to the wallet */
async function syncWithdrawal(withdrawalId, payout) {
  return withTransaction(async (client, afterCommit) => {
    const w = (await client.query('SELECT * FROM withdrawals WHERE id = $1 FOR UPDATE', [withdrawalId])).rows[0];
    if (!w) throw httpError(404, 'Withdrawal not found.');
    if (w.status === 'paid' || w.status === 'failed') return w;

    const status = payout.status === 'paid' || payout.status === 'failed' ? payout.status : 'in_transit';
    const card = cardLabel(payout.destination?.brand, payout.destination?.last4);
    const row = (await client.query(
      `UPDATE withdrawals SET gateway_payout_id = $2, status = $3::text, card_brand = $4, card_last4 = $5,
              failure_message = $6, settled_at = CASE WHEN $3::text IN ('paid', 'failed') THEN NOW() END
       WHERE id = $1 RETURNING *`,
      [w.id, payout.id, status, payout.destination?.brand ?? null, payout.destination?.last4 ?? null, payout.failure_message ?? null]
    )).rows[0];
    if (w.ledger_id) {
      await client.query(
        `UPDATE wallet_ledger SET reference = $2, description = $3 WHERE id = $1`,
        [w.ledger_id, payout.id, `Withdrawal to ${card}`]
      );
    }

    if (status === 'paid') {
      await notify(client, afterCommit, w.user_id, {
        type: 'withdrawal_paid',
        title: `${rs(toPaisa(w.amount))} sent to your ${card}`,
        body: `Withdrawal #${w.id} has arrived. Reference ${payout.id}.`,
      });
    } else if (status === 'failed') {
      await creditWallet(client, {
        userId: w.user_id,
        amountPaisa: toPaisa(w.amount),
        type: 'withdrawal_reversal',
        reference: payout.id,
        description: `Withdrawal #${w.id} returned: ${payout.failure_message || 'payout failed'}`,
      });
      await notify(client, afterCommit, w.user_id, {
        type: 'withdrawal_failed',
        title: `Withdrawal of ${rs(toPaisa(w.amount))} returned to your wallet`,
        body: payout.failure_message || "The payout to your card didn't go through.",
      });
    }
    return row;
  });
}

/** The gateway refused the payout outright: give the money back */
async function reverseWithdrawal(withdrawalId, message) {
  await withTransaction(async (client) => {
    const w = (await client.query('SELECT * FROM withdrawals WHERE id = $1 FOR UPDATE', [withdrawalId])).rows[0];
    if (w.status !== 'pending') return;
    await creditWallet(client, {
      userId: w.user_id,
      amountPaisa: toPaisa(w.amount),
      type: 'withdrawal_reversal',
      description: `Withdrawal #${w.id} cancelled: ${message}`,
    });
    await client.query(
      `UPDATE withdrawals SET status = 'failed', failure_message = $2, settled_at = NOW() WHERE id = $1`,
      [w.id, message]
    );
  });
}

async function sendPayout(w) {
  return gateway.createPayout({
    amount: toPaisa(w.amount),
    token: w.payout_token,
    description: `Vendra withdrawal #${w.id}`,
    metadata: { vendra_ref: `withdrawal:${w.id}`, user_id: String(w.user_id) },
  }, `vendra-withdrawal-${w.id}`); // the same key on a retry returns the first result
}

/** POST /api/withdrawals — moves money out of the wallet to a card */
async function startWithdrawal(userId, body) {
  const token = readToken(body);
  const { min_withdrawal: minRs } = await getPolicies();
  const amountPaisa = readAmountPaisa(body?.amount, minRs, TOPUP_MAX_RS, 'A withdrawal');

  const w = await withTransaction(async (client) => {
    const row = (await client.query(
      `INSERT INTO withdrawals (user_id, amount, payout_token) VALUES ($1, $2, $3) RETURNING *`,
      [userId, paisaToString(amountPaisa), token]
    )).rows[0];
    let ledgerId;
    await debitWallet(client, {
      userId,
      amountPaisa,
      type: 'withdrawal',
      description: `Withdrawal #${row.id} to card`,
      onLedger: (id) => { ledgerId = id; },
    });
    return (await client.query('UPDATE withdrawals SET ledger_id = $2 WHERE id = $1 RETURNING *', [row.id, ledgerId])).rows[0];
  });

  let payout;
  try {
    payout = await sendPayout(w);
  } catch (err) {
    // Unknown outcome (gateway unreachable): stays pending; the reconcile sweep resends with the
    // same idempotency key, which returns the original payout if the gateway did create it
    if (err.statusCode === 503) return { withdrawal: withdrawalView(w), walletBalance: await walletBalance(userId) };
    // The gateway refused it, so no money left: give it back
    await reverseWithdrawal(w.id, err.message);
    throw err;
  }
  // The payout exists from here on: never reverse because of a later error (the sweep finishes the sync)
  const row = await syncWithdrawal(w.id, payout);
  return { withdrawal: withdrawalView(row), walletBalance: await walletBalance(userId) };
}

/** GET /api/withdrawals */
async function listWithdrawals(userId, { limit, offset }) {
  const r = await pool.query(
    'SELECT * FROM withdrawals WHERE user_id = $1 ORDER BY created_at DESC, id DESC LIMIT $2 OFFSET $3',
    [userId, limit + 1, offset]
  );
  return r.rows.map(withdrawalView);
}

// ──────────────────────────────────────
// Webhooks and the reconcile sweep
// ──────────────────────────────────────

/** Handles one verified gateway event. Safe to receive more than once. */
async function handleGatewayEvent(event) {
  const object = event?.data?.object;
  const ref = String(object?.metadata?.vendra_ref ?? '');
  const payment = /^payment:(\d+)$/.exec(ref);
  const withdrawal = /^withdrawal:(\d+)$/.exec(ref);

  if (event.type?.startsWith('payment_intent.') && payment) await settlePayment(Number(payment[1]), object);
  else if (event.type?.startsWith('payout.') && withdrawal) await syncWithdrawal(Number(withdrawal[1]), object);

  await pool.query('INSERT INTO gateway_events (id, type) VALUES ($1, $2) ON CONFLICT (id) DO NOTHING', [event.id, event.type]);
}

/**
 * Catches anything a webhook missed: open payments and withdrawals are re-read from the
 * gateway, paid checkouts without an order are retried, and lost payout requests are resent.
 */
async function reconcileOpen() {
  let fixed = 0;
  const stale = `NOW() - INTERVAL '${RETRY_AFTER_SEC} seconds'`;

  const payments = await pool.query(
    `SELECT id, gateway_intent_id FROM payments
     WHERE (status IN ('processing', 'requires_action') AND gateway_intent_id IS NOT NULL AND updated_at < ${stale})
        OR (purpose = 'checkout' AND status = 'succeeded' AND credited_at IS NOT NULL AND order_id IS NULL AND order_error IS NULL)
     ORDER BY id LIMIT 20`
  );
  for (const p of payments.rows) {
    try {
      await settlePayment(p.id, await gateway.getPaymentIntent(p.gateway_intent_id));
      fixed++;
    } catch (err) {
      if (err.statusCode !== 503) console.error(`Payment #${p.id} reconcile failed:`, err.message);
    }
  }

  const withdrawals = await pool.query(
    `SELECT * FROM withdrawals
     WHERE (status = 'in_transit') OR (status = 'pending' AND created_at < ${stale})
     ORDER BY id LIMIT 20`
  );
  for (const w of withdrawals.rows) {
    try {
      const payout = w.gateway_payout_id ? await gateway.getPayout(w.gateway_payout_id) : await sendPayout(w);
      if (payout.status !== 'in_transit' || !w.gateway_payout_id) {
        await syncWithdrawal(w.id, payout);
        fixed++;
      }
    } catch (err) {
      if (err.statusCode === 503) continue;
      if (!w.gateway_payout_id && err.statusCode === 400) await reverseWithdrawal(w.id, err.message);
      else console.error(`Withdrawal #${w.id} reconcile failed:`, err.message);
    }
  }
  return fixed;
}

// ──────────────────────────────────────
// Reconciliation: does the money held at the gateway match the books?
// ──────────────────────────────────────

async function ledgerTotals(db = pool) {
  const r = await db.query(`
    SELECT (SELECT COALESCE(SUM(wallet_balance), 0) FROM users) AS wallets,
           (SELECT COALESCE(SUM(balance), 0) FROM platform_escrow_wallet) AS escrow,
           (SELECT COALESCE(SUM(amount), 0) FROM platform_ledger) AS platform,
           (SELECT COALESCE(SUM(amount), 0) FROM withdrawals WHERE status = 'pending') AS pending_withdrawals,
           (SELECT COALESCE(SUM(amount), 0) FROM payments WHERE status = 'succeeded' AND credited_at IS NULL) AS uncredited,
           (SELECT COALESCE(SUM(amount), 0) FROM wallet_ledger WHERE transaction_type = 'opening_balance') AS opening,
           (SELECT COALESCE(SUM(amount), 0) FROM gateway_fundings) AS funded`);
  const t = r.rows[0];
  return Object.fromEntries(Object.entries(t).map(([k, v]) => [k, toPaisa(v)]));
}

/**
 * Money that existed before the gateway (seed data, old simulated top-ups) has no
 * card payment behind it. In development the platform adds it to its gateway balance
 * once, so withdrawals of that money work and reconciliation balances.
 */
async function fundOpeningBalances() {
  let added = 0;
  for (;;) {
    const t = await ledgerTotals();
    const shortfall = t.opening - t.funded;
    if (shortfall <= 0) return added;
    // A single gateway top-up is capped at Rs 100,000,000
    const amount = Math.min(shortfall, 10_000_000_000);
    const topup = await gateway.createTopup({
      amount,
      description: 'Platform funds backing opening wallet balances',
      metadata: { vendra_ref: 'opening_balances' },
    }, `vendra-opening-${t.opening}-${t.funded}`);
    await pool.query(
      'INSERT INTO gateway_fundings (amount, gateway_topup_id) VALUES ($1, $2) ON CONFLICT (gateway_topup_id) DO NOTHING',
      [paisaToString(amount), topup.id]
    );
    added += amount;
  }
}

/** GET /api/admin/finance/reconciliation */
async function reconciliation() {
  const [t, balance] = await Promise.all([ledgerTotals(), gateway.getBalance().catch(() => null)]);
  const unfunded = t.opening - t.funded;
  // What the gateway should hold for Vendra: everything owed to users, held in escrow and earned,
  // plus withdrawals not yet sent and payments not yet credited, minus money that never came through it
  const expected = t.wallets + t.escrow + t.platform + t.pending_withdrawals + t.uncredited - unfunded;
  const n = paisaToNumber;
  return {
    gateway: balance
      ? { reachable: true, available: n(balance.available), inTransit: n(balance.in_transit) }
      : { reachable: false, available: null, inTransit: null },
    books: {
      wallets: n(t.wallets),
      escrow: n(t.escrow),
      platformRevenue: n(t.platform),
      pendingWithdrawals: n(t.pending_withdrawals),
      uncreditedPayments: n(t.uncredited),
    },
    openingBalances: { total: n(t.opening), funded: n(t.funded), unfunded: n(unfunded) },
    expectedGatewayBalance: n(expected),
    difference: balance ? n(balance.available - expected) : null,
    balanced: balance ? balance.available === expected : null,
  };
}

module.exports = {
  startTopup,
  startCardCheckout,
  getPayment,
  refreshPayment,
  listPayments,
  startWithdrawal,
  listWithdrawals,
  handleGatewayEvent,
  reconcileOpen,
  fundOpeningBalances,
  reconciliation,
  ledgerTotals,
  paymentView,
  withdrawalView,
  TOPUP_MIN_RS,
  TOPUP_MAX_RS,
};
