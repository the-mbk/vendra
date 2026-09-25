"use client";

import { useState, useEffect } from "react";
import { useRouter } from "next/navigation";
import { getDashboardStats, isAuthError } from "../lib/api";
import { formatRs } from "../lib/ui";

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

  const content = (
    <>
      <div className="flex items-start justify-between mb-4">
        <div className={`w-12 h-12 rounded-xl flex items-center justify-center ${colorClasses[color]}`}>
          <span className="material-symbols-outlined text-[24px]">{icon}</span>
        </div>
        {trend && (
          <span
            className={`text-xs font-semibold px-2 py-1 rounded-full ${
              alert ? "bg-red-50 text-red-700" : "bg-emerald-50 text-emerald-700"
            }`}
          >
            {trend}
          </span>
        )}
      </div>
      <p className={`text-2xl font-bold mb-1 ${alert ? "text-error" : "text-on-surface"}`}>{value}</p>
      <p className="text-sm text-on-surface-variant">{title}</p>
      {subtitle && <p className="text-xs text-outline mt-1">{subtitle}</p>}
      {href && (
        <p className="text-xs font-semibold text-primary mt-3 flex items-center gap-1">
          View details
          <span className="material-symbols-outlined text-[14px]">arrow_forward</span>
        </p>
      )}
    </>
  );

  const baseClass = `bg-white rounded-2xl p-6 border shadow-sm hover:shadow-md transition-shadow ${
    alert ? "border-error/40" : "border-outline-variant/20"
  }`;

  if (!href) return <div className={baseClass}>{content}</div>;

  return (
    <button onClick={() => router.push(href)} className={`${baseClass} text-left w-full flex flex-col justify-start`}>
      {content}
    </button>
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

  if (error) {
    return (
      <div className="bg-red-50 border border-red-200 text-red-700 p-4 rounded-xl">
        <p className="font-semibold">Error loading dashboard</p>
        <p className="text-sm mt-1">{error}</p>
      </div>
    );
  }

  const openDisputes = Number(stats?.openDisputes) || 0;
  const pendingProducts = Number(stats?.pendingProducts) || 0;

  return (
    <div>
      {/* Welcome Header */}
      <div className="mb-8">
        <h1 className="text-2xl font-bold text-on-surface">Welcome back, Admin 👋</h1>
        <p className="text-on-surface-variant mt-1">Here&apos;s what&apos;s happening on your marketplace today.</p>
      </div>

      {/* KPI Grid */}
      <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-5 mb-5">
        <KPICard
          title="Total Vendors"
          value={stats?.vendors?.total || 0}
          subtitle={`${stats?.vendors?.pending || 0} pending approval`}
          icon="storefront"
          color="primary"
          href="/dashboard/vendors"
        />
        <KPICard
          title="Total Customers"
          value={stats?.customers || 0}
          icon="group"
          color="info"
          href="/dashboard/users"
        />
        <KPICard
          title="Total Orders"
          value={stats?.orders?.total || 0}
          subtitle={`${stats?.orders?.today || 0} orders today`}
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
          subtitle={`Out of ${stats?.riders || 0} registered`}
          icon="two_wheeler"
          color="cyan"
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
          value={stats?.vendors?.pending || 0}
          icon="pending_actions"
          color="primary"
          trend={parseInt(stats?.vendors?.pending) > 0 ? "Needs attention" : undefined}
          href="/dashboard/vendors"
        />
      </div>

      {/* Quick Actions */}
      <div className="bg-white rounded-2xl p-6 border border-outline-variant/20 shadow-sm">
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
