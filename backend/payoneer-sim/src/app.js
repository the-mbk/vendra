// ══════════════════════════════════════════════════════════════
// Payoneer sandbox simulator for Vendra — no npm dependencies (Node's built-in SQLite).
//
// Stands in for Payoneer's Mass Payouts API (v4) until Vendra has partner
// sandbox credentials. It follows that API's flow: an OAuth client-credentials
// token, a hosted registration link per payee (sign up or link an existing
// Payoneer account), payee status, mass payouts by client_reference_id,
// payout status, program balance, and IPCN callbacks.
//
// UNVERIFIED: Payoneer's docs are behind their partner portal. Paths, field
// names and status values here follow the v4 API as commonly documented;
// check them against the real reference before switching
// (backend/src/services/payouts/payoneer.js is the only file that talks to it).
//
//   POST /api/v2/oauth2/token                                  client credentials → access_token
//   POST /v4/programs/:program/payees/registration-link        { payee_id, redirect_url, payee } → { result: { registration_link } }
//   GET  /v4/programs/:program/payees/:payee/status            { result: { status: { type, description } } }
//   POST /v4/programs/:program/masspayouts                     { Payments: [{ client_reference_id, payee_id, amount, currency, description }] }
//   GET  /v4/programs/:program/payouts/:client_reference/status { result: { status, amount, currency, … } }
//   GET  /v4/programs/:program/balance                         { result: { balance, currency } }
//   GET  /partners/sign-up?token=…                             the hosted registration page
//   GET  /payee/:payee                                         the payee's own Payoneer account (balance, payments received)
//   GET  /                                                     program dashboard
// Payees whose email contains "+fail" are approved but their payouts fail (for testing).
// ══════════════════════════════════════════════════════════════

const http = require('http');
const crypto = require('crypto');
const { DatabaseSync } = require('node:sqlite');

const SCHEMA = `
CREATE TABLE IF NOT EXISTS tokens (token TEXT PRIMARY KEY, expires INTEGER NOT NULL);
CREATE TABLE IF NOT EXISTS registration_links (
  token TEXT PRIMARY KEY, payee_id TEXT NOT NULL, redirect_url TEXT, first_name TEXT, last_name TEXT, email TEXT, created INTEGER NOT NULL);
CREATE TABLE IF NOT EXISTS payees (
  payee_id TEXT PRIMARY KEY, payoneer_id TEXT NOT NULL, first_name TEXT, last_name TEXT, email TEXT,
  linked_existing INTEGER NOT NULL DEFAULT 0, status TEXT NOT NULL, balance INTEGER NOT NULL DEFAULT 0,
  approve_at INTEGER, created INTEGER NOT NULL, updated INTEGER NOT NULL);
CREATE TABLE IF NOT EXISTS payouts (
  client_reference_id TEXT PRIMARY KEY, payee_id TEXT NOT NULL, amount INTEGER NOT NULL, currency TEXT NOT NULL,
  description TEXT, status TEXT NOT NULL, reason TEXT, settle_at INTEGER NOT NULL, created INTEGER NOT NULL, updated INTEGER NOT NULL);
CREATE TABLE IF NOT EXISTS program (id INTEGER PRIMARY KEY CHECK (id = 1), balance INTEGER NOT NULL);
CREATE TABLE IF NOT EXISTS ipcn (id INTEGER PRIMARY KEY AUTOINCREMENT, query TEXT NOT NULL, status INTEGER, error TEXT, created INTEGER NOT NULL);
`;

class ApiError extends Error {
  constructor(status, code, description) {
    super(description);
    this.status = status;
    this.code = code;
  }
}

const nowSec = () => Math.floor(Date.now() / 1000);
const esc = (s) => String(s ?? '').replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[c]);
const usd = (cents) => `$${(cents / 100).toLocaleString('en-US', { minimumFractionDigits: 2, maximumFractionDigits: 2 })}`;

/** Payee status as the API reports it */
const STATUS_TEXT = { ACTIVE: 'Active', PENDING: 'Pending approval', INACTIVE: 'Inactive' };

