"use client";

import { useState, useEffect } from "react";
import { useRouter } from "next/navigation";
import { getDashboardStats } from "../lib/api";

function KPICard({ title, value, subtitle, icon, color, trend }) {
  const colorClasses = {
    primary: "bg-primary/10 text-primary",
    secondary: "bg-orange-100 text-secondary",
    success: "bg-emerald-100 text-emerald-700",
    info: "bg-blue-100 text-blue-700",
    purple: "bg-purple-100 text-purple-700",
  };

  return (
    <div className="bg-white rounded-2xl p-6 border border-outline-variant/20 shadow-sm hover:shadow-md transition-shadow">
      <div className="flex items-start justify-between mb-4">
        <div className={`w-12 h-12 rounded-xl flex items-center justify-center ${colorClasses[color]}`}>
          <span className="material-symbols-outlined text-[24px]">{icon}</span>
        </div>
        {trend && (
          <span className="text-xs font-semibold px-2 py-1 rounded-full bg-emerald-50 text-emerald-700">
            {trend}
          </span>
        )}
      </div>
      <p className="text-2xl font-bold text-on-surface mb-1">{value}</p>
      <p className="text-sm text-on-surface-variant">{title}</p>
      {subtitle && <p className="text-xs text-outline mt-1">{subtitle}</p>}
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
        if (err.message.includes("token") || err.message.includes("denied")) {
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

  return (
    <div>
      {/* Welcome Header */}
      <div className="mb-8">
        <h1 className="text-2xl font-bold text-on-surface">Welcome back, Admin 👋</h1>
        <p className="text-on-surface-variant mt-1">Here&apos;s what&apos;s happening on your marketplace today.</p>
      </div>

      {/* KPI Grid */}
      <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-5 mb-8">
        <KPICard
          title="Total Vendors"
          value={stats?.vendors?.total || 0}
          subtitle={`${stats?.vendors?.pending || 0} pending approval`}
          icon="storefront"
          color="primary"
        />
        <KPICard
          title="Total Customers"
          value={stats?.customers || 0}
          icon="group"
          color="info"
        />
        <KPICard
          title="Total Orders"
          value={stats?.orders?.total || 0}
          subtitle={`${stats?.orders?.today || 0} orders today`}
          icon="receipt_long"
          color="secondary"
          trend={stats?.orders?.today > 0 ? `+${stats.orders.today} today` : undefined}
        />
        <KPICard
          title="Total Revenue"
          value={`Rs. ${(stats?.orders?.totalRevenue || 0).toLocaleString()}`}
          subtitle={`Rs. ${(stats?.orders?.todayRevenue || 0).toLocaleString()} today`}
          icon="payments"
          color="success"
        />
      </div>

      {/* Secondary Stats */}
      <div className="grid grid-cols-1 md:grid-cols-3 gap-5 mb-8">
        <KPICard
          title="Active Products"
          value={stats?.products || 0}
          icon="inventory_2"
          color="purple"
        />
        <KPICard
          title="Escrow Held"
          value={`Rs. ${(stats?.escrowHeld || 0).toLocaleString()}`}
          icon="account_balance_wallet"
          color="success"
        />
        <KPICard
          title="Pending Approvals"
          value={stats?.vendors?.pending || 0}
          icon="pending_actions"
          color="primary"
          trend={parseInt(stats?.vendors?.pending) > 0 ? "Needs attention" : undefined}
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
        </div>
      </div>
    </div>
  );
}
