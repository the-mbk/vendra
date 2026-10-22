"use client";

import { useState, useEffect } from "react";
import { useRouter } from "next/navigation";
import { getFinance, getReconciliation, isAuthError } from "../../lib/api";
import { usePublicConfig } from "../../lib/hooks";
import { PageLoader, ErrorBox, Spinner, Th, formatRs, formatDate, formatOrderId, humanize } from "../../lib/ui";

const entryConfig = {
  commission: { label: "Commission", color: "bg-blue-100 text-blue-700", icon: "percent" },
  delivery_margin: { label: "Delivery margin", color: "bg-orange-100 text-orange-700", icon: "local_shipping" },
};

function StatCard({ title, value, subtitle, icon, iconClass, onClick }) {
  const Tag = onClick ? "button" : "div";
  return (
    <Tag
      onClick={onClick}
      className={`bg-white rounded-2xl p-6 border border-outline-variant/20 shadow-sm text-left w-full flex flex-col justify-start ${
        onClick ? "hover:shadow-md transition-shadow" : ""
      }`}
    >
      <div className={`w-12 h-12 rounded-xl flex items-center justify-center mb-4 ${iconClass}`}>
        <span className="material-symbols-outlined text-[24px]">{icon}</span>
      </div>
      <p className="text-2xl font-bold text-on-surface mb-1">{value}</p>
      <p className="text-sm text-on-surface-variant">{title}</p>
      {subtitle && <p className="text-xs text-outline mt-1">{subtitle}</p>}
    </Tag>
  );
}

/** Rupee sums without floating-point drift (amounts have at most 2 decimals) */
function sumRs(...values) {
  return Math.round(values.reduce((s, v) => s + (Number(v) || 0) * 100, 0)) / 100;
}

/** One labelled amount in a reconciliation column */
function ReconRow({ label, hint, value, sign, strong, muted }) {
  return (
    <div className={`flex items-start justify-between gap-3 py-2 ${strong ? "border-t border-outline-variant/30 mt-1 pt-3" : ""}`}>
      <div className="min-w-0">
        <p className={`text-sm ${strong ? "font-bold text-on-surface" : "font-medium text-on-surface"}`}>{label}</p>
        {hint && <p className="text-[11px] text-outline leading-snug mt-0.5">{hint}</p>}
      </div>
      <p
        className={`text-sm whitespace-nowrap tabular-nums ${
          strong ? "font-bold text-on-surface" : muted ? "text-outline" : "font-semibold text-on-surface"
        }`}
      >
        {sign}
        {formatRs(value)}
      </p>
    </div>
  );
}

function ReconColumn({ icon, title, subtitle, children }) {
  return (
    <div className="bg-surface-container-low/40 rounded-xl p-4 border border-outline-variant/20">
      <div className="flex items-center gap-2 mb-1">
        <span className="material-symbols-outlined text-primary text-[20px]">{icon}</span>
        <h4 className="text-xs font-semibold text-on-surface-variant uppercase tracking-wider">{title}</h4>
      </div>
      {subtitle && <p className="text-xs text-outline mb-2">{subtitle}</p>}
      {children}
    </div>
  );
}

function ReconStatus({ recon }) {
  if (!recon.gateway?.reachable) {
    return (
      <div className="flex items-center gap-3 rounded-xl px-4 py-3 bg-amber-50 border border-amber-200">
        <span className="material-symbols-outlined text-amber-700 text-[28px]">cloud_off</span>
        <div>
          <p className="text-lg font-bold text-amber-800 leading-tight">Payment gateway unreachable</p>
          <p className="text-xs text-amber-700 mt-0.5">
            Vendra Pay didn&apos;t answer, so its balance can&apos;t be checked right now. The books expect it to hold{" "}
            <span className="font-semibold">{formatRs(recon.expectedGatewayBalance)}</span>.
          </p>
        </div>
      </div>
    );
  }
  if (recon.balanced) {
    return (
      <div className="flex items-center gap-3 rounded-xl px-4 py-3 bg-emerald-50 border border-emerald-200">
        <span className="material-symbols-outlined text-emerald-600 text-[32px]">verified</span>
        <div>
          <p className="text-2xl font-bold text-emerald-700 leading-tight">Balanced ✓</p>
          <p className="text-xs text-emerald-700 mt-0.5">
            The gateway holds exactly {formatRs(recon.gateway.available)}, the amount the books say it should.
          </p>
        </div>
      </div>
    );
  }
  const diff = Number(recon.difference) || 0;
  return (
    <div className="flex items-center gap-3 rounded-xl px-4 py-3 bg-red-50 border border-red-200">
      <span className="material-symbols-outlined text-error text-[32px]">error</span>
      <div>
        <p className="text-2xl font-bold text-error leading-tight">Off by {formatRs(Math.abs(diff))}</p>
        <p className="text-xs text-red-700 mt-0.5">
          The gateway holds {formatRs(Math.abs(diff))} {diff > 0 ? "more" : "less"} than the books say it should.
          Check recent payments and withdrawals for anything stuck.
        </p>
      </div>
    </div>
  );
}

