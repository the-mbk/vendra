// ══════════════════════════════════════════════════════════════
// Payout accounts: where a user's withdrawals go. PAYOUT_PROVIDER picks it:
//   card            Vendra Pay only: straight to a tokenized card, no account needed
//   payoneer        (default with Stripe) the user links a Payoneer account once on
//                   Payoneer's registration page; withdrawals are Payoneer payouts in USD
//   stripe_connect  the user sets up a Stripe Express account once on Stripe's page;
//                   withdrawals are Stripe transfers in the platform's currency
// Every provider answers in one shape, so the apps show one set of screens:
//   { provider, required, account: { id, detailsSubmitted, payoutsEnabled } | null, currency, pkrPerUnit }
// ══════════════════════════════════════════════════════════════

const pool = require('../db');
const gateway = require('./gateway.client');
const payoneer = require('./payouts/payoneer');
const { httpError } = require('../utils/http');

const MODES = ['card', 'payoneer', 'stripe_connect'];

/** The payout provider: PAYOUT_PROVIDER, else card with Vendra Pay and Payoneer with Stripe */
function mode() {
  const m = (process.env.PAYOUT_PROVIDER || (gateway.capabilities.cardPayouts ? 'card' : 'payoneer')).toLowerCase();
  if (!MODES.includes(m)) throw new Error(`PAYOUT_PROVIDER must be one of ${MODES.join(', ')} (got "${process.env.PAYOUT_PROVIDER}").`);
  if (m === 'card' && !gateway.capabilities.cardPayouts) throw new Error('PAYOUT_PROVIDER=card needs PAYMENT_PROVIDER=vendrapay.');
  if (m === 'stripe_connect' && gateway.name !== 'stripe') throw new Error('PAYOUT_PROVIDER=stripe_connect needs PAYMENT_PROVIDER=stripe.');
  return m;
}

/** What withdrawals.provider records for the current mode */
const withdrawalProvider = () => ({ card: 'vendrapay', payoneer: 'payoneer', stripe_connect: 'stripe' })[mode()];

const providerLabel = () => ({ payoneer: 'Payoneer', stripe_connect: 'Stripe' })[mode()] || 'your card';

/** Where Stripe / Payoneer send the browser back to after setup (a page on this API) */
const publicApiUrl = () => (process.env.PUBLIC_API_URL || `http://localhost:${process.env.PORT || 3000}`).replace(/\/$/, '');

// ──────────────────────────────────────
// Stripe Connect
// ──────────────────────────────────────

/** Copies Stripe's view of an account onto its user */
async function syncFromStripe(account) {
  const r = await pool.query(
    `UPDATE users SET stripe_details_submitted = $2,
            stripe_payouts_enabled = $3
     WHERE stripe_account_id = $1 RETURNING *`,
    // Transfers need the account's transfers capability; its own bank payouts follow from that
    [account.id, account.details_submitted === true, account.capabilities?.transfers === 'active']
  );
  return r.rows[0] || null;
}

async function stripeAccount(u) {
  if (u.stripe_account_id && !u.stripe_payouts_enabled) {
    u = (await syncFromStripe(await gateway.getConnectAccount(u.stripe_account_id))) || u;
  }
  const platform = await gateway.getPlatform().catch(() => null);
  return {
    account: u.stripe_account_id
      ? { id: u.stripe_account_id, detailsSubmitted: u.stripe_details_submitted, payoutsEnabled: u.stripe_payouts_enabled }
      : null,
    currency: platform?.currency ?? null,
    pkrPerUnit: gateway.pkrPerUnit(),
  };
}

async function stripeOnboarding(u) {
  let accountId = u.stripe_account_id;
  if (!accountId) {
    const account = await gateway.createConnectAccount({ email: u.email, userId: u.id, role: u.role, name: u.full_name });
    accountId = account.id;
    // The idempotency key makes a retry return the same account, so this never makes a second one
    await pool.query('UPDATE users SET stripe_account_id = $2 WHERE id = $1 AND stripe_account_id IS NULL', [u.id, accountId]);
  }
  const base = publicApiUrl();
  const link = await gateway.createAccountLink(accountId, {
    refreshUrl: `${base}/api/payouts/onboarding/expired`,
    returnUrl: `${base}/api/payouts/onboarding/done`,
  });
  return { url: link.url, expiresAt: new Date(link.expires_at * 1000) };
}

// ──────────────────────────────────────
// Payoneer
// ──────────────────────────────────────

/** Stores what Payoneer last said about a payee */
async function setPayoneerStatus(payeeId, status) {
  const r = await pool.query(
    `UPDATE users SET payoneer_status = $2, payoneer_status_at = NOW() WHERE payoneer_payee_id = $1 RETURNING *`,
    [payeeId, status]
  );
  return r.rows[0] || null;
}

