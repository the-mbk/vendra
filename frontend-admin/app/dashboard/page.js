"use client";

import { useState, useEffect } from "react";
import { useRouter } from "next/navigation";
import { getDashboardStats, isAuthError } from "../lib/api";
import { ErrorBox, formatRs, formatNumber, formatDate, formatOrderId, humanize, roleColors } from "../lib/ui";
import { CHANNELS, ChannelSwatch, ChannelSplitBar, ChannelSeriesChart } from "../lib/channels";

function KPICard({ title, value, subtitle, icon, color, trend, href, alert }) {
  const router = useRouter();
  const colorClasses = {
    primary: "bg-primary/10 text-primary",
    secondary: "bg-orange-100 text-secondary",
    success: "bg-emerald-100 text-emerald-700",
    info: "bg-blue-100 text-blue-700",
    purple: "bg-purple-100 text-purple-700",
    danger: "bg-red-100 text-red-700",
    cyan: "bg-cyan-100 text-cyan-700",
  };

  // Plain counts get thousands separators ("3,631"); money values arrive already formatted
  const displayValue = /^\d+$/.test(String(value)) ? Number(value).toLocaleString("en-PK") : value;

  const content = (
    <>
      <div className="flex items-start justify-between mb-4">
        <div className={`w-12 h-12 rounded-xl flex items-center justify-center ${colorClasses[color]}`}>
          <span className="material-symbols-outlined text-[24px]">{icon}</span>
        </div>
        {trend && (
          <span
            className={`text-xs font-semibold px-2 py-1 rounded-full whitespace-nowrap ${
              alert
                ? "bg-red-50 text-red-700"
                : String(trend).startsWith("+")
                  ? "bg-emerald-50 text-emerald-700"
                  : "bg-amber-50 text-amber-700"
            }`}
          >
            {trend}
          </span>
        )}
      </div>
      <p
        className={`${String(displayValue).length > 14 ? "text-xl" : "text-2xl"} font-bold mb-1 whitespace-nowrap ${
          alert ? "text-error" : "text-on-surface"
        }`}
      >
        {displayValue}
      </p>
      <p className="text-sm text-on-surface-variant">{title}</p>
      {subtitle && <p className="text-xs text-outline mt-1">{subtitle}</p>}
      {href && (
        <p className="text-xs font-semibold text-primary mt-auto pt-3 flex items-center gap-1">
          View details
          <span className="material-symbols-outlined text-[14px]">arrow_forward</span>
        </p>
      )}
    </>
  );

  const baseClass = `bg-surface-container-lowest rounded-2xl p-6 border shadow-sm hover:shadow-md transition-shadow ${
    alert ? "border-error/40" : "border-outline-variant/20"
  }`;

  if (!href) return <div className={`${baseClass} flex flex-col`}>{content}</div>;

  return (
    <button onClick={() => router.push(href)} className={`${baseClass} text-left w-full flex flex-col justify-start`}>
      {content}
    </button>
  );
}