function ReconciliationPanel({ gatewayUrl }) {
  const router = useRouter();
  const [state, setState] = useState(null); // { data, error, at }
  const [refreshing, setRefreshing] = useState(false);

  useEffect(() => {
    let cancelled = false;
    getReconciliation()
      .then((res) => { if (!cancelled) setState({ data: res.data, error: null, at: new Date() }); })
      .catch((err) => {
        if (isAuthError(err)) router.push("/");
        if (!cancelled) setState({ data: null, error: err.message, at: new Date() });
      });
    return () => { cancelled = true; };
  }, [router]);

  async function handleRefresh() {
    setRefreshing(true);
    try {
      const res = await getReconciliation();
      setState({ data: res.data, error: null, at: new Date() });
    } catch (err) {
      if (isAuthError(err)) router.push("/");
      setState((prev) => ({ data: prev?.data ?? null, error: err.message, at: new Date() }));
    } finally {
      setRefreshing(false);
    }
  }

  const recon = state?.data;
  const books = recon?.books || {};
  const opening = recon?.openingBalances || {};
  const booksTotal = sumRs(books.wallets, books.escrow, books.platformRevenue, books.pendingWithdrawals, books.uncreditedPayments);
  const reachable = recon?.gateway?.reachable;

  return (
    <div className="bg-white rounded-2xl p-6 border border-outline-variant/20 shadow-sm mb-5">
      {/* Title row */}
      <div className="flex flex-col md:flex-row md:items-start md:justify-between gap-3 mb-5">
        <div>
          <div className="flex items-center gap-2">
            <span className="material-symbols-outlined text-primary text-[22px]">balance</span>
            <h3 className="text-lg font-bold text-on-surface">Gateway reconciliation</h3>
          </div>
          <p className="text-sm text-on-surface-variant mt-1">
            Does the money held at the payment gateway (Vendra Pay) match what Vendra&apos;s books say it should be?
          </p>
          {state?.at && <p className="text-[11px] text-outline mt-1">Checked {formatDate(state.at, true)}</p>}
        </div>
        <div className="flex items-center gap-2 shrink-0">
          {gatewayUrl && (
            <a
              href={gatewayUrl}
              target="_blank"
              rel="noopener noreferrer"
              className="flex items-center gap-1.5 px-3 py-2 rounded-xl text-sm font-semibold text-primary bg-primary/5 hover:bg-primary/10 transition-colors"
            >
              <span className="material-symbols-outlined text-[18px]">open_in_new</span>
              Open Vendra Pay dashboard
            </a>
          )}
          <button
            onClick={handleRefresh}
            disabled={refreshing || !state}
            className="flex items-center gap-1.5 px-3 py-2 rounded-xl text-sm font-semibold text-on-surface-variant bg-surface-container-low hover:bg-surface-container transition-colors disabled:opacity-50"
          >
            <span className={`material-symbols-outlined text-[18px] ${refreshing ? "animate-spin" : ""}`}>refresh</span>
            Re-check
          </button>
        </div>
      </div>

      {!state ? (
        <div className="flex items-center justify-center gap-3 py-10 text-sm text-outline">
          <Spinner className="w-6 h-6" /> Checking the gateway balance...
        </div>
      ) : !recon ? (
        <ErrorBox title="Couldn't load the reconciliation" message={state.error} />
      ) : (
        <>
          {state.error && (
            <p className="text-xs text-error mb-3">Last re-check failed ({state.error}); showing the previous result.</p>
          )}

          <ReconStatus recon={recon} />

          <div className="grid grid-cols-1 lg:grid-cols-3 gap-4 mt-5">
            {/* Gateway side */}
            <ReconColumn icon="account_balance" title="At Vendra Pay" subtitle="What the gateway reports for Vendra's account">
              {reachable ? (
                <>
                  <div className="py-2">
                    <p className="text-sm font-medium text-on-surface">Available balance</p>
                    <p className="text-3xl font-bold text-on-surface tabular-nums mt-1">{formatRs(recon.gateway.available)}</p>
                    <p className="text-[11px] text-outline mt-0.5">Card payments + platform top-ups − payouts sent</p>
                  </div>
                  <ReconRow
                    label="In-transit payouts"
                    hint="Withdrawals on their way to cards. Already taken out of the available balance."
                    value={recon.gateway.inTransit}
                    muted
                  />
                </>
              ) : (
                <div className="py-6 text-center">
                  <span className="material-symbols-outlined text-[36px] text-outline-variant">cloud_off</span>
                  <p className="text-sm text-on-surface-variant mt-1">Payment gateway unreachable</p>
                  <p className="text-[11px] text-outline mt-0.5">Is Vendra Pay running? Try Re-check in a moment.</p>
                </div>
              )}
            </ReconColumn>

            {/* Books side */}
            <ReconColumn icon="menu_book" title="In the books" subtitle="Money Vendra owes its users or has earned">
              <div className="divide-y divide-outline-variant/10">
                <ReconRow label="Wallets" hint="Customer, vendor and rider balances" value={books.wallets} />
                <ReconRow label="Escrow" hint="Held for orders not yet released" value={books.escrow} />
                <ReconRow label="Platform revenue" hint="Commission + delivery margin earned" value={books.platformRevenue} />
                <ReconRow
                  label="Pending withdrawals"
                  hint="Taken from wallets, not yet sent to the gateway"
                  value={books.pendingWithdrawals}
                  muted={!Number(books.pendingWithdrawals)}
                />
                <ReconRow
                  label="Uncredited payments"
                  hint="Charged at the gateway, not yet in a wallet"
                  value={books.uncreditedPayments}
                  muted={!Number(books.uncreditedPayments)}
                />
              </div>
              <ReconRow label="Total in the books" value={booksTotal} strong />
            </ReconColumn>

            {/* Opening balances */}
            <ReconColumn icon="history" title="Opening balances" subtitle="Money from before the gateway (demo data)">
              <p className="text-[11px] text-on-surface-variant leading-snug mb-1">
                Seeded wallet balances never came in through a card, so the gateway has no payment behind them.
                The platform tops up its gateway balance to back them; any part not backed yet is left out of the
                expected balance.
              </p>
              <div className="divide-y divide-outline-variant/10">
                <ReconRow label="Total" hint="Opening balances in the wallet ledger" value={opening.total} />
                <ReconRow label="Funded" hint="Backed by a platform top-up at the gateway" value={opening.funded} />
                <ReconRow
                  label="Unfunded"
                  hint="Not at the gateway, so subtracted below"
                  value={opening.unfunded}
                  muted={!Number(opening.unfunded)}
                />
              </div>
            </ReconColumn>
          </div>

          {/* Expected vs actual */}
          <div className="mt-4 rounded-xl border border-outline-variant/30 px-5 py-4 flex flex-col lg:flex-row lg:items-center gap-4 lg:gap-6">
            <div className="flex-1 flex flex-wrap items-center gap-x-3 gap-y-1 text-sm">
              <span className="text-on-surface-variant">Books</span>
              <span className="font-semibold tabular-nums">{formatRs(booksTotal)}</span>
              <span className="text-outline">−</span>
              <span className="text-on-surface-variant">unfunded opening</span>
              <span className="font-semibold tabular-nums">{formatRs(opening.unfunded)}</span>
              <span className="text-outline">=</span>
              <span className="text-on-surface-variant">expected</span>
              <span className="font-bold text-on-surface tabular-nums">{formatRs(recon.expectedGatewayBalance)}</span>
            </div>
            <div className="flex items-center gap-6 shrink-0">
              <div>
                <p className="text-[11px] font-semibold text-outline uppercase tracking-wider">Expected</p>
                <p className="text-lg font-bold text-on-surface tabular-nums">{formatRs(recon.expectedGatewayBalance)}</p>
              </div>
              <div>
                <p className="text-[11px] font-semibold text-outline uppercase tracking-wider">Actual</p>
                <p className="text-lg font-bold text-on-surface tabular-nums">
                  {reachable ? formatRs(recon.gateway.available) : "—"}
                </p>
              </div>
              <div>
                <p className="text-[11px] font-semibold text-outline uppercase tracking-wider">Difference</p>
                <p
                  className={`text-lg font-bold tabular-nums ${
                    !reachable ? "text-outline" : recon.balanced ? "text-emerald-700" : "text-error"
                  }`}
                >
                  {!reachable ? "—" : `${Number(recon.difference) > 0 ? "+" : Number(recon.difference) < 0 ? "−" : ""}${formatRs(Math.abs(Number(recon.difference) || 0))}`}
                </p>
              </div>
            </div>
          </div>

          <div className="flex flex-wrap gap-4 mt-4 text-sm">
            <button onClick={() => router.push("/dashboard/payments")} className="font-semibold text-primary hover:underline">
              View card payments →
            </button>
            <button onClick={() => router.push("/dashboard/withdrawals")} className="font-semibold text-primary hover:underline">
              View withdrawals →
            </button>
          </div>
        </>
      )}
    </div>
  );
}

