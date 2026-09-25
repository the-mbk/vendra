"use client";

import { useState, useEffect } from "react";
import { useRouter } from "next/navigation";
import { getOrders, isAuthError } from "../../lib/api";
import { orderStatusConfig as statusConfig, EscrowBadge, Th, formatRs } from "../../lib/ui";

function DeliveryType({ type }) {
  const pickup = type === "self_pickup";
  return (
    <span className="inline-flex items-center gap-1 text-xs font-medium text-on-surface-variant whitespace-nowrap">
      <span className="material-symbols-outlined text-[16px]">{pickup ? "storefront" : "local_shipping"}</span>
      {pickup ? "Self pickup" : "Delivery"}
    </span>
  );
}

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
        if (isAuthError(err)) router.push("/");
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

  const totalRevenue = orders.reduce((sum, o) => sum + (Number(o.totalAmount) || 0), 0);

  return (
    <div>
      {/* Header */}
      <div className="flex items-center justify-between mb-6">
        <div>
          <h1 className="text-2xl font-bold text-on-surface">Orders</h1>
          <p className="text-on-surface-variant text-sm mt-1">
            {orders.length} total orders • {formatRs(totalRevenue)} revenue
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
                <Th>Order</Th>
                <Th>Customer</Th>
                <Th>Vendor</Th>
                <Th>Items</Th>
                <Th>Amount</Th>
                <Th>Status</Th>
                <Th>Escrow</Th>
                <Th>Delivery</Th>
                <Th>Rider</Th>
                <Th>Rider payout</Th>
                <Th>Date</Th>
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
                    <td className="px-5 py-4 text-sm font-semibold text-on-surface whitespace-nowrap">
                      {formatRs(order.totalAmount)}
                    </td>
                    <td className="px-5 py-4">
                      <span className={`inline-flex items-center gap-1 px-2.5 py-1 rounded-full text-xs font-semibold whitespace-nowrap ${config.color}`}>
                        <span className={`w-1.5 h-1.5 rounded-full ${config.dot}`} />
                        {config.label}
                      </span>
                    </td>
                    <td className="px-5 py-4"><EscrowBadge status={order.escrowStatus} /></td>
                    <td className="px-5 py-4"><DeliveryType type={order.deliveryType} /></td>
                    <td className="px-5 py-4 text-sm text-on-surface whitespace-nowrap">
                      {order.riderName || (
                        <span className="text-xs text-outline">
                          {order.deliveryType === "self_pickup" ? "Not needed" : "Unassigned"}
                        </span>
                      )}
                    </td>
                    <td className="px-5 py-4 text-sm text-on-surface whitespace-nowrap">
                      {Number(order.riderPayout) > 0 ? formatRs(order.riderPayout) : <span className="text-xs text-outline">—</span>}
                    </td>
                    <td className="px-5 py-4 text-xs text-outline whitespace-nowrap">
                      {new Date(order.createdAt).toLocaleDateString("en-PK", {
                        day: "numeric", month: "short", year: "numeric",
                      })}
                    </td>
                  </tr>
                );
              })}

              {orders.length === 0 && (
                <tr>
                  <td colSpan={11} className="text-center py-12 text-on-surface-variant">
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