/** Total platform GMV = walk-in POS + online marketplace, with the daily split (SRDS §2.1) */
function ChannelGmvCard({ channels }) {
  const router = useRouter();
  const total = Number(channels.totalGmv) || 0;
  const subtitles = {
    walkIn: `${formatNumber(channels.walkIn?.sales)} sales · ${formatRs(channels.walkIn?.today)} today`,
    online: `${formatNumber(channels.online?.orders)} orders · ${formatRs(channels.online?.today)} today`,
  };

  return (
    <div className="bg-surface-container-lowest rounded-2xl p-6 border border-outline-variant/20 shadow-sm mb-8">
      <div className="flex flex-wrap items-start justify-between gap-3 mb-5">
        <div>
          <h3 className="text-lg font-bold text-on-surface">Platform GMV by channel</h3>
          <p className="text-sm text-on-surface-variant mt-0.5">
            Walk-in POS sales plus online marketplace orders (item value; delivery fees excluded).
          </p>
        </div>
        <button
          onClick={() => router.push("/dashboard/finance")}
          className="text-sm font-semibold text-primary hover:underline flex items-center gap-1"
        >
          Commission ledger
          <span className="material-symbols-outlined text-[16px]">arrow_forward</span>
        </button>
      </div>

      <div className="grid grid-cols-1 xl:grid-cols-3 gap-8">
        <div>
          <p className="text-[11px] font-semibold text-outline uppercase tracking-wider">Total platform GMV</p>
          <p className="text-3xl font-bold text-on-surface tabular-nums mt-1">{formatRs(total)}</p>
          <p className="text-xs text-outline mt-1 mb-4">Walk-in POS + online, all time</p>
          <ChannelSplitBar walkIn={channels.walkIn?.gmv} online={channels.online?.gmv} />
          <div className="mt-4 space-y-3">
            {CHANNELS.map((c) => {
              const gmv = Number(channels[c.key]?.gmv) || 0;
              return (
                <div key={c.key} className="flex items-start justify-between gap-3">
                  <div className="min-w-0">
                    <p className="text-sm font-medium text-on-surface flex items-center gap-2">
                      <ChannelSwatch channel={c} />
                      {c.label}
                    </p>
                    <p className="text-xs text-outline mt-0.5 pl-[18px]">{subtitles[c.key]}</p>
                  </div>
                  <div className="text-right shrink-0">
                    <p className="text-sm font-semibold text-on-surface tabular-nums">{formatRs(gmv)}</p>
                    <p className="text-xs text-outline tabular-nums">{total > 0 ? Math.round((gmv / total) * 100) : 0}%</p>
                  </div>
                </div>
              );
            })}
          </div>
        </div>

        <div className="xl:col-span-2 min-w-0">
          <div className="flex flex-wrap items-center justify-between gap-2 mb-2">
            <p className="text-[11px] font-semibold text-outline uppercase tracking-wider">
              Daily GMV · last {channels.series?.length || 0} days
            </p>
            <div className="flex items-center gap-4">
              {CHANNELS.map((c) => (
                <span key={c.key} className="inline-flex items-center gap-1.5 text-xs text-on-surface-variant">
                  <ChannelSwatch channel={c} />
                  {c.label}
                </span>
              ))}
            </div>
          </div>
          <ChannelSeriesChart series={channels.series} />
        </div>
      </div>
    </div>
  );
}

/** The latest disputes, open ones first (SRDS Fig 2.9 recent-disputes panel) */
function RecentDisputesCard({ disputes }) {
  const router = useRouter();
  return (
    <div className="bg-surface-container-lowest rounded-2xl p-6 border border-outline-variant/20 shadow-sm">
      <div className="flex items-center justify-between mb-4">
        <h3 className="text-lg font-bold text-on-surface">Recent Disputes</h3>
        <button onClick={() => router.push("/dashboard/disputes")} className="text-sm font-semibold text-primary hover:underline">
          View all
        </button>
      </div>
      {disputes.length === 0 ? (
        <p className="text-sm text-outline py-6 text-center">No disputes yet.</p>
      ) : (
        <ul className="divide-y divide-outline-variant/15">
          {disputes.map((d) => (
            <li key={d.id}>
              <button
                onClick={() => router.push(`/dashboard/disputes/${d.id}`)}
                className="w-full flex items-center gap-3 py-3 text-left hover:bg-surface-container-low/40 rounded-lg px-2 -mx-2 transition-colors"
              >
                <span className={`w-2 h-2 rounded-full shrink-0 ${d.status === "open" ? "bg-red-500" : "bg-outline-variant"}`} />
                <div className="min-w-0 flex-1">
                  <p className="text-sm font-semibold text-on-surface truncate">
                    {humanize(d.issueType)} · {formatOrderId(d.orderId)}
                  </p>
                  <p className="text-xs text-outline truncate">
                    {d.storeName} · {formatDate(d.createdAt, true)}
                  </p>
                </div>
                <span className={`px-2 py-0.5 rounded text-[10px] font-semibold uppercase tracking-wide ${roleColors[d.raisedByRole] || ""}`}>
                  {d.raisedByRole}
                </span>
                <span className="text-sm font-semibold text-on-surface tabular-nums whitespace-nowrap">{formatRs(d.heldAmount)}</span>
              </button>
            </li>
          ))}
        </ul>
      )}
    </div>
  );
}

function HealthRow({ ok, warn = false, icon, title, detail }) {
  const tone = ok ? "text-emerald-700 bg-emerald-100" : warn ? "text-amber-700 bg-amber-100" : "text-red-700 bg-red-100";
  return (
    <li className="flex items-start gap-3 py-3">
      <span className={`w-9 h-9 rounded-lg flex items-center justify-center shrink-0 ${tone}`}>
        <span className="material-symbols-outlined text-[20px]">{icon}</span>
      </span>
      <div className="min-w-0">
        <p className="text-sm font-semibold text-on-surface">{title}</p>
        <p className="text-xs text-outline">{detail}</p>
      </div>
    </li>
  );
}