export default function FinancePage() {
  const [finance, setFinance] = useState(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(null);
  const router = useRouter();
  const publicConfig = usePublicConfig();

  useEffect(() => {
    const token = localStorage.getItem("vendra_admin_token");
    if (!token) { router.push("/"); return; }

    async function fetchFinance() {
      try {
        const res = await getFinance();
        setFinance(res.data);
      } catch (err) {
        if (isAuthError(err)) router.push("/");
        setError(err.message);
      } finally {
        setLoading(false);
      }
    }
    fetchFinance();
  }, [router]);

  if (loading) return <PageLoader label="Loading finance..." />;
  if (error) return <ErrorBox title="Error loading finance" message={error} />;

  const held = finance.held || { orders: 0, amount: 0 };
  const disputed = finance.disputed || { orders: 0, amount: 0 };
  const commission = Number(finance.commission) || 0;
  const deliveryMargin = Number(finance.deliveryMargin) || 0;
  const revenue = Number(finance.platformRevenue) || 0;
  const recent = finance.recent || [];

  const owed = Number(held.amount) + Number(disputed.amount);
  const gap = Number(finance.escrowPool) - owed;
  const reconciled = Math.abs(gap) < 0.01;

  // Share of each revenue source for the split bar (only positive parts are drawn)
  const splitTotal = Math.max(commission, 0) + Math.max(deliveryMargin, 0);
  const commissionShare = splitTotal > 0 ? (Math.max(commission, 0) / splitTotal) * 100 : 0;
  const marginShare = splitTotal > 0 ? 100 - commissionShare : 0;

  return (
    <div>
      {/* Header */}
      <div className="flex items-center justify-between mb-6">
        <div>
          <h1 className="text-2xl font-bold text-on-surface">Finance & Escrow</h1>
          <p className="text-on-surface-variant text-sm mt-1">
            Customer payments are held in escrow until delivery and the dispute window pass.
          </p>
        </div>
      </div>

      {/* Gateway reconciliation */}
      <ReconciliationPanel gatewayUrl={publicConfig?.payments?.gatewayUrl} />

      {/* Escrow Cards */}
      <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-5 mb-5">
        <StatCard
          title="Escrow Pool Balance"
          value={formatRs(finance.escrowPool)}
          subtitle={
            reconciled
              ? "Matches held + disputed orders ✓"
              : `Held + disputed orders: ${formatRs(owed)}`
          }
          icon="account_balance"
          iconClass="bg-primary/10 text-primary"
        />
        <StatCard
          title="Held (awaiting release)"
          value={formatRs(held.amount)}
          subtitle={`${held.orders} order${held.orders === 1 ? "" : "s"}`}
          icon="hourglass_top"
          iconClass="bg-amber-100 text-amber-700"
          onClick={() => router.push("/dashboard/orders")}
        />
        <StatCard
          title="Frozen by disputes"
          value={formatRs(disputed.amount)}
          subtitle={`${disputed.orders} order${disputed.orders === 1 ? "" : "s"} under review`}
          icon="gavel"
          iconClass="bg-red-100 text-red-700"
          onClick={() => router.push("/dashboard/disputes")}
        />
        <StatCard
          title="Total Rider Payouts"
          value={formatRs(finance.riderPayouts)}
          subtitle="Paid from escrow at each delivery"
          icon="two_wheeler"
          iconClass="bg-cyan-100 text-cyan-700"
          onClick={() => router.push("/dashboard/riders")}
        />
      </div>

      {/* Revenue split */}
      <div className="bg-white rounded-2xl p-6 border border-outline-variant/20 shadow-sm mb-5">
        <div className="flex flex-col md:flex-row md:items-end md:justify-between gap-4 mb-5">
          <div>
            <p className="text-sm text-on-surface-variant">Platform revenue</p>
            <p className="text-3xl font-bold text-on-surface">{formatRs(revenue)}</p>
            <p className="text-xs text-outline mt-1">
              Commission on released orders + delivery fee kept after paying the rider
            </p>
          </div>
          <div className="flex gap-6">
            <div>
              <div className="flex items-center gap-2">
                <span className="w-2.5 h-2.5 rounded-full bg-primary" />
                <span className="text-xs font-semibold text-on-surface-variant uppercase">Commission</span>
              </div>
              <p className="text-lg font-bold text-on-surface mt-0.5">{formatRs(commission)}</p>
            </div>
            <div>
              <div className="flex items-center gap-2">
                <span className="w-2.5 h-2.5 rounded-full bg-secondary-container" />
                <span className="text-xs font-semibold text-on-surface-variant uppercase">Delivery margin</span>
              </div>
              <p className={`text-lg font-bold mt-0.5 ${deliveryMargin < 0 ? "text-error" : "text-on-surface"}`}>
                {formatRs(deliveryMargin)}
              </p>
            </div>
          </div>
        </div>
        <div className="h-3 rounded-full bg-surface-container-low overflow-hidden flex gap-0.5">
          {commissionShare > 0 && <div className="bg-primary h-full" style={{ width: `${commissionShare}%` }} />}
          {marginShare > 0 && <div className="bg-secondary-container h-full" style={{ width: `${marginShare}%` }} />}
        </div>
        {deliveryMargin < 0 && (
          <p className="text-xs text-error mt-2">
            Rider payouts are exceeding the delivery fees collected. Consider reviewing the delivery fee or rider rates in Policies.
          </p>
        )}
      </div>

      {/* Ledger */}
      <div className="bg-white rounded-2xl border border-outline-variant/20 shadow-sm overflow-hidden">
        <div className="px-5 py-4 border-b border-outline-variant/20 flex items-center justify-between">
          <h3 className="text-lg font-bold text-on-surface">Recent platform ledger</h3>
          <span className="text-xs text-outline">{recent.length} most recent entr{recent.length === 1 ? "y" : "ies"}</span>
        </div>
        <div className="overflow-x-auto">
          <table className="w-full">
            <thead>
              <tr className="bg-surface-container-low/50 border-b border-outline-variant/20">
                <Th>Date</Th>
                <Th>Order</Th>
                <Th>Store</Th>
                <Th>Type</Th>
                <Th align="right">Amount</Th>
              </tr>
            </thead>
            <tbody className="divide-y divide-outline-variant/10">
              {recent.map((entry) => {
                const config = entryConfig[entry.type] || {
                  label: humanize(entry.type),
                  color: "bg-surface-container-low text-on-surface-variant",
                  icon: "receipt",
                };
                return (
                  <tr key={entry.id} className="hover:bg-surface-container-low/30 transition-colors">
                    <td className="px-4 py-3.5 text-xs text-outline whitespace-nowrap">{formatDate(entry.createdAt, true)}</td>
                    <td className="px-4 py-3.5 text-sm font-bold text-primary whitespace-nowrap">{formatOrderId(entry.orderId)}</td>
                    <td className="px-4 py-3.5 text-sm text-on-surface">{entry.storeName}</td>
                    <td className="px-4 py-3.5">
                      <span className={`inline-flex items-center gap-1 px-2.5 py-1 rounded-full text-xs font-semibold whitespace-nowrap ${config.color}`}>
                        <span className="material-symbols-outlined text-[14px]">{config.icon}</span>
                        {config.label}
                      </span>
                    </td>
                    <td
                      className={`px-4 py-3.5 text-sm font-semibold text-right whitespace-nowrap ${
                        entry.amount < 0 ? "text-error" : "text-emerald-700"
                      }`}
                    >
                      {entry.amount < 0 ? "−" : "+"}
                      {formatRs(Math.abs(entry.amount))}
                    </td>
                  </tr>
                );
              })}

              {recent.length === 0 && (
                <tr>
                  <td colSpan={5} className="text-center py-12 text-on-surface-variant">
                    <span className="material-symbols-outlined text-[48px] text-outline-variant block mb-2">receipt_long</span>
                    No platform revenue recorded yet. Entries are recorded when an order&apos;s escrow is released to the store.
                  </td>
                </tr>
              )}
            </tbody>
          </table>
        </div>
      </div>
    </div>
  );
}
