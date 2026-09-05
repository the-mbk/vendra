"use client";

import { useState, useEffect } from "react";
import { useRouter } from "next/navigation";
import { getOrders } from "../../lib/api";

const statusConfig = {
  confirmed: { label: "Confirmed", color: "bg-blue-100 text-blue-700", dot: "bg-blue-500" },
  packed: { label: "Packed", color: "bg-purple-100 text-purple-700", dot: "bg-purple-500" },
  ready_for_pickup: { label: "Ready", color: "bg-amber-100 text-amber-700", dot: "bg-amber-500" },
  picked: { label: "Picked Up", color: "bg-cyan-100 text-cyan-700", dot: "bg-cyan-500" },
  on_the_way: { label: "On the Way", color: "bg-orange-100 text-orange-700", dot: "bg-orange-500" },
  delivered: { label: "Delivered", color: "bg-emerald-100 text-emerald-700", dot: "bg-emerald-500" },
  cancelled: { label: "Cancelled", color: "bg-red-100 text-red-700", dot: "bg-red-500" },
};

export default function OrdersPage() {
  const [orders, setOrders] = useState([]);
  const [loading, setLoading] = useState(true);
  const router = useRouter();

  useEffect(() => {
    const token = localStorage.getItem("vendra_admin_token");
    if (!token) { router.push("/"); return; }

    async function fetchOrders() {
      try {
        const res = await getOrders();
        setOrders(res.data);
      } catch (err) {
        console.error("Error fetching orders:", err);
      } finally {
        setLoading(false);
      }
    }
    fetchOrders();
  }, [router]);

  if (loading) {
    return (
      <div className="flex items-center justify-center h-64">
        <svg className="animate-spin w-8 h-8 text-primary" fill="none" viewBox="0 0 24 24">
          <circle className="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" strokeWidth="4" />
          <path className="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4z" />
        </svg>
      </div>
    );
  }

  const totalRevenue = orders.reduce((sum, o) => sum + o.totalAmount, 0);

  return (
    <div>
      {/* Header */}
      <div className="flex items-center justify-between mb-6">
        <div>
          <h1 className="text-2xl font-bold text-on-surface">Orders</h1>
          <p className="text-on-surface-variant text-sm mt-1">
            {orders.length} total orders • Rs. {totalRevenue.toLocaleString()} revenue
          </p>
        </div>
      </div>

      {/* Summary Cards */}
      <div className="grid grid-cols-2 md:grid-cols-4 gap-4 mb-6">
        {Object.entries(
          orders.reduce((acc, o) => { acc[o.status] = (acc[o.status] || 0) + 1; return acc; }, {})
        ).map(([status, count]) => {
          const config = statusConfig[status] || statusConfig.confirmed;
          return (
            <div key={status} className="bg-white rounded-xl p-4 border border-outline-variant/20">
              <div className="flex items-center gap-2 mb-2">
                <span className={`w-2 h-2 rounded-full ${config.dot}`} />
                <span className="text-xs font-semibold text-on-surface-variant uppercase">{config.label}</span>
              </div>
              <p className="text-2xl font-bold text-on-surface">{count}</p>
            </div>
          );
        })}
      </div>

      {/* Orders Table */}
      <div className="bg-white rounded-2xl border border-outline-variant/20 shadow-sm overflow-hidden">
        <div className="overflow-x-auto">
          <table className="w-full">
            <thead>
              <tr className="bg-surface-container-low/50 border-b border-outline-variant/20">
                <th className="text-left px-5 py-3.5 text-xs font-semibold text-on-surface-variant uppercase tracking-wider">Order</th>
                <th className="text-left px-5 py-3.5 text-xs font-semibold text-on-surface-variant uppercase tracking-wider">Customer</th>
                <th className="text-left px-5 py-3.5 text-xs font-semibold text-on-surface-variant uppercase tracking-wider">Vendor</th>
                <th className="text-left px-5 py-3.5 text-xs font-semibold text-on-surface-variant uppercase tracking-wider">Items</th>
                <th className="text-left px-5 py-3.5 text-xs font-semibold text-on-surface-variant uppercase tracking-wider">Amount</th>
                <th className="text-left px-5 py-3.5 text-xs font-semibold text-on-surface-variant uppercase tracking-wider">Status</th>
                <th className="text-left px-5 py-3.5 text-xs font-semibold text-on-surface-variant uppercase tracking-wider">Date</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-outline-variant/10">
              {orders.map((order) => {
                const config = statusConfig[order.status] || statusConfig.confirmed;
                return (
                  <tr key={order.id} className="hover:bg-surface-container-low/30 transition-colors">
                    <td className="px-5 py-4">
                      <span className="text-sm font-bold text-primary">
                        #VDR-{String(order.id).padStart(5, "0")}
                      </span>
                    </td>
                    <td className="px-5 py-4">
                      <p className="text-sm font-medium text-on-surface">{order.customerName}</p>
                      <p className="text-xs text-outline">{order.customerEmail}</p>
                    </td>
                    <td className="px-5 py-4 text-sm text-on-surface">{order.storeName}</td>
                    <td className="px-5 py-4 text-sm text-on-surface font-medium">{order.itemCount}</td>
                    <td className="px-5 py-4 text-sm font-semibold text-on-surface">
                      Rs. {order.totalAmount.toLocaleString()}
                    </td>
                    <td className="px-5 py-4">
                      <span className={`inline-flex items-center gap-1 px-2.5 py-1 rounded-full text-xs font-semibold ${config.color}`}>
                        <span className={`w-1.5 h-1.5 rounded-full ${config.dot}`} />
                        {config.label}
                      </span>
                    </td>
                    <td className="px-5 py-4 text-xs text-outline">
                      {new Date(order.createdAt).toLocaleDateString("en-PK", {
                        day: "numeric", month: "short", year: "numeric",
                      })}
                    </td>
                  </tr>
                );
              })}

              {orders.length === 0 && (
                <tr>
                  <td colSpan={7} className="text-center py-12 text-on-surface-variant">
                    <span className="material-symbols-outlined text-[48px] text-outline-variant block mb-2">inbox</span>
                    No orders yet.
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
