// ══════════════════════════════════════════════════════════════
// Payoneer Mass Payouts client (withdrawals to Payoneer accounts).
// Talks to the local simulator (backend/payoneer-sim) by default; point
// the PAYONEER_* variables at Payoneer's sandbox once Vendra has partner
// credentials. This is the only file that knows Payoneer's API.
//
// UNVERIFIED: Payoneer's API reference is behind their partner portal.
// The paths, fields and status values below follow the v4 API as commonly
// documented, and the simulator mirrors them. Check each one against the
// real reference before going live.
//
//   PAYONEER_API_URL        API base (default http://localhost:4343, the simulator)
//   PAYONEER_AUTH_URL       token endpoint (default {API_URL}/api/v2/oauth2/token)
//   PAYONEER_CLIENT_ID / PAYONEER_CLIENT_SECRET / PAYONEER_PROGRAM_ID
//   PAYONEER_PKR_PER_USD    rupees per dollar for withdrawals (default 280)
//   PAYONEER_IPCN_TOKEN     shared secret on the IPCN callback URL (Payoneer's
//                           callbacks are not signed; also allow-list their IPs)
//   PAYONEER_PAYEE_PORTAL   where a payee sees their account (default {API_URL}/payee/{payeeId};
//                           real Payoneer: https://myaccount.payoneer.com)
// Amounts at Payoneer are decimal dollars; Vendra keeps cents.
// ══════════════════════════════════════════════════════════════

const { httpError } = require('../../utils/http');
const { isDevelopment } = require('../../config/mode');

const config = () => {
  const apiUrl = (process.env.PAYONEER_API_URL || 'http://localhost:4343').replace(/\/$/, '');
  return {
    apiUrl,
    authUrl: process.env.PAYONEER_AUTH_URL || `${apiUrl}/api/v2/oauth2/token`,
    clientId: process.env.PAYONEER_CLIENT_ID || 'vendra_sandbox',
    clientSecret: process.env.PAYONEER_CLIENT_SECRET || 'vendra_sandbox_secret',
    programId: process.env.PAYONEER_PROGRAM_ID || '100086',
    ipcnToken: process.env.PAYONEER_IPCN_TOKEN || 'ipcn_vendra',
    payeePortal: process.env.PAYONEER_PAYEE_PORTAL || `${apiUrl}/payee/{payeeId}`,
  };
};

const pkrPerUsd = () => {
  const r = Number(process.env.PAYONEER_PKR_PER_USD);
  return Number.isFinite(r) && r > 0 ? r : 280;
};

/** Rupee paisa → US cents */
const toCents = (paisa) => Math.max(1, Math.round(paisa / pkrPerUsd()));

/** The payee id Vendra registers each user under */
const payeeIdFor = (userId) => `vendra-${userId}`;

const unavailable = (err) => httpError(503, 'Payoneer is unavailable right now. Please try again in a moment.', {
  code: 'PAYOUT_PROVIDER_UNAVAILABLE',
  ...(isDevelopment && err ? { cause: err.message } : {}),
});

let cachedToken = null;

async function accessToken() {
  if (cachedToken && cachedToken.expires > Date.now() + 60_000) return cachedToken.value;
  const { authUrl, clientId, clientSecret } = config();
  let res;
  try {
    res = await fetch(authUrl, {
      method: 'POST',
      headers: {
        Authorization: `Basic ${Buffer.from(`${clientId}:${clientSecret}`).toString('base64')}`,
        'Content-Type': 'application/x-www-form-urlencoded',
      },
      body: new URLSearchParams({ grant_type: 'client_credentials', scope: 'read write' }).toString(),
      signal: AbortSignal.timeout(10_000),
    });
  } catch (err) {
    throw unavailable(err);
  }
  const body = await res.json().catch(() => ({}));
  if (!res.ok || !body.access_token) {
    throw httpError(502, 'Vendra could not sign in to Payoneer. Check the PAYONEER_* settings.', { code: 'PAYOUT_PROVIDER_AUTH' });
  }
  cachedToken = { value: body.access_token, expires: Date.now() + (body.expires_in || 3600) * 1000 };
  return cachedToken.value;
}

