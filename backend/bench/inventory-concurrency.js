// ══════════════════════════════════════════════════════════════
// PR 04 benchmark — "100 concurrent inventory requests per second
// without stock corruption".
//
// Fires online checkouts at a steady rate (open loop: a request goes out on
// schedule whether or not earlier ones have answered) at ONE product, while
// the store sells the same product at the walk-in counter (POS). Stock runs
// out part-way, so the run also shows that late buyers are refused (409)
// instead of being oversold. Afterwards every stock number is checked
// against what actually succeeded.
//
// --products=1 (default) is the worst case: every request fights for the same
// row lock. --products=10 spreads the same load over ten products, which is
// closer to a real marketplace.
//
//   TEST_DATABASE_URL=postgresql://postgres:test@localhost:55432/vendra_bench \
//     npm run bench:concurrency -- --rate=100 --duration=15 --stock=600
//
// Options: --rate (checkouts/s, default 100) --duration (s, default 15)
//          --stock (units per product, default 600) --pos-rate (walk-in sales/s, default 5)
//          --products (default 1) --customers (default 300)
// The database in TEST_DATABASE_URL is DROPPED and recreated, like the tests.
// Writes bench/results/concurrency-<time>.json and .html (chart for the report).
// ══════════════════════════════════════════════════════════════

const fs = require('fs');
const path = require('path');
const jwt = require('jsonwebtoken');
const { resetDatabase, startServer, query, moneyInvariant } = require('../tests/helpers');

const arg = (name, fallback) => {
  const a = process.argv.find((x) => x.startsWith(`--${name}=`));
  const n = a ? Number(a.split('=')[1]) : fallback;
  if (!Number.isFinite(n) || n <= 0) throw new Error(`--${name} must be a positive number`);
  return n;
};

const RATE = arg('rate', 100);
const DURATION_S = arg('duration', 15);
const STOCK = Math.round(arg('stock', 600));
const POS_RATE = arg('pos-rate', 5);
const CUSTOMERS = Math.round(arg('customers', 300));
const PRODUCTS = Math.round(arg('products', 1));
const BUFFER = 20;
const PRICE = 500;
const VENDOR_USER_ID = 2; // fixture: Karachi Electronics Hub
const VENDOR_ID = 1;

const percentile = (sorted, p) => (sorted.length ? sorted[Math.min(sorted.length - 1, Math.floor((p / 100) * sorted.length))] : 0);
const round = (n, d = 1) => Math.round(n * 10 ** d) / 10 ** d;

async function setup() {
  await resetDatabase();
  // Fresh products with a known shelf count and nothing reserved
  const products = await query(
    `INSERT INTO products (vendor_id, name, price, private_stock, buffer, reserved_quantity, public_stock, is_approved)
     SELECT $1, 'Bench item ' || g, $2, $3::int, $4::int, 0, $3::int - $4::int, true FROM generate_series(1, $5) g RETURNING id`,
    [VENDOR_ID, PRICE, STOCK, BUFFER, PRODUCTS]
  );
  await query(
    `INSERT INTO inventory_ledger (product_id, vendor_id, change_type, quantity_change, private_stock_after, public_stock_after, notes)
     SELECT id, vendor_id, 'stock_in', private_stock, private_stock, public_stock, 'Benchmark stock' FROM products WHERE id = ANY($1::int[])`,
    [products.rows.map((x) => x.id)]
  );
  // Buyers with money in their wallets (opening balances keep the books balanced)
  const r = await query(
    `INSERT INTO users (full_name, email, password_hash, role, wallet_balance)
     SELECT 'Bench Buyer ' || g, 'buyer' || g || '@bench.vendra.pk', 'x', 'customer', 100000
     FROM generate_series(1, $1) g RETURNING id`,
    [CUSTOMERS]
  );
  await query(
    `INSERT INTO wallet_ledger (user_id, transaction_type, amount, balance_after, description)
     SELECT id, 'opening_balance', 100000, 100000, 'Benchmark buyer' FROM users WHERE email LIKE '%@bench.vendra.pk'`
  );
  const sign = (payload) => jwt.sign(payload, process.env.JWT_SECRET, { expiresIn: '1h' });
  return {
    productIds: products.rows.map((x) => x.id),
    buyers: r.rows.map((u) => sign({ userId: u.id, role: 'customer' })),
    vendor: sign({ userId: VENDOR_USER_ID, role: 'vendor', vendorId: VENDOR_ID }),
  };
}