/**
 * Live checks from GET /api/admin/stats (SRDS Fig 2.9 platform health, §4.3.2):
 * database round trip, escrow reconciliation (SSR 02), background jobs, realtime.
 */
function PlatformHealthCard({ health }) {
  const { database, escrow, sweep, realtime } = health;
  const sweepOk = sweep.lastRunAt && !sweep.lastError && sweep.secondsAgo <= sweep.intervalSeconds * 3;
  return (
    <div className="bg-surface-container-lowest rounded-2xl p-6 border border-outline-variant/20 shadow-sm">
      <h3 className="text-lg font-bold text-on-surface mb-1">Platform Health</h3>
      <p className="text-xs text-outline mb-2">Checked when this page loaded</p>
      <ul className="divide-y divide-outline-variant/15">
        <HealthRow
          ok={database.ok && database.latencyMs < 200}
          warn={database.ok}
          icon="database"
          title="Database"
          detail={`Responding in ${database.latencyMs} ms`}
        />
        <HealthRow
          ok={escrow.balanced}
          icon="account_balance"
          title={escrow.balanced ? "Escrow reconciled" : "Escrow mismatch"}
          detail={
            escrow.balanced
              ? `Pool ${formatRs(escrow.pool)} equals what ${formatNumber(escrow.orders)} open order${escrow.orders === 1 ? "" : "s"} hold`
              : `Pool ${formatRs(escrow.pool)} but open orders hold ${formatRs(escrow.heldByOrders)}`
          }
        />
        <HealthRow
          ok={Boolean(sweepOk)}
          warn={!sweep.lastRunAt}
          icon="update"
          title="Background jobs"
          detail={
            sweep.lastError
              ? `Last run failed: ${sweep.lastError}`
              : sweep.lastRunAt
                ? `Escrow release, timeouts and payment checks ran ${sweep.secondsAgo}s ago (every ${sweep.intervalSeconds}s)`
                : "Not run yet since the server started"
          }
        />
        <HealthRow
          ok
          icon="sensors"
          title="Realtime"
          detail={`${formatNumber(realtime.connections)} app${realtime.connections === 1 ? "" : "s"} connected for live updates`}
        />
      </ul>
    </div>
  );
}

