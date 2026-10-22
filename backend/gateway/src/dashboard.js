// Merchant dashboard: what the payment processor sees (balance, payments, payouts, webhooks)

const esc = (s) => String(s ?? '').replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[c]);
const rs = (paisa) => `Rs ${(paisa / 100).toLocaleString('en-PK', { minimumFractionDigits: 2, maximumFractionDigits: 2 })}`;
const when = (sec) => (sec ? new Date(sec * 1000).toLocaleString('en-PK', { timeZone: 'Asia/Karachi' }) : '—');
const card = (c) => (c?.last4 ? `${esc(c.brand)} •••• ${esc(c.last4)}` : '—');
const pill = (status) => `<span class="pill ${esc(status)}">${esc(status.replace(/_/g, ' '))}</span>`;
const desc = (o) => esc(o.description || '') + (o.metadata?.vendra_ref ? ` <span class="muted">${esc(o.metadata.vendra_ref)}</span>` : '');

function table(head, rows, empty) {
  if (!rows.length) return `<p class="muted">${empty}</p>`;
  return `<div class="scroll"><table><thead><tr>${head.map((h) => `<th>${h}</th>`).join('')}</tr></thead><tbody>${rows.join('')}</tbody></table></div>`;
}

function renderDashboard(d) {
  const intents = d.intents.map((i) => `<tr><td class="mono">${esc(i.id)}</td><td class="num">${rs(i.amount)}</td><td>${pill(i.status)}</td>
    <td>${card(i.card)}</td><td>${desc(i)}${i.last_payment_error ? `<div class="err">${esc(i.last_payment_error.message)}</div>` : ''}</td><td>${when(i.created)}</td></tr>`);
  const payouts = d.payouts.map((p) => `<tr><td class="mono">${esc(p.id)}</td><td class="num">${rs(p.amount)}</td><td>${pill(p.status)}</td>
    <td>${card(p.destination)}</td><td>${desc(p)}${p.failure_message ? `<div class="err">${esc(p.failure_message)}</div>` : ''}</td><td>${when(p.status === 'in_transit' ? p.arrival_date : p.created)}</td></tr>`);
  const events = d.events.map((e) => `<tr><td class="mono">${esc(e.id)}</td><td>${esc(e.type)}</td><td class="mono">${esc(e.object_id)}</td>
    <td>${e.delivered_at ? pill('delivered') : e.attempts ? `${pill('retrying')} <span class="err">${esc(e.last_error || '')}</span>` : pill('pending')}</td>
    <td class="num">${e.attempts}</td><td>${when(e.created)}</td></tr>`);
  const cards = d.testCards.map((c) => `<tr><td class="mono">${esc(c.number.replace(/(\d{4})(?=\d)/g, '$1 '))}</td><td>${esc(c.brand)} ${esc(c.funding)}</td><td>${esc(c.label)}</td></tr>`);

  return `<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<meta http-equiv="refresh" content="5"><title>Vendra Pay · Sandbox dashboard</title>
<style>
:root{--bg:#f5f6f8;--card:#fff;--ink:#16181d;--muted:#667085;--line:#e3e6eb;--brand:#5b3fd6;--ok:#127a43;--okbg:#e2f5ea;--warn:#8a5a00;--warnbg:#fdf1d6;--bad:#b42318;--badbg:#fde7e5}
@media (prefers-color-scheme:dark){:root{--bg:#0f1115;--card:#171a21;--ink:#e7e9ee;--muted:#98a1b2;--line:#2a2f3a;--brand:#a594ff;--ok:#5fd18f;--okbg:#123222;--warn:#f0b955;--warnbg:#3a2b0d;--bad:#ff8f84;--badbg:#3d1714}}
*{box-sizing:border-box}body{margin:0;background:var(--bg);color:var(--ink);font:14px/1.5 system-ui,-apple-system,"Segoe UI",sans-serif;padding:24px 16px 48px}
.wrap{max-width:1100px;margin:0 auto;display:flex;flex-direction:column;gap:22px}
header{display:flex;flex-wrap:wrap;align-items:baseline;gap:8px 14px}h1{margin:0;font-size:22px}h1 b{color:var(--brand)}
.badge{background:var(--warnbg);color:var(--warn);font-weight:700;font-size:12px;padding:2px 8px;border-radius:99px;letter-spacing:.04em}
.tiles{display:grid;grid-template-columns:repeat(auto-fit,minmax(200px,1fr));gap:12px}
.tile{background:var(--card);border:1px solid var(--line);border-radius:10px;padding:14px 16px}.tile span{color:var(--muted);font-size:12px;text-transform:uppercase;letter-spacing:.06em;font-weight:600}
.tile b{display:block;font-size:22px;font-variant-numeric:tabular-nums;margin-top:2px}
section{background:var(--card);border:1px solid var(--line);border-radius:10px;padding:16px}h2{margin:0 0 10px;font-size:15px}
.scroll{overflow-x:auto}table{border-collapse:collapse;width:100%;min-width:640px}th,td{text-align:left;padding:7px 10px;border-bottom:1px solid var(--line);vertical-align:top}
th{font-size:11px;text-transform:uppercase;letter-spacing:.06em;color:var(--muted)}tr:last-child td{border-bottom:0}
.mono{font-family:ui-monospace,Consolas,monospace;font-size:12px}.num{font-variant-numeric:tabular-nums;white-space:nowrap}.muted{color:var(--muted)}.err{color:var(--bad);font-size:12px}
.pill{display:inline-block;font-size:11px;font-weight:700;padding:1px 8px;border-radius:99px;background:var(--line);white-space:nowrap}
.pill.succeeded,.pill.paid,.pill.delivered{background:var(--okbg);color:var(--ok)}.pill.requires_action,.pill.in_transit,.pill.retrying,.pill.pending{background:var(--warnbg);color:var(--warn)}
.pill.failed,.pill.canceled{background:var(--badbg);color:var(--bad)}
</style></head><body><div class="wrap">
<header><h1><b>Vendra Pay</b> merchant dashboard</h1><span class="badge">SANDBOX</span><span class="muted">Refreshes every 5 s · webhooks → ${esc(d.webhookUrl || 'not configured')}</span></header>
<div class="tiles">
  <div class="tile"><span>Available balance</span><b>${rs(d.balance.available)}</b></div>
  <div class="tile"><span>Payouts in transit</span><b>${rs(d.balance.in_transit)}</b></div>
  <div class="tile"><span>Payments shown</span><b>${d.intents.length}</b></div>
</div>
<section><h2>Payments</h2>${table(['ID', 'Amount', 'Status', 'Card', 'Description', 'Created'], intents, 'No payments yet.')}</section>
<section><h2>Payouts</h2>${table(['ID', 'Amount', 'Status', 'Destination', 'Description', 'Arrives / created'], payouts, 'No payouts yet.')}</section>
<section><h2>Webhook events</h2>${table(['Event', 'Type', 'Object', 'Delivery', 'Attempts', 'Created'], events, 'No events yet.')}</section>
<section><h2>Test cards</h2><p class="muted">Any future expiry date and any 3-digit CVC. One-time password: <b class="mono">${esc(d.otp)}</b></p>
${table(['Number', 'Type', 'Behaviour'], cards, '')}</section>
</div></body></html>`;
}

module.exports = { renderDashboard };
