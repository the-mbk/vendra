"use client";

import { useState, useEffect } from "react";
import { useRouter } from "next/navigation";
import { getOrders, isAuthError } from "../../lib/api";
import {
  orderStatusConfig as statusConfig, EscrowBadge, Th, SearchBox, NoSearchResults,
  formatRs, formatNumber, formatOrderId, matchesSearch, matchesId,
} from "../../lib/ui";

function DeliveryType({ type }) {
  const pickup = type === "self_pickup";
  return (
    <span className="inline-flex items-center gap-1 text-xs font-medium text-on-surface-variant whitespace-nowrap">
      <span className="material-symbols-outlined text-[16px]">{pickup ? "storefront" : "local_shipping"}</span>
      {pickup ? "Self pickup" : "Delivery"}
    </span>
  );
}

/** How the customer paid: from their wallet or by card at checkout */
function PaymentMethod({ method }) {
  const card = method === "card";
  return (
    <span className="flex items-center gap-1 mt-0.5 text-[11px] font-medium text-outline">
      <span className="material-symbols-outlined text-[14px]">{card ? "credit_card" : "account_balance_wallet"}</span>
      {card ? "Card" : "Wallet"}
    </span>
  );
}

export default function OrdersPage() {
  const [orders, setOrders] = useState([]);
  const [loading, setLoading] = useState(true);
  const [search, setSearch] = useState("");
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

  // Links like /dashboard/orders#order-12 (from Card Payments) scroll to that order once loaded
  useEffect(() => {
    if (loading || !window.location.hash.startsWith("#order-")) return;
    document.getElementById(window.location.hash.slice(1))?.scrollIntoView({ behavior: "smooth", block: "center" });
  }, [loading]);

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
  // Only reached in the browser (the server render stops at the loader above)
  const linkedRowId = window.location.hash.slice(1);
  const filteredOrders = orders.filter(
    (o) =>
      matchesId(search, o.id, formatOrderId(o.id)) ||
      matchesSearch(search, o.customerName, o.customerEmail, o.storeName, o.riderName)
  );

  return (
    <div>
      {/* Header */}
      <div className="flex items-center justify-between mb-6">
        <div>
          <h1 className="text-2xl font-bold text-on-surface">Orders</h1>
          <p className="text-on-surface-variant text-sm mt-1">
            {formatNumber(orders.length)} total orders • {formatRs(totalRevenue)} revenue
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
              <p className="text-2xl font-bold text-on-surface">{formatNumber(count)}</p>
            </div>
          );
        })}
      </div>

      {/* Search */}
      <div className="flex justify-end mb-4">
        <SearchBox
          value={search}
          onChange={setSearch}
          placeholder="Search order #, customer, store or rider"
          count={filteredOrders.length}
          total={orders.length}
        />
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
                <Th align="center">Items</Th>
                <Th>Amount</Th>
                <Th>Status</Th>
                <Th>Escrow</Th>
                <Th>Rider / payout</Th>
              </tr>
            </thead>
            <tbody className="divide-y divide-outline-variant/10">
              {filteredOrders.map((order) => {
                const config = statusConfig[order.status] || statusConfig.confirmed;
                return (
                  <tr
                    key={order.id}
                    id={`order-${order.id}`}
                    className={`transition-colors scroll-mt-24 ${
                      linkedRowId === `order-${order.id}` ? "bg-amber-50" : "hover:bg-surface-container-low/30"
                    }`}
                  >
                    <td className="px-4 py-3.5 whitespace-nowrap">
                      <span className="text-sm font-bold text-primary">
                        #VDR-{String(order.id).padStart(5, "0")}
                      </span>
                      <p className="text-[11px] text-outline mt-0.5">
                        {new Date(order.createdAt).toLocaleDateString("en-PK", {
                          day: "numeric", month: "short", year: "numeric",
                        })}
                      </p>
                    </td>
                    <td className="px-4 py-3.5 max-w-[210px]">
                      <p className="text-sm font-medium text-on-surface truncate" title={order.customerName}>{order.customerName}</p>
                      <p className="text-xs text-outline truncate" title={order.customerEmail}>{order.customerEmail}</p>
                    </td>
                    <td className="px-4 py-3.5 text-sm text-on-surface min-w-[130px] max-w-[180px]">{order.storeName}</td>
                    <td className="px-4 py-3.5 text-sm text-on-surface font-medium text-center">{order.itemCount}</td>
                    <td className="px-4 py-3.5 text-sm font-semibold text-on-surface whitespace-nowrap">
                      {formatRs(order.totalAmount)}
                      {order.paymentMethod && <PaymentMethod method={order.paymentMethod} />}
                    </td>
                    <td className="px-4 py-3.5">
                      <span className={`inline-flex items-center gap-1 px-2.5 py-1 rounded-full text-xs font-semibold whitespace-nowrap ${config.color}`}>
                        <span className={`w-1.5 h-1.5 rounded-full ${config.dot}`} />
                        {config.label}
                      </span>
                      {order.status === "cancelled" && order.cancellationReason && (
                        <p className="text-[11px] text-outline mt-1 max-w-[150px] leading-snug">{order.cancellationReason}</p>
                      )}
                    </td>
                    <td className="px-4 py-3.5"><EscrowBadge status={order.escrowStatus} /></td>
                    <td className="px-4 py-3.5 text-sm text-on-surface whitespace-nowrap">
                      {order.riderName || (
                        <span className="text-xs text-outline">
                          {order.deliveryType === "self_pickup" ? "Not needed" : "Unassigned"}
                        </span>
                      )}
                      <div className="mt-0.5 flex items-center gap-2">
                        <DeliveryType type={order.deliveryType} />
                        {Number(order.riderPayout) > 0 && (
                          <span className="text-[11px] font-semibold text-on-surface-variant" title="Rider payout">
                            · {formatRs(order.riderPayout)}
                          </span>
                        )}
                      </div>
                    </td>
                  </tr>
                );
              })}

              {filteredOrders.length === 0 && (
                <tr>
                  <td colSpan={8} className="text-center py-12 text-on-surface-variant">
                    {orders.length > 0 ? (
                      <NoSearchResults query={search} onClear={() => setSearch("")} />
                    ) : (
                      <>
                        <span className="material-symbols-outlined text-[48px] text-outline-variant block mb-2">inbox</span>
                        No orders yet.
                      </>
                    )}
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
