// ══════════════════════════════════════════════════════════════
// Vendra Pay — a local card payment gateway for development and demos.
//
// Shaped like a real processor (Stripe-style API):
//   POST /v1/tokens                       card details → single-use token (publishable key)
//   POST /v1/payment_intents              charge a token (secret key)
//   POST /v1/payment_intents/:id/verify   one-time password for 3-D Secure cards (publishable key)
//   POST /v1/payouts                      pay money out to a card (secret key)
//   POST /v1/topups                       the merchant adds funds to its own balance (secret key)
//   GET  /v1/balance                      the merchant's balance held here
//   Signed webhooks to WEBHOOK_URL:       payment_intent.succeeded | payment_failed | canceled,
//                                         payout.paid | payout.failed
//   GET  /                                merchant dashboard
//
// The merchant (Vendra) never sees card numbers: apps tokenize directly here.
// Amounts are integer paisa, currency "pkr".
// ══════════════════════════════════════════════════════════════

const http = require('http');
const crypto = require('crypto');
const { DatabaseSync } = require('node:sqlite');
const { TEST_CARDS, BY_NUMBER, SANDBOX_OTP, luhnValid, CHARGE_DECLINES, PAYOUT_FAILURES } = require('./cards');
const { renderDashboard } = require('./dashboard');

const MAX_AMOUNT = 100_000_000; // Rs 1,000,000 per payment or payout
const MAX_TOPUP = 10_000_000_000; // Rs 100,000,000 per merchant top-up
const MIN_AMOUNT = 100; // Rs 1
const OTP_ATTEMPTS = 3;
const WEBHOOK_BACKOFF_SEC = [2, 5, 30, 120, 600, 1800];

const SCHEMA = `
CREATE TABLE IF NOT EXISTS tokens (
  id TEXT PRIMARY KEY, brand TEXT, last4 TEXT, funding TEXT, exp_month INTEGER, exp_year INTEGER,
  behaviour TEXT NOT NULL, used INTEGER NOT NULL DEFAULT 0, created INTEGER NOT NULL);
CREATE TABLE IF NOT EXISTS payment_intents (
  id TEXT PRIMARY KEY, amount INTEGER NOT NULL, currency TEXT NOT NULL, status TEXT NOT NULL,
  description TEXT, metadata TEXT, card_brand TEXT, card_last4 TEXT, card_funding TEXT,
  error_code TEXT, error_message TEXT, otp_attempts INTEGER NOT NULL DEFAULT 0,
  created INTEGER NOT NULL, updated INTEGER NOT NULL);
CREATE TABLE IF NOT EXISTS payouts (
  id TEXT PRIMARY KEY, amount INTEGER NOT NULL, currency TEXT NOT NULL, status TEXT NOT NULL,
  description TEXT, metadata TEXT, card_brand TEXT, card_last4 TEXT, behaviour TEXT NOT NULL,
  failure_code TEXT, failure_message TEXT, arrival_at INTEGER NOT NULL,
  created INTEGER NOT NULL, updated INTEGER NOT NULL);
CREATE TABLE IF NOT EXISTS topups (
  id TEXT PRIMARY KEY, amount INTEGER NOT NULL, currency TEXT NOT NULL, description TEXT, metadata TEXT,
  created INTEGER NOT NULL);
CREATE TABLE IF NOT EXISTS events (
  id TEXT PRIMARY KEY, type TEXT NOT NULL, object_id TEXT NOT NULL, data TEXT NOT NULL,
  created INTEGER NOT NULL, delivered_at INTEGER, attempts INTEGER NOT NULL DEFAULT 0,
  next_attempt_at INTEGER NOT NULL, last_status INTEGER, last_error TEXT);
CREATE TABLE IF NOT EXISTS idempotency (
  key TEXT NOT NULL, endpoint TEXT NOT NULL, response TEXT NOT NULL, created INTEGER NOT NULL,
  PRIMARY KEY (key, endpoint));
`;