export default function DashboardPage() {
  const [stats, setStats] = useState(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(null);
  const router = useRouter();

  useEffect(() => {
    const token = localStorage.getItem("vendra_admin_token");
    if (!token) {
      router.push("/");
      return;
    }

    async function fetchStats() {
      try {
        const res = await getDashboardStats();
        setStats(res.data);
      } catch (err) {
        if (isAuthError(err)) {
          router.push("/");
        }
        setError(err.message);
      } finally {
        setLoading(false);
      }
    }
    fetchStats();
  }, [router]);

  if (loading) {
    return (
      <div className="flex items-center justify-center h-64">
        <div className="flex flex-col items-center gap-3">
          <svg className="animate-spin w-8 h-8 text-primary" fill="none" viewBox="0 0 24 24">
            <circle className="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" strokeWidth="4" />
            <path className="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4z" />
          </svg>
          <p className="text-sm text-outline">Loading dashboard...</p>
        </div>
      </div>
    );
  }

  if (error) return <ErrorBox title="Error loading dashboard" message={error} />;

  const openDisputes = Number(stats?.openDisputes) || 0;
  const pendingProducts = Number(stats?.pendingProducts) || 0;
  const pendingVendors = Number(stats?.vendors?.pending) || 0;
  const locationRequests = Number(stats?.vendors?.location_requests) || 0;
  const locationRequestsText = `${locationRequests} store location change${locationRequests > 1 ? "s" : ""}`;

  return (
    <div>
      {/* Welcome Header */}
      <div className="mb-8">
        <h1 className="text-2xl font-bold text-on-surface">Welcome back, Admin</h1>
        <p className="text-on-surface-variant mt-1">Here&apos;s what&apos;s happening on your marketplace today.</p>
      </div>

      {/* KPI Grid */}
      <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-5 mb-5">
        <KPICard
          title="Total Vendors"
          value={stats?.vendors?.total || 0}
          subtitle={`${pendingVendors} pending approval${locationRequests > 0 ? ` • ${locationRequestsText}` : ""}`}
          icon="storefront"
          color="primary"
          href="/dashboard/vendors"
        />
        <KPICard
          title="Total Customers"
          value={stats?.customers || 0}
          subtitle="Registered shopper accounts"
          icon="group"
          color="info"
          href="/dashboard/users"
        />
        <KPICard
          title="Total Orders"
          value={stats?.orders?.total || 0}
          subtitle={`${stats?.orders?.today || 0} order${Number(stats?.orders?.today) === 1 ? "" : "s"} today`}
          icon="receipt_long"
          color="secondary"
          trend={stats?.orders?.today > 0 ? `+${stats.orders.today} today` : undefined}
          href="/dashboard/orders"
        />
        <KPICard
          title="Total Revenue"
          value={formatRs(stats?.orders?.totalRevenue)}
          subtitle={`${formatRs(stats?.orders?.todayRevenue)} today`}
          icon="payments"
          color="success"
        />
      </div>

      {/* Store location change requests */}
      {locationRequests > 0 && (
        <button
          onClick={() => router.push("/dashboard/vendors?filter=location")}
          className="w-full bg-blue-50 border border-blue-200 rounded-xl p-4 mb-5 flex items-center gap-3 text-left hover:bg-blue-100/60 transition-colors"
        >
          <div className="w-10 h-10 bg-blue-100 rounded-lg flex items-center justify-center shrink-0">
            <span className="material-symbols-outlined text-blue-700 text-[22px]">edit_location_alt</span>
          </div>
          <div>
            <p className="text-sm font-semibold text-blue-900">{locationRequestsText} awaiting review</p>
            <p className="text-xs text-blue-700">Vendors asked to move their store pin. Approve or reject each request.</p>
          </div>
          <span className="ml-auto text-sm font-semibold text-blue-700">Review →</span>
        </button>
      )}

      {/* Operations: items that need admin attention */}
      <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-5 mb-5">
        <KPICard
          title="Open Disputes"
          value={openDisputes}
          subtitle="Escrow frozen until you decide"
          icon="gavel"
          color="danger"
          alert={openDisputes > 0}
          trend={openDisputes > 0 ? "Action required" : undefined}
          href="/dashboard/disputes"
        />
        <KPICard
          title="Products Awaiting Approval"
          value={pendingProducts}
          subtitle="Hidden from customers until approved"
          icon="inventory"
          color="purple"
          trend={pendingProducts > 0 ? "Needs review" : undefined}
          href="/dashboard/products"
        />
        <KPICard
          title="Riders Online"
          value={stats?.ridersOnline || 0}
          subtitle={
            stats?.pendingRiders
              ? `Out of ${stats?.riders || 0} · ${stats.pendingRiders} awaiting document review`
              : `Out of ${stats?.riders || 0} registered`
          }
          icon="two_wheeler"
          color="cyan"
          trend={stats?.pendingRiders > 0 ? "Documents to review" : undefined}
          href="/dashboard/riders"
        />
        <KPICard
          title="Orders In Progress"
          value={stats?.orders?.inProgress || 0}
          subtitle="Not yet delivered or cancelled"
          icon="local_shipping"
          color="secondary"
          href="/dashboard/orders"
        />
      </div>

      {/* Secondary Stats */}
      <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-5 mb-8">
        <KPICard
          title="Active Products"
          value={stats?.products || 0}
          icon="inventory_2"
          color="purple"
          href="/dashboard/products"
        />
        <KPICard
          title="Escrow Held"
          value={formatRs(stats?.escrowHeld)}
          subtitle="Customer payments not yet settled"
          icon="account_balance_wallet"
          color="success"
          href="/dashboard/finance"
        />
        <KPICard
          title="Platform Revenue"
          value={formatRs(stats?.platformRevenue)}
          subtitle="Commission + delivery margin"
          icon="savings"
          color="info"
          href="/dashboard/finance"
        />
        <KPICard
          title="Pending Vendor Approvals"
          value={pendingVendors}
          subtitle={locationRequests > 0 ? `+ ${locationRequestsText} to review` : undefined}
          icon="pending_actions"
          color="primary"
          trend={pendingVendors > 0 || locationRequests > 0 ? "Needs attention" : undefined}
          href={pendingVendors === 0 && locationRequests > 0 ? "/dashboard/vendors?filter=location" : "/dashboard/vendors"}
        />
      </div>

      {stats?.channels && <ChannelGmvCard channels={stats.channels} />}

      {stats?.health && (
        <div className="grid grid-cols-1 lg:grid-cols-2 gap-5 mb-8">
          <RecentDisputesCard disputes={stats.recentDisputes || []} />
          <PlatformHealthCard health={stats.health} />
        </div>
      )}

      {/* Quick Actions */}
      <div className="bg-surface-container-lowest rounded-2xl p-6 border border-outline-variant/20 shadow-sm">
        <h3 className="text-lg font-bold text-on-surface mb-4">Quick Actions</h3>
        <div className="grid grid-cols-1 md:grid-cols-3 gap-3">
          <button
            onClick={() => router.push("/dashboard/vendors")}
            className="flex items-center gap-3 p-4 bg-primary/5 rounded-xl hover:bg-primary/10 transition-colors text-left"
          >
            <div className="w-10 h-10 bg-primary/10 rounded-lg flex items-center justify-center">
              <span className="material-symbols-outlined text-primary text-[20px]">verified</span>
            </div>
            <div>
              <p className="text-sm font-semibold text-on-surface">Manage Vendors</p>
              <p className="text-xs text-outline">Approve or review vendors</p>
            </div>
          </button>
          <button
            onClick={() => router.push("/dashboard/orders")}
            className="flex items-center gap-3 p-4 bg-orange-50 rounded-xl hover:bg-orange-100/60 transition-colors text-left"
          >
            <div className="w-10 h-10 bg-orange-100 rounded-lg flex items-center justify-center">
              <span className="material-symbols-outlined text-secondary text-[20px]">local_shipping</span>
            </div>
            <div>
              <p className="text-sm font-semibold text-on-surface">View Orders</p>
              <p className="text-xs text-outline">Monitor all marketplace orders</p>
            </div>
          </button>
          <button
            onClick={() => router.push("/dashboard/users")}
            className="flex items-center gap-3 p-4 bg-blue-50 rounded-xl hover:bg-blue-100/60 transition-colors text-left"
          >
            <div className="w-10 h-10 bg-blue-100 rounded-lg flex items-center justify-center">
              <span className="material-symbols-outlined text-blue-700 text-[20px]">person_search</span>
            </div>
            <div>
              <p className="text-sm font-semibold text-on-surface">User Management</p>
              <p className="text-xs text-outline">View all platform users</p>
            </div>
          </button>
          <button
            onClick={() => router.push("/dashboard/disputes")}
            className="flex items-center gap-3 p-4 bg-red-50 rounded-xl hover:bg-red-100/60 transition-colors text-left"
          >
            <div className="w-10 h-10 bg-red-100 rounded-lg flex items-center justify-center">
              <span className="material-symbols-outlined text-red-700 text-[20px]">gavel</span>
            </div>
            <div>
              <p className="text-sm font-semibold text-on-surface">Resolve Disputes</p>
              <p className="text-xs text-outline">Review evidence, refund or release</p>
            </div>
          </button>
          <button
            onClick={() => router.push("/dashboard/products")}
            className="flex items-center gap-3 p-4 bg-purple-50 rounded-xl hover:bg-purple-100/60 transition-colors text-left"
          >
            <div className="w-10 h-10 bg-purple-100 rounded-lg flex items-center justify-center">
              <span className="material-symbols-outlined text-purple-700 text-[20px]">fact_check</span>
            </div>
            <div>
              <p className="text-sm font-semibold text-on-surface">Approve Products</p>
              <p className="text-xs text-outline">Moderate the product catalog</p>
            </div>
          </button>
          <button
            onClick={() => router.push("/dashboard/policies")}
            className="flex items-center gap-3 p-4 bg-emerald-50 rounded-xl hover:bg-emerald-100/60 transition-colors text-left"
          >
            <div className="w-10 h-10 bg-emerald-100 rounded-lg flex items-center justify-center">
              <span className="material-symbols-outlined text-emerald-700 text-[20px]">tune</span>
            </div>
            <div>
              <p className="text-sm font-semibold text-on-surface">Platform Policies</p>
              <p className="text-xs text-outline">Fees, commission, payout rules</p>
            </div>
          </button>
        </div>
      </div>
    </div>
  );
}