/** Calls the program's API; Payoneer errors become httpErrors with its code (upper-cased) */
async function call(method, path, body) {
  const { apiUrl, programId } = config();
  const token = await accessToken();
  let res;
  try {
    res = await fetch(`${apiUrl}/v4/programs/${encodeURIComponent(programId)}${path}`, {
      method,
      headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' },
      body: body === undefined ? undefined : JSON.stringify(body),
      signal: AbortSignal.timeout(15_000),
    });
  } catch (err) {
    throw unavailable(err);
  }
  const payload = await res.json().catch(() => ({}));
  if (res.status === 401) cachedToken = null;
  if (!res.ok) {
    throw httpError(res.status === 404 ? 404 : res.status >= 500 ? 502 : 400, payload.error_description || 'Payoneer refused the request.', {
      code: String(payload.error || 'payoneer_error').toUpperCase(),
      gatewayStatus: res.status,
    });
  }
  return payload;
}

/**
 * The hosted page where the user signs up for Payoneer, or signs in to an existing
 * account, and links it to Vendra. Payoneer sends the browser to redirectUrl afterwards.
 */
async function registrationLink({ userId, redirectUrl, firstName, lastName, email }) {
  const r = await call('POST', '/payees/registration-link', {
    payee_id: payeeIdFor(userId),
    redirect_url: redirectUrl,
    redirect_time: 5,
    already_have_an_account: true,
    payee: { type: 'INDIVIDUAL', contact: { first_name: firstName, last_name: lastName, email } },
  });
  return { url: r.result.registration_link, payeeId: payeeIdFor(userId) };
}

/** not_registered (never finished sign-up) | pending (Payoneer is reviewing) | active | inactive */
async function payeeStatus(payeeId) {
  try {
    const r = await call('GET', `/payees/${encodeURIComponent(payeeId)}/status`);
    const type = String(r.result?.status?.type || '').toUpperCase();
    return type === 'ACTIVE' ? 'active' : type === 'PENDING' ? 'pending' : 'inactive';
  } catch (err) {
    if (err.statusCode === 404) return 'not_registered';
    throw err;
  }
}

/** Payoneer payout status → the Vendra Pay payout shape payments.service works with */
function toPayout(clientRef, r) {
  const s = String(r.status || '').toLowerCase();
  const status = s === 'transferred' || s === 'completed' ? 'paid'
    : s === 'failed' || s === 'cancelled' || s === 'canceled' ? 'failed'
      : 'in_transit';
  return {
    id: clientRef,
    status,
    amount: Math.round(Number(r.amount) * 100),
    currency: String(r.currency || 'USD').toLowerCase(),
    destination: { brand: 'payoneer', last4: String(r.payee_id || '').slice(-4) },
    failure_message: status === 'failed' ? r.reason || 'Payoneer could not complete the payment.' : null,
  };
}

/**
 * Sends a withdrawal to the user's Payoneer account (converted to USD). The
 * client reference makes a resend of the same withdrawal a no-op at Payoneer.
 */
async function submitPayout({ withdrawalId, payeeId, amountPaisa, description }) {
  const clientRef = `vendra-withdrawal-${withdrawalId}`;
  const cents = toCents(amountPaisa);
  await call('POST', '/masspayouts', {
    Payments: [{
      client_reference_id: clientRef,
      payee_id: payeeId,
      amount: (cents / 100).toFixed(2),
      currency: 'USD',
      description,
      payout_date: new Date().toISOString().slice(0, 10),
    }],
  });
  return getPayout(clientRef);
}

async function getPayout(clientRef) {
  const r = await call('GET', `/payouts/${encodeURIComponent(clientRef)}/status`);
  return toPayout(clientRef, r.result || {});
}

async function getBalance() {
  const r = await call('GET', '/balance');
  return { currency: String(r.result?.currency || 'USD').toLowerCase(), available: Math.round(Number(r.result?.balance || 0) * 100) };
}

/** Where the user sees their Payoneer balance and the payments Vendra sent */
const payeePortalUrl = (payeeId) => config().payeePortal.replace('{payeeId}', encodeURIComponent(payeeId));

/** IPCN callbacks are unsigned, so the URL Vendra registers with Payoneer carries a shared token */
const ipcnTokenValid = (token) => typeof token === 'string' && token.length > 0 && token === config().ipcnToken;

module.exports = {
  name: 'payoneer',
  payeeIdFor,
  registrationLink,
  payeeStatus,
  submitPayout,
  getPayout,
  getBalance,
  payeePortalUrl,
  ipcnTokenValid,
  pkrPerUsd,
  toCents,
  toPayout,
};
