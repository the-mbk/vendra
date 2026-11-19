// ══════════════════════════════════════════════════════════════
// Money helpers — all calculations in integer paisa (1/100 Rs)
// so splits and payouts are exact to 0.01 (SRDS PR 06).
// ══════════════════════════════════════════════════════════════

/** Rupees (number or numeric string from Postgres) → integer paisa */
function toPaisa(value) {
  return Math.round(Number(value) * 100);
}

/** Integer paisa → numeric string with 2 decimals, safe to pass to Postgres */
function paisaToString(paisa) {
  const sign = paisa < 0 ? '-' : '';
  const abs = Math.abs(paisa);
  return `${sign}${Math.floor(abs / 100)}.${String(abs % 100).padStart(2, '0')}`;
}

/** Integer paisa → JS number of rupees, for JSON responses */
function paisaToNumber(paisa) {
  return paisa / 100;
}

/** Percentage of an amount in paisa, rounded to the nearest paisa */
function percentOf(paisa, pct) {
  return Math.round((paisa * Number(pct)) / 100);
}

/** Integer paisa → "Rs. 6,999" (paisa shown only when there are any), for ledger text */
function formatRs(paisa) {
  const rupees = paisa / 100;
  return `Rs. ${rupees.toLocaleString('en-US', { minimumFractionDigits: paisa % 100 ? 2 : 0, maximumFractionDigits: 2 })}`;
}

/** "items Rs. 6,999 − 10% commission Rs. 700 = Rs. 6,299": how a store payout was worked out */
function commissionBreakdown(grossPaisa, pct, commissionPaisa) {
  return `items ${formatRs(grossPaisa)} − ${Number(pct)}% commission ${formatRs(commissionPaisa)} = ${formatRs(grossPaisa - commissionPaisa)}`;
}

module.exports = { toPaisa, paisaToString, paisaToNumber, percentOf, formatRs, commissionBreakdown };
