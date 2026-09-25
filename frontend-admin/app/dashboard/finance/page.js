"use client";

import { useState, useEffect } from "react";
import { useRouter } from "next/navigation";
import { getFinance, isAuthError } from "../../lib/api";
import { PageLoader, ErrorBox, Th, formatRs, formatDate, formatOrderId, humanize } from "../../lib/ui";

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

export default function FinancePage() {
  const [finance, setFinance] = useState(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(null);
  const router = useRouter();

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
                    <td className="px-5 py-4 text-xs text-outline whitespace-nowrap">{formatDate(entry.createdAt, true)}</td>
                    <td className="px-5 py-4 text-sm font-bold text-primary whitespace-nowrap">{formatOrderId(entry.orderId)}</td>
                    <td className="px-5 py-4 text-sm text-on-surface">{entry.storeName}</td>
                    <td className="px-5 py-4">
                      <span className={`inline-flex items-center gap-1 px-2.5 py-1 rounded-full text-xs font-semibold whitespace-nowrap ${config.color}`}>
                        <span className="material-symbols-outlined text-[14px]">{config.icon}</span>
                        {config.label}
                      </span>
                    </td>
                    <td
                      className={`px-5 py-4 text-sm font-semibold text-right whitespace-nowrap ${
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