class GatewayError extends Error {
  constructor(status, type, code, message) {
    super(message);
    Object.assign(this, { status, type, code });
  }
}
const invalid = (code, message) => new GatewayError(400, 'invalid_request_error', code, message);
const cardError = (code, message) => new GatewayError(402, 'card_error', code, message);

const nowSec = () => Math.floor(Date.now() / 1000);
const newId = (prefix) => `${prefix}_${crypto.randomBytes(12).toString('base64url')}`;

/** Header value for a webhook body: t=<unix>,v1=<hex HMAC-SHA256 of "t.body"> */
function signPayload(secret, payload, t = nowSec()) {
  const v1 = crypto.createHmac('sha256', secret).update(`${t}.${payload}`).digest('hex');
  return `t=${t},v1=${v1}`;
}

function createGateway(options = {}) {
  const cfg = {
    dbPath: ':memory:',
    publishableKey: 'pk_test_vendra',
    secretKey: 'sk_test_vendra',
    webhookSecret: 'whsec_vendra',
    webhookUrl: null,
    payoutDelaySec: 20,
    otpTtlSec: 15 * 60,
    tokenTtlSec: 15 * 60,
    log: () => {},
    ...options,
  };

  const db = new DatabaseSync(cfg.dbPath);
  db.exec('PRAGMA journal_mode = WAL;');
  db.exec(SCHEMA);

  const q = (sql) => db.prepare(sql);
  const tx = (fn) => {
    db.exec('BEGIN IMMEDIATE');
    try {
      const out = fn();
      db.exec('COMMIT');
      return out;
    } catch (err) {
      db.exec('ROLLBACK');
      throw err;
    }
  };

  // ──────────────────────────────────────
  // API objects
  // ──────────────────────────────────────

  const meta = (s) => (s ? JSON.parse(s) : {});

  function intentObject(r) {
    return {
      id: r.id,
      object: 'payment_intent',
      amount: r.amount,
      currency: r.currency,
      status: r.status,
      description: r.description,
      metadata: meta(r.metadata),
      card: { brand: r.card_brand, last4: r.card_last4, funding: r.card_funding },
      last_payment_error: r.error_code ? { code: r.error_code, message: r.error_message } : null,
      next_action: r.status === 'requires_action'
        ? { type: 'otp', attempts_left: OTP_ATTEMPTS - r.otp_attempts, otp_hint: `Sandbox code: ${SANDBOX_OTP}` }
        : null,
      created: r.created,
    };
  }

  function payoutObject(r) {
    return {
      id: r.id,
      object: 'payout',
      amount: r.amount,
      currency: r.currency,
      status: r.status,
      description: r.description,
      metadata: meta(r.metadata),
      destination: { brand: r.card_brand, last4: r.card_last4 },
      failure_code: r.failure_code,
      failure_message: r.failure_message,
      arrival_date: r.arrival_at,
      created: r.created,
    };
  }

  const getIntent = (id) => q('SELECT * FROM payment_intents WHERE id = ?').get(id);
  const getPayout = (id) => q('SELECT * FROM payouts WHERE id = ?').get(id);

  function balance() {
    const paid = q("SELECT COALESCE(SUM(amount), 0) AS s FROM payment_intents WHERE status = 'succeeded'").get().s
      + q('SELECT COALESCE(SUM(amount), 0) AS s FROM topups').get().s;
    const out = q("SELECT COALESCE(SUM(amount), 0) AS s FROM payouts WHERE status IN ('in_transit', 'paid')").get().s;
    const inTransit = q("SELECT COALESCE(SUM(amount), 0) AS s FROM payouts WHERE status = 'in_transit'").get().s;
    return { object: 'balance', currency: 'pkr', available: paid - out, in_transit: inTransit };
  }

  // ──────────────────────────────────────
  // Webhooks
  // ──────────────────────────────────────

  const inFlight = new Set();

  function emit(type, object) {
    const event = { id: newId('evt'), object: 'event', type, created: nowSec(), data: { object } };
    q('INSERT INTO events (id, type, object_id, data, created, next_attempt_at) VALUES (?, ?, ?, ?, ?, ?)')
      .run(event.id, type, object.id, JSON.stringify(event), event.created, event.created);
    setImmediate(() => deliver(event.id).catch(() => {}));
    return event;
  }

  async function deliver(eventId) {
    if (inFlight.has(eventId)) return;
    const row = q('SELECT * FROM events WHERE id = ?').get(eventId);
    if (!row || row.delivered_at || !cfg.webhookUrl) return;
    inFlight.add(eventId);
    let status = null;
    let error = null;
    try {
      const res = await fetch(cfg.webhookUrl, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', 'Vendra-Signature': signPayload(cfg.webhookSecret, row.data) },
        body: row.data,
        signal: AbortSignal.timeout(5000),
      });
      status = res.status;
      if (!res.ok) error = `HTTP ${res.status}`;
    } catch (err) {
      error = err.message;
    } finally {
      inFlight.delete(eventId);
    }
    const attempts = row.attempts + 1;
    if (!error) {
      q('UPDATE events SET delivered_at = ?, attempts = ?, last_status = ?, last_error = NULL WHERE id = ?')
        .run(nowSec(), attempts, status, eventId);
    } else {
      const wait = WEBHOOK_BACKOFF_SEC[Math.min(attempts - 1, WEBHOOK_BACKOFF_SEC.length - 1)];
      q('UPDATE events SET attempts = ?, next_attempt_at = ?, last_status = ?, last_error = ? WHERE id = ?')
        .run(attempts, nowSec() + wait, status, error, eventId);
    }
  }

  // ──────────────────────────────────────
  // Time-based work: payouts land or bounce, unanswered OTPs expire, webhooks retry
  // ──────────────────────────────────────

  async function tick() {
    const t = nowSec();
    for (const p of q("SELECT * FROM payouts WHERE status = 'in_transit' AND arrival_at <= ?").all(t)) {
      const failure = PAYOUT_FAILURES[p.behaviour];
      tx(() => {
        q('UPDATE payouts SET status = ?, failure_code = ?, failure_message = ?, updated = ? WHERE id = ?')
          .run(failure ? 'failed' : 'paid', failure?.code ?? null, failure?.message ?? null, t, p.id);
        emit(failure ? 'payout.failed' : 'payout.paid', payoutObject(getPayout(p.id)));
      });
    }
    for (const i of q("SELECT * FROM payment_intents WHERE status = 'requires_action' AND created <= ?").all(t - cfg.otpTtlSec)) {
      tx(() => {
        q("UPDATE payment_intents SET status = 'canceled', error_code = 'authentication_timeout', error_message = ?, updated = ? WHERE id = ?")
          .run('The one-time password was not entered in time.', t, i.id);
        emit('payment_intent.canceled', intentObject(getIntent(i.id)));
      });
    }
    const due = q('SELECT id FROM events WHERE delivered_at IS NULL AND next_attempt_at <= ? AND attempts < 10').all(t);
    await Promise.all(due.map((e) => deliver(e.id)));
  }

  // ──────────────────────────────────────
  // Operations
  // ──────────────────────────────────────

  function createToken(body) {
    const number = String(body.number ?? '').replace(/[\s-]/g, '');
    if (!/^\d{12,19}$/.test(number)) throw cardError('incomplete_number', 'Your card number is incomplete.');
    if (!luhnValid(number)) throw cardError('invalid_number', 'Your card number is invalid.');
    const card = BY_NUMBER.get(number);
    if (!card) {
      throw cardError('test_card_required', 'Vendra Pay is a sandbox and only accepts its test card numbers.');
    }
    const month = Number(body.exp_month);
    let year = Number(body.exp_year);
    if (year < 100) year += 2000;
    if (!Number.isInteger(month) || month < 1 || month > 12) throw cardError('invalid_expiry_month', "Your card's expiry month is invalid.");
    if (!Number.isInteger(year)) throw cardError('invalid_expiry_year', "Your card's expiry year is invalid.");
    const now = new Date();
    if (year < now.getFullYear() || (year === now.getFullYear() && month < now.getMonth() + 1)) {
      throw cardError('invalid_expiry_year', "Your card's expiration date is in the past.");
    }
    if (!/^\d{3}$/.test(String(body.cvc ?? ''))) throw cardError('incomplete_cvc', "Your card's security code is incomplete.");

    const token = {
      id: newId('tok'),
      object: 'token',
      card: { brand: card.brand, last4: number.slice(-4), funding: card.funding, exp_month: month, exp_year: year },
      created: nowSec(),
    };
    q('INSERT INTO tokens (id, brand, last4, funding, exp_month, exp_year, behaviour, created) VALUES (?, ?, ?, ?, ?, ?, ?, ?)')
      .run(token.id, card.brand, token.card.last4, card.funding, month, year, card.behaviour, token.created);
    return token;
  }

  /** Marks a token used and returns its row; tokens are single-use and expire */
  function spendToken(id) {
    const tok = q('SELECT * FROM tokens WHERE id = ?').get(String(id ?? ''));
    if (!tok) throw invalid('resource_missing', 'No such card token.');
    if (tok.used) throw invalid('token_already_used', 'This card token has already been used. Enter the card again.');
    if (tok.created < nowSec() - cfg.tokenTtlSec) throw invalid('token_expired', 'This card token has expired. Enter the card again.');
    q('UPDATE tokens SET used = 1 WHERE id = ?').run(tok.id);
    return tok;
  }

  function readAmount(body, max = MAX_AMOUNT) {
    const amount = Number(body.amount);
    if (!Number.isInteger(amount) || amount < MIN_AMOUNT || amount > max) {
      throw invalid('amount_invalid', `Amount must be a whole number of paisa between ${MIN_AMOUNT} and ${max}.`);
    }
    if ((body.currency ?? 'pkr') !== 'pkr') throw invalid('currency_unsupported', 'Only PKR is supported.');
    return amount;
  }

  function createIntent(body) {
    const amount = readAmount(body);
    return tx(() => {
      const tok = spendToken(body.token);
      const decline = CHARGE_DECLINES[tok.behaviour];
      const status = decline ? 'failed' : tok.behaviour === 'otp' ? 'requires_action' : 'succeeded';
      const t = nowSec();
      const id = newId('pi');
      q(`INSERT INTO payment_intents (id, amount, currency, status, description, metadata, card_brand, card_last4,
                                      card_funding, error_code, error_message, created, updated)
         VALUES (?, ?, 'pkr', ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`)
        .run(id, amount, status, body.description ?? null, JSON.stringify(body.metadata ?? {}), tok.brand, tok.last4,
          tok.funding, decline?.code ?? null, decline?.message ?? null, t, t);
      const intent = intentObject(getIntent(id));
      if (status === 'succeeded') emit('payment_intent.succeeded', intent);
      if (status === 'failed') emit('payment_intent.payment_failed', intent);
      return intent;
    });
  }

  function verifyIntent(id, body) {
    return tx(() => {
      const row = getIntent(id);
      if (!row) throw new GatewayError(404, 'invalid_request_error', 'resource_missing', 'No such payment.');
      if (row.status !== 'requires_action') return intentObject(row);
      const t = nowSec();
      if (String(body.otp ?? '').trim() === SANDBOX_OTP) {
        q("UPDATE payment_intents SET status = 'succeeded', updated = ? WHERE id = ?").run(t, id);
        const intent = intentObject(getIntent(id));
        emit('payment_intent.succeeded', intent);
        return intent;
      }
      const attempts = row.otp_attempts + 1;
      if (attempts >= OTP_ATTEMPTS) {
        q(`UPDATE payment_intents SET status = 'failed', otp_attempts = ?, error_code = 'authentication_failed',
             error_message = 'Too many incorrect codes.', updated = ? WHERE id = ?`).run(attempts, t, id);
        const intent = intentObject(getIntent(id));
        emit('payment_intent.payment_failed', intent);
        return intent;
      }
      q('UPDATE payment_intents SET otp_attempts = ?, updated = ? WHERE id = ?').run(attempts, t, id);
      const left = OTP_ATTEMPTS - attempts;
      throw cardError('incorrect_otp', `That code is incorrect. ${left} attempt${left === 1 ? '' : 's'} left.`);
    });
  }

  function createPayout(body) {
    const amount = readAmount(body);
    return tx(() => {
      if (balance().available < amount) {
        throw invalid('balance_insufficient', 'The merchant balance at Vendra Pay is too low for this payout.');
      }
      const tok = spendToken(body.token);
      const t = nowSec();
      const id = newId('po');
      q(`INSERT INTO payouts (id, amount, currency, status, description, metadata, card_brand, card_last4, behaviour,
                              arrival_at, created, updated)
         VALUES (?, ?, 'pkr', 'in_transit', ?, ?, ?, ?, ?, ?, ?, ?)`)
        .run(id, amount, body.description ?? null, JSON.stringify(body.metadata ?? {}), tok.brand, tok.last4,
          tok.behaviour, t + cfg.payoutDelaySec, t, t);
      return payoutObject(getPayout(id));
    });
  }

  /** Funds added to the merchant balance (e.g. to back money that predates the gateway) */
  function createTopup(body) {
    const amount = readAmount(body, MAX_TOPUP);
    const topup = {
      id: newId('tu'), object: 'topup', amount, currency: 'pkr', status: 'succeeded',
      description: body.description ?? null, metadata: body.metadata ?? {}, created: nowSec(),
    };
    q('INSERT INTO topups (id, amount, currency, description, metadata, created) VALUES (?, ?, ?, ?, ?, ?)')
      .run(topup.id, amount, 'pkr', topup.description, JSON.stringify(topup.metadata), topup.created);
    return topup;
  }

  /** Same Idempotency-Key on the same endpoint returns the first response */
  function idempotent(req, endpoint, fn) {
    const key = req.headers['idempotency-key'];
    if (!key) return fn();
    const hit = q('SELECT response FROM idempotency WHERE key = ? AND endpoint = ?').get(key, endpoint);
    if (hit) return JSON.parse(hit.response);
    const out = fn();
    q('INSERT OR IGNORE INTO idempotency (key, endpoint, response, created) VALUES (?, ?, ?, ?)')
      .run(key, endpoint, JSON.stringify(out), nowSec());
    return out;
  }

  // ──────────────────────────────────────
  // HTTP
  // ──────────────────────────────────────

  function requireKey(req, allowPublishable) {
    const key = (req.headers.authorization || '').replace(/^Bearer\s+/i, '');
    if (key === cfg.secretKey || (allowPublishable && key === cfg.publishableKey)) return;
    throw new GatewayError(401, 'authentication_error', 'invalid_api_key',
      allowPublishable ? 'Invalid API key.' : 'This request needs the secret key.');
  }

  async function readBody(req) {
    const chunks = [];
    let size = 0;
    for await (const c of req) {
      size += c.length;
      if (size > 64 * 1024) throw invalid('body_too_large', 'Request body is too large.');
      chunks.push(c);
    }
    if (!chunks.length) return {};
    try {
      return JSON.parse(Buffer.concat(chunks).toString('utf8'));
    } catch {
      throw invalid('invalid_json', 'Request body must be JSON.');
    }
  }

  const routes = [
    ['GET', /^\/health$/, () => ({ ok: true })],
    ['GET', /^\/v1\/test-cards$/, () => ({
      object: 'list',
      otp: SANDBOX_OTP,
      data: TEST_CARDS.map(({ number, brand, funding, label }) => ({ number, brand, funding, label })),
    })],
    ['POST', /^\/v1\/tokens$/, async (req) => {
      requireKey(req, true);
      return createToken(await readBody(req));
    }],
    ['POST', /^\/v1\/payment_intents$/, async (req) => {
      requireKey(req, false);
      const body = await readBody(req);
      return idempotent(req, 'payment_intents', () => createIntent(body));
    }],
    ['GET', /^\/v1\/payment_intents\/([\w-]+)$/, (req, [id]) => {
      requireKey(req, false);
      const row = getIntent(id);
      if (!row) throw new GatewayError(404, 'invalid_request_error', 'resource_missing', 'No such payment.');
      return intentObject(row);
    }],
    ['POST', /^\/v1\/payment_intents\/([\w-]+)\/verify$/, async (req, [id]) => {
      requireKey(req, true);
      return verifyIntent(id, await readBody(req));
    }],
    ['POST', /^\/v1\/payouts$/, async (req) => {
      requireKey(req, false);
      const body = await readBody(req);
      return idempotent(req, 'payouts', () => createPayout(body));
    }],
    ['GET', /^\/v1\/payouts\/([\w-]+)$/, (req, [id]) => {
      requireKey(req, false);
      const row = getPayout(id);
      if (!row) throw new GatewayError(404, 'invalid_request_error', 'resource_missing', 'No such payout.');
      return payoutObject(row);
    }],
    ['POST', /^\/v1\/topups$/, async (req) => {
      requireKey(req, false);
      const body = await readBody(req);
      return idempotent(req, 'topups', () => createTopup(body));
    }],
    ['GET', /^\/v1\/balance$/, (req) => {
      requireKey(req, false);
      return balance();
    }],
  ];

  function dashboardData() {
    return {
      balance: balance(),
      intents: q('SELECT * FROM payment_intents ORDER BY created DESC, rowid DESC LIMIT 50').all().map(intentObject),
      payouts: q('SELECT * FROM payouts ORDER BY created DESC, rowid DESC LIMIT 50').all().map(payoutObject),
      events: q('SELECT id, type, object_id, created, delivered_at, attempts, last_status, last_error FROM events ORDER BY created DESC, rowid DESC LIMIT 50').all(),
      testCards: TEST_CARDS,
      otp: SANDBOX_OTP,
      webhookUrl: cfg.webhookUrl,
    };
  }

  const server = http.createServer(async (req, res) => {
    res.setHeader('Access-Control-Allow-Origin', '*');
    res.setHeader('Access-Control-Allow-Headers', 'Authorization, Content-Type, Idempotency-Key');
    res.setHeader('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
    if (req.method === 'OPTIONS') {
      res.writeHead(204).end();
      return;
    }
    const url = new URL(req.url, 'http://gateway');
    if (req.method === 'GET' && url.pathname === '/') {
      res.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8' }).end(renderDashboard(dashboardData()));
      return;
    }
    let status = 200;
    let payload;
    try {
      const route = routes.find(([m, re]) => m === req.method && re.test(url.pathname));
      if (!route) throw new GatewayError(404, 'invalid_request_error', 'not_found', 'Unknown endpoint.');
      payload = await route[2](req, url.pathname.match(route[1]).slice(1));
    } catch (err) {
      if (!(err instanceof GatewayError)) {
        console.error('Vendra Pay error:', err);
        err = new GatewayError(500, 'api_error', 'internal_error', 'Something went wrong at Vendra Pay.');
      }
      status = err.status;
      payload = { error: { type: err.type, code: err.code, message: err.message } };
    }
    cfg.log(`${new Date().toISOString()} | ${req.method} ${url.pathname} → ${status}`);
    res.writeHead(status, { 'Content-Type': 'application/json' }).end(JSON.stringify(payload));
  });

  let timer = null;
  return {
    server,
    tick,
    balance,
    setWebhookUrl(url) {
      cfg.webhookUrl = url;
    },
    /** Starts the once-a-second clock for payouts, OTP expiry and webhook retries */
    startClock() {
      timer = setInterval(() => tick().catch((err) => console.error('Vendra Pay tick failed:', err.message)), 1000);
      timer.unref();
    },
    close() {
      if (timer) clearInterval(timer);
      db.close();
    },
  };
}

module.exports = { createGateway, signPayload };