function createPayoneerSim(options = {}) {
  const cfg = {
    dbPath: ':memory:',
    clientId: 'vendra_sandbox',
    clientSecret: 'vendra_sandbox_secret',
    programId: '100086',
    ipcnUrl: null,               // the platform's IPCN endpoint (query string callbacks)
    publicUrl: 'http://localhost:4343',
    approvalDelaySec: 8,         // a new payee is PENDING this long, then ACTIVE
    payoutDelaySec: 15,          // a payout is Pending this long, then Transferred
    startingBalanceCents: 100_000_000, // the program's funds: $1,000,000
    log: () => {},
    ...options,
  };

  const db = new DatabaseSync(cfg.dbPath);
  db.exec('PRAGMA journal_mode = WAL;');
  db.exec(SCHEMA);
  const q = (sql) => db.prepare(sql);
  q('INSERT OR IGNORE INTO program (id, balance) VALUES (1, ?)').run(cfg.startingBalanceCents);
  const programBalance = () => q('SELECT balance FROM program WHERE id = 1').get().balance;

  // ── IPCN: Payoneer calls the platform back with a GET and query parameters
  async function ipcn(params) {
    const query = new URLSearchParams(params).toString();
    const row = q('INSERT INTO ipcn (query, created) VALUES (?, ?) RETURNING id').get(query, nowSec());
    if (!cfg.ipcnUrl) return;
    let status = null;
    let error = null;
    try {
      const res = await fetch(`${cfg.ipcnUrl}${cfg.ipcnUrl.includes('?') ? '&' : '?'}${query}`, { signal: AbortSignal.timeout(5000) });
      status = res.status;
      if (!res.ok) error = `HTTP ${res.status}`;
    } catch (err) {
      error = err.message;
    }
    q('UPDATE ipcn SET status = ?, error = ? WHERE id = ?').run(status, error, row.id);
  }

  // ── Time-based work: payees get approved, payouts arrive
  async function tick() {
    const t = nowSec();
    for (const p of q("SELECT * FROM payees WHERE status = 'PENDING' AND approve_at <= ?").all(t)) {
      q("UPDATE payees SET status = 'ACTIVE', updated = ? WHERE payee_id = ?").run(t, p.payee_id);
      await ipcn({ APPROVED: '', apuid: p.payee_id, payeeid: p.payoneer_id });
    }
    for (const p of q("SELECT * FROM payouts WHERE status = 'Pending' AND settle_at <= ?").all(t)) {
      const payee = q('SELECT * FROM payees WHERE payee_id = ?').get(p.payee_id);
      const fail = /\+fail/i.test(payee?.email || '');
      db.exec('BEGIN IMMEDIATE');
      if (fail) {
        q("UPDATE payouts SET status = 'Failed', reason = 'The payee account could not receive the payment.', updated = ? WHERE client_reference_id = ?")
          .run(t, p.client_reference_id);
        q('UPDATE program SET balance = balance + ? WHERE id = 1').run(p.amount); // back to the program
      } else {
        q("UPDATE payouts SET status = 'Transferred', updated = ? WHERE client_reference_id = ?").run(t, p.client_reference_id);
        q('UPDATE payees SET balance = balance + ?, updated = ? WHERE payee_id = ?').run(p.amount, t, p.payee_id);
      }
      db.exec('COMMIT');
      await ipcn({ PAYMENT: '', apuid: p.payee_id, paymentid: p.client_reference_id, status: fail ? 'Failed' : 'Transferred' });
    }
  }

  // ── API
  function requireToken(req) {
    const token = (req.headers.authorization || '').replace(/^Bearer\s+/i, '');
    const row = token && q('SELECT * FROM tokens WHERE token = ?').get(token);
    if (!row || row.expires < nowSec()) throw new ApiError(401, 'invalid_token', 'The access token is missing, invalid or expired.');
  }

  function requireProgram(programId) {
    if (programId !== cfg.programId) throw new ApiError(404, 'program_not_found', `Program ${programId} does not exist.`);
  }

  function issueToken(req, body) {
    const basic = (req.headers.authorization || '').replace(/^Basic\s+/i, '');
    const [id, secret] = Buffer.from(basic, 'base64').toString('utf8').split(':');
    if (id !== cfg.clientId || secret !== cfg.clientSecret) throw new ApiError(401, 'invalid_client', 'Client authentication failed.');
    if (body.get('grant_type') !== 'client_credentials') throw new ApiError(400, 'unsupported_grant_type', 'Use grant_type=client_credentials.');
    const token = crypto.randomBytes(24).toString('base64url');
    const expiresIn = 30 * 24 * 3600;
    q('INSERT INTO tokens (token, expires) VALUES (?, ?)').run(token, nowSec() + expiresIn);
    return { token_type: 'Bearer', access_token: token, expires_in: expiresIn, scope: body.get('scope') || 'read write', consented_on: nowSec() };
  }

  function registrationLink(body) {
    const payeeId = String(body.payee_id ?? '').trim();
    if (!/^[\w.-]{1,64}$/.test(payeeId)) throw new ApiError(400, 'invalid_payee_id', 'payee_id is required (letters, digits, . _ -, up to 64).');
    const contact = body.payee?.contact || {};
    const token = crypto.randomBytes(18).toString('base64url');
    q('INSERT INTO registration_links (token, payee_id, redirect_url, first_name, last_name, email, created) VALUES (?, ?, ?, ?, ?, ?, ?)')
      .run(token, payeeId, body.redirect_url || null, contact.first_name || null, contact.last_name || null, contact.email || null, nowSec());
    return { result: { registration_link: `${cfg.publicUrl}/partners/sign-up?token=${token}`, token } };
  }

  function payeeStatus(payeeId) {
    const p = q('SELECT * FROM payees WHERE payee_id = ?').get(payeeId);
    if (!p) throw new ApiError(404, 'payee_not_found', 'Payee does not exist.');
    return { result: { status: { type: p.status, description: STATUS_TEXT[p.status] } } };
  }

  function payoutView(p) {
    return {
      result: {
        client_reference_id: p.client_reference_id,
        payee_id: p.payee_id,
        amount: p.amount / 100,
        currency: p.currency,
        status: p.status,
        reason: p.reason,
        payout_date: new Date(p.created * 1000).toISOString(),
      },
    };
  }

  /** Submits payments. Re-submitting an existing client_reference_id is a no-op (idempotent). */
  function massPayout(body) {
    const payments = body.Payments || body.payments;
    if (!Array.isArray(payments) || payments.length === 0) throw new ApiError(400, 'invalid_request', 'Payments must be a non-empty array.');
    const t = nowSec();
    db.exec('BEGIN IMMEDIATE');
    try {
      for (const pay of payments) {
        const ref = String(pay.client_reference_id ?? '');
        if (!ref) throw new ApiError(400, 'invalid_request', 'client_reference_id is required.');
        if (q('SELECT 1 FROM payouts WHERE client_reference_id = ?').get(ref)) continue;
        const payee = q('SELECT * FROM payees WHERE payee_id = ?').get(String(pay.payee_id ?? ''));
        if (!payee) throw new ApiError(400, 'payee_not_found', `Payee ${pay.payee_id} does not exist.`);
        if (payee.status !== 'ACTIVE') throw new ApiError(400, 'payee_inactive', `Payee ${pay.payee_id} is not active yet.`);
        const currency = String(pay.currency || 'USD').toUpperCase();
        if (currency !== 'USD') throw new ApiError(400, 'currency_not_supported', 'This program pays in USD.');
        const amount = Math.round(Number(pay.amount) * 100);
        if (!Number.isFinite(amount) || amount < 1) throw new ApiError(400, 'invalid_amount', 'amount must be a positive decimal, e.g. 17.86.');
        if (amount > programBalance()) throw new ApiError(400, 'insufficient_funds', 'The program balance is too low for this payout.');
        q('UPDATE program SET balance = balance - ? WHERE id = 1').run(amount);
        q(`INSERT INTO payouts (client_reference_id, payee_id, amount, currency, description, status, settle_at, created, updated)
           VALUES (?, ?, ?, ?, ?, 'Pending', ?, ?, ?)`)
          .run(ref, payee.payee_id, amount, currency, pay.description || null, t + cfg.payoutDelaySec, t, t);
      }
      db.exec('COMMIT');
    } catch (err) {
      db.exec('ROLLBACK');
      throw err;
    }
    return { result: 'Payments Created' };
  }

  function payoutStatus(ref) {
    const p = q('SELECT * FROM payouts WHERE client_reference_id = ?').get(ref);
    if (!p) throw new ApiError(404, 'payout_not_found', 'Payout does not exist.');
    return payoutView(p);
  }

  // ── Hosted pages
  const page = (title, body) => `<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>${esc(title)}</title><style>
:root{--brand:#ff4800;--ink:#1d2433;--muted:#6b7280;--line:#e5e7eb;--bg:#f6f7f9}
@media (prefers-color-scheme: dark){:root{--ink:#e8ebf1;--muted:#9aa3b2;--line:#2a2f39;--bg:#14171d}}
*{box-sizing:border-box}body{margin:0;font:15px/1.5 system-ui,sans-serif;color:var(--ink);background:var(--bg)}
header{background:var(--brand);color:#fff;padding:14px 20px;font-weight:700;letter-spacing:.3px}header small{font-weight:400;opacity:.85;margin-left:8px}
main{max-width:760px;margin:24px auto;padding:0 16px}.card{background:Canvas;border:1px solid var(--line);border-radius:14px;padding:22px;margin-bottom:16px}
h1{font-size:22px;margin:0 0 6px}h2{font-size:16px;margin:0 0 10px}p{margin:6px 0}.muted{color:var(--muted)}
label{display:block;font-size:13px;color:var(--muted);margin:12px 0 4px}input{width:100%;padding:10px 12px;border:1px solid var(--line);border-radius:10px;font:inherit;background:Canvas;color:var(--ink)}
button{margin-top:16px;width:100%;padding:12px;border:0;border-radius:10px;background:var(--brand);color:#fff;font:inherit;font-weight:600;cursor:pointer}
.tabs{display:flex;gap:8px;margin-bottom:6px}.tabs a{padding:6px 12px;border-radius:999px;border:1px solid var(--line);color:var(--ink);text-decoration:none;font-size:14px}.tabs a.on{background:var(--brand);border-color:var(--brand);color:#fff}
table{width:100%;border-collapse:collapse;font-size:14px}td,th{padding:8px 6px;border-bottom:1px solid var(--line);text-align:left}
.big{font-size:30px;font-weight:700}.pill{display:inline-block;padding:2px 10px;border-radius:999px;font-size:12px;font-weight:600;background:var(--line)}
.ok{background:#d1fadf;color:#05603a}.wait{background:#fef0c7;color:#93370d}.bad{background:#fee4e2;color:#912018}
</style></head><body><header>Payoneer <small>sandbox simulator for Vendra</small></header><main>${body}</main></body></html>`;

  const statusPill = (s) => `<span class="pill ${/ACTIVE|Transferred/.test(s) ? 'ok' : /PENDING|Pending/.test(s) ? 'wait' : 'bad'}">${esc(STATUS_TEXT[s] || s)}</span>`;

  function signUpPage(token, mode, error) {
    const link = token && q('SELECT * FROM registration_links WHERE token = ?').get(token);
    if (!link) return page('Link expired', '<div class="card"><h1>This link is not valid</h1><p class="muted">Go back to the Vendra app and tap “Link Payoneer account” again.</p></div>');
    const existing = mode === 'existing';
    const name = [link.first_name, link.last_name].filter(Boolean).join(' ');
    return page('Payoneer sign-up', `<div class="card">
<h1>Get paid by Vendra</h1>
<p class="muted">Vendra pays your earnings into your Payoneer account. From there you can withdraw to your bank in Pakistan.</p>
<div class="tabs" style="margin-top:14px"><a class="${existing ? '' : 'on'}" href="?token=${esc(token)}">Create an account</a><a class="${existing ? 'on' : ''}" href="?token=${esc(token)}&mode=existing">I already have Payoneer</a></div>
${error ? `<p class="pill bad">${esc(error)}</p>` : ''}
<form method="post" action="/partners/sign-up">
<input type="hidden" name="token" value="${esc(token)}"><input type="hidden" name="mode" value="${existing ? 'existing' : 'new'}">
${existing ? '' : `<label for="name">Full name</label><input id="name" name="name" value="${esc(name)}" required>`}
<label for="email">${existing ? 'Your Payoneer email' : 'Email'}</label><input id="email" name="email" type="email" value="${esc(link.email || '')}" required>
<label for="password">Password</label><input id="password" name="password" type="password" value="sandbox" required>
${existing ? '' : '<label for="bank">Bank account in Pakistan (IBAN)</label><input id="bank" name="bank" value="PK36SCBL0000001123456702" required>'}
<button type="submit">${existing ? 'Sign in and link to Vendra' : 'Create account and link to Vendra'}</button>
</form>
<p class="muted" style="font-size:12px;margin-top:12px">Sandbox: any password works. An email containing “+fail” creates a payee whose payments fail.</p></div>`);
  }

  function completeSignUp(form) {
    const link = q('SELECT * FROM registration_links WHERE token = ?').get(form.get('token') || '');
    if (!link) return { html: signUpPage(null) };
    const email = (form.get('email') || '').trim();
    if (!/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(email)) return { html: signUpPage(link.token, form.get('mode'), 'Enter a valid email.') };
    const t = nowSec();
    const [first, ...rest] = (form.get('name') || [link.first_name, link.last_name].filter(Boolean).join(' ') || email.split('@')[0]).trim().split(/\s+/);
    const existing = q('SELECT * FROM payees WHERE payee_id = ?').get(link.payee_id);
    if (!existing) {
      q(`INSERT INTO payees (payee_id, payoneer_id, first_name, last_name, email, linked_existing, status, approve_at, created, updated)
         VALUES (?, ?, ?, ?, ?, ?, 'PENDING', ?, ?, ?)`)
        .run(link.payee_id, String(40_000_000 + Math.floor(Math.random() * 9_000_000)), first, rest.join(' ') || null, email,
          form.get('mode') === 'existing' ? 1 : 0, t + cfg.approvalDelaySec, t, t);
      ipcn({ REG: '', apuid: link.payee_id }).catch(() => {});
    }
    q('DELETE FROM registration_links WHERE token = ?').run(link.token);
    if (link.redirect_url) return { redirect: link.redirect_url };
    return { html: page('Linked', '<div class="card"><h1>Your Payoneer account is linked</h1><p>You can close this tab and go back to the Vendra app.</p></div>') };
  }

  function payeePage(payeeId) {
    const p = q('SELECT * FROM payees WHERE payee_id = ?').get(payeeId);
    if (!p) return page('Not found', '<div class="card"><h1>No such Payoneer account</h1></div>');
    const payments = q('SELECT * FROM payouts WHERE payee_id = ? ORDER BY created DESC LIMIT 50').all(payeeId);
    return page('My Payoneer account', `<div class="card"><p class="muted">${esc(p.first_name)} ${esc(p.last_name || '')} · ${esc(p.email)} · Customer ID ${esc(p.payoneer_id)} ${statusPill(p.status)}</p>
<p class="muted">Balance</p><p class="big">${usd(p.balance)}</p>
<p class="muted" style="font-size:13px">In the real Payoneer you would now withdraw this to your bank in Pakistan.</p></div>
<div class="card"><h2>Payments received</h2>${payments.length ? `<table><tr><th>Date</th><th>From</th><th>Amount</th><th>Status</th></tr>${payments.map((x) =>
      `<tr><td>${new Date(x.created * 1000).toLocaleString()}</td><td>Vendra · ${esc(x.description || x.client_reference_id)}</td><td>${usd(x.amount)}</td><td>${statusPill(x.status)}</td></tr>`).join('')}</table>`
      : '<p class="muted">Nothing yet.</p>'}</div>`);
  }

  function dashboardPage() {
    const payees = q('SELECT * FROM payees ORDER BY created DESC LIMIT 100').all();
    const payouts = q('SELECT * FROM payouts ORDER BY created DESC LIMIT 100').all();
    const calls = q('SELECT * FROM ipcn ORDER BY id DESC LIMIT 30').all();
    return page('Payoneer program', `<div class="card"><p class="muted">Program ${esc(cfg.programId)} · IPCN → ${esc(cfg.ipcnUrl || 'not configured')}</p>
<p class="muted">Program balance</p><p class="big">${usd(programBalance())}</p></div>
<div class="card"><h2>Payees (${payees.length})</h2><table><tr><th>Payee ID</th><th>Name</th><th>Status</th><th>Balance</th></tr>${payees.map((p) =>
      `<tr><td><a href="/payee/${encodeURIComponent(p.payee_id)}">${esc(p.payee_id)}</a></td><td>${esc(p.first_name)} ${esc(p.last_name || '')}</td><td>${statusPill(p.status)}</td><td>${usd(p.balance)}</td></tr>`).join('')}</table></div>
<div class="card"><h2>Payouts</h2><table><tr><th>Reference</th><th>Payee</th><th>Amount</th><th>Status</th></tr>${payouts.map((p) =>
      `<tr><td>${esc(p.client_reference_id)}</td><td>${esc(p.payee_id)}</td><td>${usd(p.amount)}</td><td>${statusPill(p.status)}</td></tr>`).join('')}</table></div>
<div class="card"><h2>IPCN callbacks</h2><table><tr><th>When</th><th>Query</th><th>Result</th></tr>${calls.map((c) =>
      `<tr><td>${new Date(c.created * 1000).toLocaleTimeString()}</td><td><code>${esc(c.query)}</code></td><td>${esc(c.status ?? c.error ?? 'not sent')}</td></tr>`).join('')}</table></div>`);
  }

  // ── HTTP
  async function readRaw(req) {
    const chunks = [];
    let size = 0;
    for await (const c of req) {
      size += c.length;
      if (size > 64 * 1024) throw new ApiError(413, 'body_too_large', 'Request body is too large.');
      chunks.push(c);
    }
    return Buffer.concat(chunks).toString('utf8');
  }
  const readJson = async (req) => {
    const raw = await readRaw(req);
    if (!raw) return {};
    try {
      return JSON.parse(raw);
    } catch {
      throw new ApiError(400, 'invalid_json', 'Request body must be JSON.');
    }
  };

  const api = [
    ['GET', /^\/health$/, () => ({ ok: true })],
    ['POST', /^\/api\/v2\/oauth2\/token$/, async (req) => issueToken(req, new URLSearchParams(await readRaw(req)))],
    ['POST', /^\/v4\/programs\/([\w-]+)\/payees\/registration-link$/, async (req, [prog]) => {
      requireToken(req); requireProgram(prog);
      return registrationLink(await readJson(req));
    }],
    ['GET', /^\/v4\/programs\/([\w-]+)\/payees\/([\w.-]+)\/status$/, (req, [prog, payee]) => {
      requireToken(req); requireProgram(prog);
      return payeeStatus(payee);
    }],
    ['POST', /^\/v4\/programs\/([\w-]+)\/masspayouts$/, async (req, [prog]) => {
      requireToken(req); requireProgram(prog);
      return massPayout(await readJson(req));
    }],
    ['GET', /^\/v4\/programs\/([\w-]+)\/payouts\/([\w.-]+)\/status$/, (req, [prog, ref]) => {
      requireToken(req); requireProgram(prog);
      return payoutStatus(ref);
    }],
    ['GET', /^\/v4\/programs\/([\w-]+)\/balance$/, (req, [prog]) => {
      requireToken(req); requireProgram(prog);
      return { result: { balance: programBalance() / 100, currency: 'USD', fees_due: 0 } };
    }],
  ];

  const server = http.createServer(async (req, res) => {
    const url = new URL(req.url, 'http://payoneer');
    const html = (status, body) => res.writeHead(status, { 'Content-Type': 'text/html; charset=utf-8' }).end(body);
    try {
      if (req.method === 'GET' && url.pathname === '/') return html(200, dashboardPage());
      if (req.method === 'GET' && url.pathname === '/partners/sign-up') {
        return html(200, signUpPage(url.searchParams.get('token'), url.searchParams.get('mode')));
      }
      if (req.method === 'POST' && url.pathname === '/partners/sign-up') {
        const out = completeSignUp(new URLSearchParams(await readRaw(req)));
        if (out.redirect) return res.writeHead(303, { Location: out.redirect }).end();
        return html(200, out.html);
      }
      const payeeMatch = /^\/payee\/([\w.-]+)$/.exec(url.pathname);
      if (req.method === 'GET' && payeeMatch) return html(200, payeePage(payeeMatch[1]));

      let status = 200;
      let payload;
      try {
        const route = api.find(([m, re]) => m === req.method && re.test(url.pathname));
        if (!route) throw new ApiError(404, 'not_found', 'Unknown endpoint.');
        payload = await route[2](req, url.pathname.match(route[1]).slice(1));
      } catch (err) {
        if (!(err instanceof ApiError)) throw err;
        status = err.status;
        payload = { error: err.code, error_description: err.message };
      }
      cfg.log(`${new Date().toISOString()} | ${req.method} ${url.pathname} → ${status}`);
      res.writeHead(status, { 'Content-Type': 'application/json' }).end(JSON.stringify(payload));
    } catch (err) {
      console.error('Payoneer simulator error:', err);
      res.writeHead(500, { 'Content-Type': 'application/json' }).end(JSON.stringify({ error: 'internal_error', error_description: 'Something went wrong.' }));
    }
  });

  let timer = null;
  return {
    server,
    tick,
    setIpcnUrl(url) { cfg.ipcnUrl = url; },
    setPublicUrl(url) { cfg.publicUrl = url; },
    programBalance,
    /** Test helper: what a payee holds at "Payoneer" */
    payee: (payeeId) => q('SELECT * FROM payees WHERE payee_id = ?').get(payeeId),
    startClock() {
      timer = setInterval(() => tick().catch((err) => console.error('Payoneer simulator tick failed:', err.message)), 1000);
      timer.unref();
    },
    close() {
      if (timer) clearInterval(timer);
      db.close();
    },
  };
}

module.exports = { createPayoneerSim };