async function run(baseUrl, tokens) {
  const results = [];
  const send = (kind, url, method, body, token) => {
    const startedAt = performance.now();
    return fetch(`${baseUrl}${url}`, {
      method,
      headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${token}` },
      body: JSON.stringify(body),
    })
      .then(async (res) => {
        const json = await res.json().catch(() => ({}));
        results.push({ kind, at: startedAt, ms: performance.now() - startedAt, status: res.status, productId: body.items[0].productId, qty: body.items[0].quantity, id: json.data?.id });
      })
      .catch((err) => results.push({ kind, at: startedAt, ms: performance.now() - startedAt, status: 0, error: err.message }));
  };

  const t0 = performance.now();
  const end = t0 + DURATION_S * 1000;
  const inFlight = [];
  let sentCheckouts = 0;
  let sentPos = 0;
  let n = 0;
  // Dispatch loop: every few ms send whatever is due, so the rate holds however slow responses get
  await new Promise((resolve) => {
    const tick = setInterval(() => {
      const now = performance.now();
      const elapsed = (Math.min(now, end) - t0) / 1000;
      while (sentCheckouts < Math.floor(elapsed * RATE)) {
        const qty = 1 + (n++ % 3);
        inFlight.push(send('checkout', '/api/customer/checkout', 'POST',
          { items: [{ productId: tokens.productIds[sentCheckouts % PRODUCTS], quantity: qty }], deliveryType: 'self_pickup' },
          tokens.buyers[sentCheckouts % tokens.buyers.length]));
        sentCheckouts++;
      }
      while (sentPos < Math.floor(elapsed * POS_RATE)) {
        inFlight.push(send('pos', '/api/vendor/pos/sales', 'POST', { items: [{ productId: tokens.productIds[sentPos % PRODUCTS], quantity: 1 }] }, tokens.vendor));
        sentPos++;
      }
      if (now >= end) {
        clearInterval(tick);
        resolve();
      }
    }, 5);
  });
  await Promise.all(inFlight);
  return { results, wallSeconds: (performance.now() - t0) / 1000, t0 };
}

async function verify(results, productIds) {
  const ok = (kind, id) => results.filter((r) => r.kind === kind && r.status === 201 && (id == null || r.productId === id));
  const units = (rows) => rows.reduce((sum, r) => sum + r.qty, 0);
  const orders = (await query(`SELECT COUNT(*)::int AS n FROM orders WHERE customer_id IN (SELECT id FROM users WHERE email LIKE '%@bench.vendra.pk')`)).rows[0];
  const money = await moneyInvariant();

  // Every product must add up on its own
  const perProduct = [];
  for (const id of productIds) {
    const p = (await query('SELECT * FROM products WHERE id = $1', [id])).rows[0];
    const locks = (await query(`SELECT COALESCE(SUM(quantity), 0)::int AS q FROM inventory_locks WHERE product_id = $1 AND status = 'active'`, [id])).rows[0];
    const last = (await query('SELECT private_stock_after, public_stock_after FROM inventory_ledger WHERE product_id = $1 ORDER BY id DESC LIMIT 1', [id])).rows[0];
    const reserved = units(ok('checkout', id));
    const sold = units(ok('pos', id));
    perProduct.push({
      id,
      shelf: p.private_stock === STOCK - sold,
      reserved: p.reserved_quantity === reserved && p.reserved_quantity === locks.q,
      publicStock: p.public_stock === Math.max(0, p.private_stock - BUFFER - p.reserved_quantity),
      noOversell: reserved + sold <= STOCK,
      buffer: reserved <= STOCK - BUFFER,
      ledger: last.private_stock_after === p.private_stock && last.public_stock_after === p.public_stock,
      soldOut: p.public_stock === 0,
    });
  }
  const all = (key) => perProduct.every((x) => x[key]);
  const n = productIds.length;
  const each = n === 1 ? '' : ` (each of ${n} products)`;

  const checks = [
    [`Shelf stock = start − walk-in sales${each}`, all('shelf'), true],
    [`Reserved = units in successful orders = active locks${each}`, all('reserved'), true],
    ['Orders in the database = successful checkouts', orders.n, ok('checkout').length],
    [`Public stock = max(0, shelf − buffer − reserved)${each}`, all('publicStock'), true],
    [`Never oversold: reserved + sold ≤ start${each}`, all('noOversell'), true],
    [`Online sales never ate the walk-in buffer${each}`, all('buffer'), true],
    [`Ledger ends at the current shelf / public stock${each}`, all('ledger'), true],
    ['Money: wallets + escrow + platform = deposits', money.accounted.toFixed(2), money.deposits.toFixed(2)],
    ['Money: escrow pool = money held on open orders', money.pool.toFixed(2), money.held.toFixed(2)],
  ].map(([name, actual, expected]) => ({ name, actual, expected, pass: actual === expected }));
  return {
    checks,
    reservedByOrders: units(ok('checkout')),
    soldAtCounter: units(ok('pos')),
    soldOutProducts: perProduct.filter((x) => x.soldOut).length,
  };
}

function summarise(results, wallSeconds, t0) {
  const checkouts = results.filter((r) => r.kind === 'checkout');
  const lat = checkouts.map((r) => r.ms).sort((a, b) => a - b);
  const byStatus = {};
  for (const r of results) byStatus[`${r.kind} ${r.status}`] = (byStatus[`${r.kind} ${r.status}`] || 0) + 1;

  // Per-second series for the chart
  const seconds = Math.ceil(DURATION_S);
  const series = Array.from({ length: seconds }, (_, i) => ({ second: i + 1, sent: 0, ok: 0, soldOut: 0, p95: 0, lat: [] }));
  for (const r of checkouts) {
    const s = series[Math.min(seconds - 1, Math.floor((r.at - t0) / 1000))];
    s.sent++;
    if (r.status === 201) s.ok++;
    if (r.status === 409) s.soldOut++;
    s.lat.push(r.ms);
  }
  for (const s of series) {
    s.p95 = round(percentile(s.lat.sort((a, b) => a - b), 95));
    delete s.lat;
  }
  return {
    requests: results.length,
    checkouts: checkouts.length,
    achievedRate: round(checkouts.length / DURATION_S),
    wallSeconds: round(wallSeconds, 2),
    latencyMs: { p50: round(percentile(lat, 50)), p95: round(percentile(lat, 95)), p99: round(percentile(lat, 99)), max: round(lat.at(-1) || 0) },
    byStatus,
    errors: results.filter((r) => r.status >= 500 || r.status === 0).length,
    series,
  };
}

function htmlReport(report) {
  const { summary, checks, config } = report;
  const W = 760;
  const H = 260;
  const pad = 40;
  const n = summary.series.length;
  const maxCount = Math.max(1, ...summary.series.map((s) => s.sent));
  const maxP95 = Math.max(1, ...summary.series.map((s) => s.p95));
  const bw = (W - 2 * pad) / n;
  const y = (v, max) => H - pad - (v / max) * (H - 2 * pad);
  const bars = summary.series.map((s, i) => {
    const x = pad + i * bw + 2;
    const okH = (s.ok / maxCount) * (H - 2 * pad);
    const soH = (s.soldOut / maxCount) * (H - 2 * pad);
    return `<rect x="${x}" y="${H - pad - okH}" width="${bw - 4}" height="${okH}" fill="var(--ok)"><title>second ${s.second}: ${s.ok} placed</title></rect>`
      + `<rect x="${x}" y="${H - pad - okH - soH}" width="${bw - 4}" height="${soH}" fill="var(--sold)"><title>second ${s.second}: ${s.soldOut} sold out</title></rect>`;
  }).join('');
  const line = summary.series.map((s, i) => `${pad + i * bw + bw / 2},${y(s.p95, maxP95)}`).join(' ');
  const rows = checks.map((c) => `<tr><td>${c.pass ? '✅' : '❌'}</td><td>${c.name}</td><td>${c.actual}</td><td>${c.expected}</td></tr>`).join('');
  return `<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>Vendra PR 04 benchmark</title>
<style>
:root{--bg:#fff;--fg:#1d2433;--muted:#5b6475;--ok:#2e7d5b;--sold:#d08a2c;--line:#3157d5;--grid:#e3e6ec}
@media (prefers-color-scheme: dark){:root{--bg:#14171d;--fg:#e8ebf1;--muted:#9aa3b2;--ok:#4fb588;--sold:#e2a54f;--line:#7b9bff;--grid:#2a2f39}}
body{background:var(--bg);color:var(--fg);font:15px/1.5 system-ui,sans-serif;max-width:820px;margin:24px auto;padding:0 16px}
h1{font-size:22px;margin-bottom:4px}.muted{color:var(--muted)}table{border-collapse:collapse;width:100%;margin:12px 0}
td,th{border-bottom:1px solid var(--grid);padding:6px 8px;text-align:left}.kpis{display:flex;flex-wrap:wrap;gap:12px;margin:16px 0}
.kpi{border:1px solid var(--grid);border-radius:8px;padding:10px 14px;min-width:130px}.kpi b{display:block;font-size:20px}
svg{width:100%;height:auto}.legend span{margin-right:16px}.sw{display:inline-block;width:10px;height:10px;margin-right:6px}
</style></head><body>
<h1>PR 04 — concurrent inventory requests</h1>
<p class="muted">${config.rate} checkouts/s for ${config.duration} s on ${config.products === 1 ? 'one product' : `${config.products} products`} (${config.stock} units each, buffer ${config.buffer}), plus ${config.posRate} walk-in sales/s. ${report.ranAt}</p>
<div class="kpis">
<div class="kpi">Achieved rate<b>${summary.achievedRate}/s</b></div>
<div class="kpi">Latency p50 / p95<b>${summary.latencyMs.p50} / ${summary.latencyMs.p95} ms</b></div>
<div class="kpi">Orders placed<b>${summary.byStatus['checkout 201'] || 0}</b></div>
<div class="kpi">Refused, sold out<b>${summary.byStatus['checkout 409'] || 0}</b></div>
<div class="kpi">Server errors<b>${summary.errors}</b></div>
<div class="kpi">Integrity checks<b>${checks.filter((c) => c.pass).length}/${checks.length} pass</b></div>
</div>
<svg viewBox="0 0 ${W} ${H}" role="img" aria-label="Checkouts per second and p95 latency">
<line x1="${pad}" y1="${H - pad}" x2="${W - pad}" y2="${H - pad}" stroke="var(--grid)"/>
${bars}
<polyline points="${line}" fill="none" stroke="var(--line)" stroke-width="2"/>
<text x="${pad}" y="${pad - 12}" fill="var(--muted)" font-size="12">checkouts per second (max ${maxCount})</text>
<text x="${W - pad}" y="${pad - 12}" fill="var(--line)" font-size="12" text-anchor="end">p95 latency (max ${maxP95} ms)</text>
<text x="${W / 2}" y="${H - 10}" fill="var(--muted)" font-size="12" text-anchor="middle">seconds into the run</text>
</svg>
<p class="legend"><span><i class="sw" style="background:var(--ok)"></i>order placed (stock reserved)</span><span><i class="sw" style="background:var(--sold)"></i>refused: sold out (409)</span><span><i class="sw" style="background:var(--line)"></i>p95 latency</span></p>
<h2>Integrity after the run</h2>
<table><tr><th></th><th>Check</th><th>Actual</th><th>Expected</th></tr>${rows}</table>
</body></html>`;
}

async function main() {
  console.log(`PR 04 benchmark: ${RATE} checkouts/s for ${DURATION_S}s on ${PRODUCTS} product(s) × ${STOCK} units (+${POS_RATE} walk-in sales/s)`);
  const tokens = await setup();
  const srv = await startServer();
  try {
    const { results, wallSeconds, t0 } = await run(srv.baseUrl, tokens);
    const summary = summarise(results, wallSeconds, t0);
    const { checks, reservedByOrders, soldAtCounter, soldOutProducts } = await verify(results, tokens.productIds);
    const report = {
      ranAt: new Date().toISOString(),
      config: { rate: RATE, duration: DURATION_S, stock: STOCK, buffer: BUFFER, posRate: POS_RATE, customers: CUSTOMERS, products: PRODUCTS },
      summary,
      reservedByOrders,
      soldAtCounter,
      soldOutProducts,
      checks,
    };

    console.log(`\n  Sent ${summary.checkouts} checkouts in ${DURATION_S}s → ${summary.achievedRate}/s (all answered after ${summary.wallSeconds}s)`);
    console.log(`  Latency  p50 ${summary.latencyMs.p50} ms · p95 ${summary.latencyMs.p95} ms · p99 ${summary.latencyMs.p99} ms · max ${summary.latencyMs.max} ms`);
    console.log(`  Results  ${Object.entries(summary.byStatus).map(([k, v]) => `${k}: ${v}`).join(' · ')}`);
    console.log(`  Units    ${reservedByOrders} reserved online + ${soldAtCounter} sold at the counter of ${STOCK * PRODUCTS} (buffer ${BUFFER} each); ${soldOutProducts}/${PRODUCTS} product(s) sold out\n`);
    for (const c of checks) console.log(`  ${c.pass ? '✓' : '✗'} ${c.name}${c.pass ? '' : ` — got ${c.actual}, expected ${c.expected}`}`);

    const dir = path.join(__dirname, 'results');
    fs.mkdirSync(dir, { recursive: true });
    const stamp = report.ranAt.replace(/[:.]/g, '-');
    fs.writeFileSync(path.join(dir, `concurrency-${stamp}.json`), JSON.stringify(report, null, 2));
    fs.writeFileSync(path.join(dir, `concurrency-${stamp}.html`), htmlReport(report));
    console.log(`\n  Report: bench/results/concurrency-${stamp}.html`);
    process.exitCode = checks.every((c) => c.pass) && summary.errors === 0 ? 0 : 1;
  } finally {
    await srv.stop();
  }
}

main().catch((err) => {
  console.error('✗ Benchmark failed:', err);
  process.exit(1);
});
