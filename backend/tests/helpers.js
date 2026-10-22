// ══════════════════════════════════════════════════════════════
// Test helpers — a throwaway database per run + an in-process server.
// Requires TEST_DATABASE_URL pointing at a Postgres the tests may
// DROP and CREATE databases on, e.g.
//   TEST_DATABASE_URL=postgresql://postgres:test@localhost:55432/vendra_it
// ══════════════════════════════════════════════════════════════

const { Client } = require('pg');

const TEST_DATABASE_URL = process.env.TEST_DATABASE_URL;
if (!TEST_DATABASE_URL) {
  throw new Error('Set TEST_DATABASE_URL (a database the tests are allowed to drop and recreate).');
}

// Must be set before anything requires src/db.js or the storage service.
// Files go to a temp folder unless S3_BUCKET is set (then the S3 driver is tested).
process.env.DATABASE_URL = TEST_DATABASE_URL;
process.env.UPLOAD_DIR = require('path').join(require('os').tmpdir(), 'vendra-test-uploads');
process.env.JWT_SECRET = process.env.JWT_SECRET || 'test-secret';
process.env.NODE_ENV = 'test';

async function resetDatabase() {
  const url = new URL(TEST_DATABASE_URL);
  const dbName = url.pathname.slice(1);
  if (!/^[a-z0-9_]+$/i.test(dbName)) throw new Error(`Unsafe test database name: ${dbName}`);

  url.pathname = '/postgres';
  const admin = new Client({ connectionString: url.toString() });
  await admin.connect();
  await admin.query(`DROP DATABASE IF EXISTS ${dbName} WITH (FORCE)`);
  await admin.query(`CREATE DATABASE ${dbName}`);
  await admin.end();

  const { migrate } = require('../src/migrate');
  await migrate(TEST_DATABASE_URL, { log: () => {} });
  // Small fixed fixture (a few Karachi/Lahore accounts) that the tests' ids and coordinates rely on
  const client = new Client({ connectionString: TEST_DATABASE_URL });
  await client.connect();
  await client.query(require('fs').readFileSync(require('path').join(__dirname, 'fixture.sql'), 'utf8'));
  await client.end();
}

/**
 * Starts the API and an in-process Vendra Pay gateway wired to each other
 * (payouts land on the next gateway.tick(); webhooks go to the API).
 */
async function startServer() {
  const { createGateway } = require('../gateway/src/app');
  const gateway = createGateway({ payoutDelaySec: 0 });
  await new Promise((resolve) => gateway.server.listen(0, resolve));
  const gatewayUrl = `http://127.0.0.1:${gateway.server.address().port}`;
  process.env.GATEWAY_URL = gatewayUrl;

  const { createServer } = require('../src/app');
  await require('../src/services/storage.service').initStorage();
  const { server } = createServer({ logRequests: false });
  await new Promise((resolve) => server.listen(0, resolve));
  const baseUrl = `http://127.0.0.1:${server.address().port}`;
  gateway.setWebhookUrl(`${baseUrl}/api/payments/webhook`);

  async function stop() {
    const { closeRealtime } = require('../src/realtime');
    await closeRealtime();
    await new Promise((resolve) => server.close(resolve));
    await new Promise((resolve) => gateway.server.close(resolve));
    gateway.close();
    await require('../src/db').end();
  }
  return { server, baseUrl, gateway, gatewayUrl, stop };
}

/** Tokenizes a test card at the gateway, as the apps do (card numbers never reach the API) */
async function cardToken(gatewayUrl, number = '4242424242424242') {
  const res = await fetch(`${gatewayUrl}/v1/tokens`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', Authorization: 'Bearer pk_test_vendra' },
    body: JSON.stringify({ number, exp_month: 12, exp_year: new Date().getFullYear() + 3, cvc: '123' }),
  });
  const body = await res.json();
  if (!res.ok) throw new Error(`Tokenize failed: ${JSON.stringify(body)}`);
  return body.id;
}

/** Small fetch wrapper: api(baseUrl)('POST', '/api/x', body, token) → { status, body } */
function apiClient(baseUrl) {
  return async (method, path, body, token) => {
    const headers = {};
    let payload;
    if (body instanceof FormData) payload = body;
    else if (body !== undefined) {
      headers['Content-Type'] = 'application/json';
      payload = JSON.stringify(body);
    }
    if (token) headers.Authorization = `Bearer ${token}`;
    const res = await fetch(`${baseUrl}${path}`, { method, headers, body: payload });
    const text = await res.text();
    let json;
    try { json = JSON.parse(text); } catch { json = text; }
    return { status: res.status, body: json };
  };
}

async function query(sql, params) {
  return require('../src/db').query(sql, params);
}

/**
 * Money is never created or destroyed: every rupee deposited is either in a
 * wallet, held in the escrow pool, or earned by the platform.
 */
async function moneyInvariant() {
  const r = await query(`
    SELECT
      (SELECT COALESCE(SUM(wallet_balance), 0) FROM users) AS wallets,
      (SELECT balance FROM platform_escrow_wallet WHERE id = 1) AS pool,
      (SELECT COALESCE(SUM(amount), 0) FROM platform_ledger) AS platform,
      (SELECT COALESCE(SUM(CASE WHEN transaction_type = 'withdrawal' THEN -amount ELSE amount END), 0)
         FROM wallet_ledger
        WHERE transaction_type IN ('deposit', 'opening_balance', 'withdrawal', 'withdrawal_reversal')) AS deposits,
      (SELECT COALESCE(SUM(total_amount - rider_payout), 0) FROM orders WHERE escrow_status IN ('held', 'disputed')) AS held`);
  const row = r.rows[0];
  return {
    accounted: Number(row.wallets) + Number(row.pool) + Number(row.platform),
    deposits: Number(row.deposits),
    pool: Number(row.pool),
    held: Number(row.held),
  };
}

module.exports = { resetDatabase, startServer, cardToken, apiClient, query, moneyInvariant };