async function payoneerAccount(u) {
  // Re-read from Payoneer until the account is active, so finishing sign-up shows up at once
  if (u.payoneer_payee_id && u.payoneer_status !== 'active') {
    u = (await setPayoneerStatus(u.payoneer_payee_id, await payoneer.payeeStatus(u.payoneer_payee_id))) || u;
  }
  const status = u.payoneer_status;
  return {
    account: u.payoneer_payee_id && status && status !== 'not_registered'
      ? { id: u.payoneer_payee_id, status, detailsSubmitted: true, payoutsEnabled: status === 'active' }
      : u.payoneer_payee_id
        ? { id: u.payoneer_payee_id, status: 'not_registered', detailsSubmitted: false, payoutsEnabled: false }
        : null,
    currency: 'usd',
    pkrPerUnit: payoneer.pkrPerUsd(),
  };
}

async function payoneerOnboarding(u) {
  const [firstName, ...rest] = String(u.full_name || '').trim().split(/\s+/);
  const link = await payoneer.registrationLink({
    userId: u.id,
    redirectUrl: `${publicApiUrl()}/api/payouts/onboarding/done`,
    firstName,
    lastName: rest.join(' ') || firstName,
    email: u.email,
  });
  await pool.query(
    `UPDATE users SET payoneer_payee_id = $2, payoneer_status = COALESCE(payoneer_status, 'not_registered'), payoneer_status_at = NOW()
     WHERE id = $1`,
    [u.id, link.payeeId]
  );
  return { url: link.url, expiresAt: null };
}

// ──────────────────────────────────────
// The API
// ──────────────────────────────────────

async function userRow(userId) {
  const u = (await pool.query('SELECT * FROM users WHERE id = $1', [userId])).rows[0];
  if (!u) throw httpError(404, 'User not found.');
  return u;
}

/** GET /api/payouts/account — what the app shows on the withdraw screen */
async function getPayoutAccount(userId) {
  const m = mode();
  if (m === 'card') return { provider: 'card', required: false, account: null };
  const u = await userRow(userId);
  const view = m === 'payoneer' ? await payoneerAccount(u) : await stripeAccount(u);
  return { provider: m, required: true, ...view };
}

/** POST /api/payouts/account/onboarding — the provider's setup page for this user */
async function startOnboarding(userId) {
  const m = mode();
  if (m === 'card') throw httpError(400, 'Withdrawals go to your card; no payout account is needed.');
  const u = await userRow(userId);
  return m === 'payoneer' ? payoneerOnboarding(u) : stripeOnboarding(u);
}

/** POST /api/payouts/account/dashboard — where the user sees their balance at the provider */
async function dashboardLink(userId) {
  const m = mode();
  const u = await userRow(userId);
  if (m === 'payoneer' && u.payoneer_payee_id && u.payoneer_status && u.payoneer_status !== 'not_registered') {
    return { url: payoneer.payeePortalUrl(u.payoneer_payee_id) };
  }
  if (m === 'stripe_connect' && u.stripe_account_id && u.stripe_details_submitted) {
    return { url: (await gateway.createLoginLink(u.stripe_account_id)).url };
  }
  throw httpError(409, 'Set up your payout account first.', { code: 'PAYOUT_ACCOUNT_REQUIRED' });
}

/** The account a withdrawal goes to, or a 409 telling the app to send the user to set it up */
async function requireReadyAccount(userId) {
  const status = await getPayoutAccount(userId);
  const name = providerLabel();
  if (!status.account || !status.account.detailsSubmitted) {
    throw httpError(409, `Link your ${name} account before withdrawing.`, { code: 'PAYOUT_ACCOUNT_REQUIRED' });
  }
  if (!status.account.payoutsEnabled) {
    throw httpError(409, `${name} is still checking your account. You can withdraw as soon as it's approved.`, {
      code: 'PAYOUT_ACCOUNT_PENDING',
    });
  }
  return status.account.id;
}

/** The page Stripe / Payoneer return the browser to. The app re-reads the account when the user comes back. */
function onboardingPage(done) {
  const title = done ? 'Payout account linked' : 'This link has expired';
  const text = done
    ? 'You can close this tab and go back to the Vendra app. Your withdrawals will go to this account.'
    : 'Go back to the Vendra app and tap “Set up payouts” again to get a new link.';
  return `<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>Vendra payouts</title><style>body{font:16px/1.5 system-ui,sans-serif;max-width:480px;margin:15vh auto;padding:0 16px;color:#1a1a2e;background:#f5f5f5}
.card{background:#fff;border-radius:16px;padding:28px;box-shadow:0 2px 12px #0001}h1{font-size:22px;margin:0 0 8px;color:${done ? '#28a745' : '#ff6b35'}}</style></head>
<body><div class="card"><h1>${title}</h1><p>${text}</p></div></body></html>`;
}

module.exports = {
  mode,
  withdrawalProvider,
  usesConnect: () => mode() === 'stripe_connect',
  getPayoutAccount,
  startOnboarding,
  dashboardLink,
  requireReadyAccount,
  syncFromStripe,
  setPayoneerStatus,
  onboardingPage,
};
