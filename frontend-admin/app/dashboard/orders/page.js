"use client";

import { useState, useEffect } from "react";
import { useRouter } from "next/navigation";
import { getOrders, getOrderDetails, fileUrl, isAuthError } from "../../lib/api";
import {
  orderStatusConfig as statusConfig, EscrowBadge, OrderStatusBadge, MaskedPhone, ErrorBox, Th, SearchBox, NoSearchResults, Spinner,
  formatRs, formatNumber, formatOrderId, formatDate, matchesSearch, matchesId,
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

const osmLink = (lat, lng) => `https://www.openstreetmap.org/?mlat=${lat}&mlon=${lng}#map=17/${lat}/${lng}`;

const escrowNote = {
  held: "Held until delivery and the dispute window",
  disputed: "Frozen until an admin resolves the dispute",
  released: "Paid out to the store",
  refunded: "Returned to the customer",
};

/** Small titled box used by every section of the drawer */
function Section({ icon, title, aside, children }) {
  return (
    <div className="rounded-xl border border-outline-variant/30 p-4">
      <div className="flex items-center justify-between gap-2 mb-2.5">
        <h4 className="flex items-center gap-1.5 text-xs font-bold uppercase tracking-wider text-outline">
          <span className="material-symbols-outlined text-[16px] text-primary">{icon}</span>
          {title}
        </h4>
        {aside}
      </div>
      {children}
    </div>
  );
}

function Stat({ label, children, note }) {
  return (
    <div className="p-3.5 rounded-xl bg-surface-container-low/60 border border-outline-variant/30 min-w-0">
      <p className="text-[11px] font-semibold text-outline uppercase tracking-wider">{label}</p>
      <div className="text-sm font-bold text-on-surface mt-1">{children}</div>
      {note && <p className="text-[11px] text-outline mt-1 leading-snug">{note}</p>}
    </div>
  );
}

function Party({ icon, role, children }) {
  return (
    <div className="rounded-xl border border-outline-variant/30 p-3.5 bg-surface-container-low/30 min-w-0">
      <div className="flex items-center gap-1.5 mb-2 text-xs font-bold uppercase tracking-wider text-outline">
        <span className="material-symbols-outlined text-[16px] text-primary">{icon}</span>
        {role}
      </div>
      {children}
    </div>
  );
}

function MoneyRow({ label, value, strong = false, muted = false }) {
  return (
    <div className={`flex justify-between gap-4 ${strong ? "font-bold text-on-surface pt-1.5 border-t border-outline-variant/20" : muted ? "text-xs text-outline" : "text-on-surface-variant"}`}>
      <span>{label}</span>
      <span className="font-mono tabular-nums whitespace-nowrap">{value}</span>
    </div>
  );
}

/**
 * Handover proof for a delivery: was the customer's code entered, how many wrong
 * tries, and where the rider stood against the customer's pin (geofence).
 */
function HandoverEvidence({ details }) {
  const h = details.handover;
  const inside = h.distanceFromPinMeters != null && h.distanceFromPinMeters <= h.geofenceMeters;
  return (
    <Section
      icon="verified_user"
      title="Delivery location & handover proof"
      aside={details.customerLat != null && (
        <a
          href={osmLink(details.customerLat, details.customerLng)}
          target="_blank"
          rel="noopener noreferrer"
          className="text-xs font-semibold text-primary hover:underline inline-flex items-center gap-1"
        >
          Customer pin
          <span className="material-symbols-outlined text-[14px]">open_in_new</span>
        </a>
      )}
    >
      <p className="text-sm text-on-surface font-medium">{details.deliveryAddress || "Pin dropped on the map"}</p>
      {details.deliveryNote && (
        <p className="text-xs text-on-surface-variant mt-1">
          <span className="font-semibold">Note for the rider:</span> {details.deliveryNote}
        </p>
      )}
      {details.customerLat != null && (
        <p className="text-xs font-mono text-outline mt-0.5">
          {details.customerLat.toFixed(5)}, {details.customerLng.toFixed(5)}
        </p>
      )}
      <dl className="grid grid-cols-1 sm:grid-cols-3 gap-3 mt-3 text-sm">
        <div>
          <dt className="text-[11px] font-semibold text-outline uppercase tracking-wider">Customer code</dt>
          <dd className={`mt-0.5 font-semibold ${h.codeVerifiedAt ? "text-emerald-700" : "text-on-surface-variant"}`}>
            {h.codeVerifiedAt ? `Entered ${formatDate(h.codeVerifiedAt, true)}` : "Not entered yet"}
          </dd>
        </div>
        <div>
          <dt className="text-[11px] font-semibold text-outline uppercase tracking-wider">Wrong attempts</dt>
          <dd className={`mt-0.5 font-semibold ${h.failedAttempts ? "text-amber-700" : "text-on-surface-variant"}`}>
            {h.failedAttempts}
            {h.lockedUntil && <span className="block text-xs text-error">Locked until {formatDate(h.lockedUntil, true)}</span>}
          </dd>
        </div>
        <div>
          <dt className="text-[11px] font-semibold text-outline uppercase tracking-wider">Rider at handover</dt>
          <dd className="mt-0.5">
            {h.distanceFromPinMeters == null ? (
              <span className="text-on-surface-variant">No handover position yet</span>
            ) : (
              <>
                <span className={`font-semibold ${inside ? "text-emerald-700" : "text-error"}`}>
                  {h.distanceFromPinMeters} m from the pin
                </span>
                <span className="block text-xs text-outline">
                  Geofence {h.geofenceMeters} m ·{" "}
                  <a href={osmLink(h.riderLat, h.riderLng)} target="_blank" rel="noopener noreferrer" className="text-primary hover:underline">
                    view point
                  </a>
                </span>
              </>
            )}
          </dd>
        </div>
      </dl>
    </Section>
  );
}

function Timeline({ details }) {
  const pickup = details.deliveryType === "self_pickup";
  const steps = [
    ["Placed", details.createdAt],
    ["Ready at the store", details.readyAt],
    ...(pickup ? [] : [
      ["Rider accepted", details.assignedAt],
      ["Rider at the store", details.arrivedAt],
      ["Picked up", details.pickedAt],
    ]),
    [pickup ? "Collected by the customer" : "Delivered", details.deliveredAt],
  ];
  return (
    <Section icon="timeline" title="Timeline">
      <ol className="space-y-1.5 text-sm">
        {steps.map(([label, at]) => (
          <li key={label} className="flex items-center justify-between gap-4">
            <span className={`flex items-center gap-2 ${at ? "text-on-surface" : "text-outline"}`}>
              <span className={`w-2 h-2 rounded-full ${at ? "bg-primary" : "bg-outline-variant"}`} />
              {label}
            </span>
            <span className="text-xs text-outline tabular-nums">{at ? formatDate(at, true) : "—"}</span>
          </li>
        ))}
      </ol>
      {details.status === "cancelled" && (
        <p className="mt-2.5 text-xs text-error">Cancelled{details.cancellationReason ? `: ${details.cancellationReason}` : ""}</p>
      )}
    </Section>
  );
}

function Settlement({ details }) {
  const s = details.settlement;
  return (
    <Section icon="account_balance" title="Money: escrow and settlement">
      <div className="space-y-1.5 text-sm">
        <MoneyRow label="Items subtotal" value={formatRs(details.subtotal)} />
        <MoneyRow label="Delivery fee" value={formatRs(details.deliveryFee)} />
        <MoneyRow label="Paid into escrow" value={formatRs(details.totalAmount)} strong />
      </div>
      <div className="space-y-1.5 text-sm mt-3 pt-3 border-t border-dashed border-outline-variant/40">
        {s.state === "refunded" ? (
          <>
            <MoneyRow label="Refunded to the customer's wallet" value={formatRs(s.refunded)} />
            {s.storeFee > 0 && <MoneyRow label="Late cancellation fee to the store" value={formatRs(s.storeFee)} />}
          </>
        ) : (
          <>
            {s.customerRefund > 0 && <MoneyRow label="Refunded to the customer (dispute)" value={formatRs(s.customerRefund)} />}
            <MoneyRow label={`Platform commission (${s.commissionPct}%)`} value={formatRs(s.commission)} />
            <MoneyRow label={s.state === "released" ? "Paid to the store" : "Store will receive"} value={formatRs(s.storeNet)} />
            {details.riderPayout > 0 && <MoneyRow label="Rider payout" value={formatRs(details.riderPayout)} />}
            {s.deliveryMargin != null && <MoneyRow label="Delivery margin kept by the platform" value={formatRs(s.deliveryMargin)} />}
            {s.state === "estimate" && (
              <MoneyRow muted label="Estimate at today's commission; final figures come from the ledger on release." value="" />
            )}
          </>
        )}
      </div>
    </Section>
  );
}

/** Customer ↔ rider chat for this delivery (read-only evidence) */
function ChatTranscript({ messages }) {
  return (
    <Section icon="forum" title={`Customer and rider messages (${messages.length})`}>
      <ul className="space-y-2">
        {messages.map((m) => (
          <li key={m.id} className={`flex ${m.senderRole === "rider" ? "justify-end" : "justify-start"}`}>
            <div className={`max-w-[80%] rounded-xl px-3 py-2 ${m.senderRole === "rider" ? "bg-primary/10" : "bg-surface-container-low"}`}>
              <p className="text-[11px] font-semibold text-outline uppercase tracking-wide">{m.senderRole}</p>
              <p className="text-sm text-on-surface whitespace-pre-line break-words">{m.body}</p>
              <p className="text-[11px] text-outline mt-0.5">{formatDate(m.createdAt, true)}</p>
            </div>
          </li>
        ))}
      </ul>
    </Section>
  );
}

/** Inspection drawer for one order: parties, handover proof, timeline, basket and money */
function OrderInspectionModal({ orderId, onClose }) {
  const [details, setDetails] = useState(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(null);

  useEffect(() => {
    function onKey(e) {
      if (e.key === "Escape") onClose();
    }
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [onClose]);

  useEffect(() => {
    let cancelled = false;
    async function load() {
      try {
        const res = await getOrderDetails(orderId);
        if (!cancelled) setDetails(res.data);
      } catch (err) {
        if (!cancelled) setError(err.message || "Failed to load the order");
      } finally {
        if (!cancelled) setLoading(false);
      }
    }
    load();
    return () => { cancelled = true; };
  }, [orderId]);

  const delivery = details?.deliveryType !== "self_pickup";

  return (
    <div className="fixed inset-0 z-50 bg-black/50 flex items-center justify-center p-4 sm:p-6" onClick={onClose}>
      <div
        role="dialog"
        aria-modal="true"
        aria-label={`Order ${formatOrderId(orderId)}`}
        className="bg-surface-container-lowest rounded-2xl shadow-2xl w-full max-w-3xl max-h-[92vh] overflow-y-auto"
        onClick={(e) => e.stopPropagation()}
      >
        <div className="flex items-start justify-between px-6 py-5 border-b border-outline-variant/20 sticky top-0 bg-surface-container-lowest z-10">
          <div className="flex items-center gap-3">
            <div className="w-11 h-11 bg-primary/10 rounded-xl flex items-center justify-center shrink-0">
              <span className="material-symbols-outlined text-primary text-[24px]">receipt_long</span>
            </div>
            <div>
              <div className="flex items-center gap-2 flex-wrap">
                <h3 className="text-lg font-bold text-on-surface">{formatOrderId(orderId)}</h3>
                {details && <OrderStatusBadge status={details.status} />}
              </div>
              <p className="text-xs text-outline mt-0.5">
                {details ? `Placed ${formatDate(details.createdAt, true)}` : "Loading the order..."}
              </p>
            </div>
          </div>
          <button
            onClick={onClose}
            aria-label="Close"
            className="material-symbols-outlined text-[22px] p-1.5 rounded-lg text-outline hover:text-on-surface hover:bg-surface-container-low transition-colors"
          >
            close
          </button>
        </div>

        <div className="p-6">
          {loading ? (
            <div className="py-16 flex flex-col items-center justify-center text-center">
              <Spinner className="w-8 h-8 mb-3" />
              <p className="text-sm font-semibold text-on-surface-variant">Loading the order...</p>
            </div>
          ) : error ? (
            <ErrorBox title="Could not load this order" message={error} />
          ) : details ? (
            <div className="space-y-5">
              <div className="grid grid-cols-2 sm:grid-cols-4 gap-3">
                <Stat label="Total charged" note={`Paid by ${details.paymentMethod === "card" ? "card" : "wallet"}`}>
                  {formatRs(details.totalAmount)}
                </Stat>
                <Stat label="Escrow" note={escrowNote[details.escrowStatus]}>
                  <EscrowBadge status={details.escrowStatus} />
                </Stat>
                <Stat
                  label="Fulfilment"
                  note={details.distanceKm != null ? `${details.distanceKm} km ridden` : null}
                >
                  {delivery ? "Home delivery" : "Self pickup"}
                </Stat>
                <Stat
                  label="Handover code"
                  note={details.handover.codeVerifiedAt ? formatDate(details.handover.codeVerifiedAt, true) : "Shown only on the customer's phone"}
                >
                  {details.handover.codeVerifiedAt ? (
                    <span className="text-emerald-700">Verified</span>
                  ) : (
                    <span className="text-on-surface-variant">Not used yet</span>
                  )}
                </Stat>
              </div>

              <div className="grid grid-cols-1 md:grid-cols-3 gap-3">
                <Party icon="person" role="Customer">
                  <p className="text-sm font-semibold text-on-surface truncate">{details.customerName}</p>
                  <p className="text-xs text-outline truncate">{details.customerEmail}</p>
                  <div className="mt-1"><MaskedPhone phone={details.customerPhone} /></div>
                </Party>
                <Party icon="storefront" role="Store">
                  <p className="text-sm font-semibold text-on-surface truncate">{details.storeName}</p>
                  <p className="text-xs text-outline line-clamp-2 mt-0.5">{details.storeAddress || "No address on file"}</p>
                </Party>
                <Party icon="two_wheeler" role="Rider">
                  {details.riderName ? (
                    <>
                      <p className="text-sm font-semibold text-on-surface truncate">{details.riderName}</p>
                      <div className="mt-0.5"><MaskedPhone phone={details.riderPhone} /></div>
                      {details.riderPayout > 0 && (
                        <p className="text-xs font-semibold text-emerald-700 mt-1">Payout {formatRs(details.riderPayout)}</p>
                      )}
                    </>
                  ) : (
                    <p className="text-xs text-outline mt-1">
                      {delivery ? "Not assigned yet" : "Not needed: collected at the counter"}
                    </p>
                  )}
                </Party>
              </div>

              {delivery && <HandoverEvidence details={details} />}

              {details.messages?.length > 0 && <ChatTranscript messages={details.messages} />}

              <div className="grid grid-cols-1 md:grid-cols-2 gap-3">
                <Timeline details={details} />
                <Settlement details={details} />
              </div>

              <div className="rounded-xl border border-outline-variant/30 overflow-hidden">
                <div className="px-4 py-2.5 bg-surface-container-low/50 border-b border-outline-variant/20">
                  <h4 className="text-xs font-bold uppercase tracking-wider text-outline">
                    Items ({details.items.length})
                  </h4>
                </div>
                <div className="divide-y divide-outline-variant/15">
                  {details.items.map((item) => (
                    <div key={item.id} className="p-3.5 flex items-center justify-between gap-4">
                      <div className="flex items-center gap-3 min-w-0">
                        {item.imageUrl ? (
                          // eslint-disable-next-line @next/next/no-img-element
                          <img
                            src={fileUrl(item.imageUrl)}
                            alt={item.name}
                            className="w-10 h-10 rounded-lg object-cover border border-outline-variant/30 shrink-0"
                          />
                        ) : (
                          <div className="w-10 h-10 rounded-lg bg-surface-container-low flex items-center justify-center shrink-0 text-outline">
                            <span className="material-symbols-outlined text-[20px]">inventory_2</span>
                          </div>
                        )}
                        <div className="min-w-0">
                          <p className="text-sm font-semibold text-on-surface truncate">{item.name}</p>
                          <p className="text-xs text-outline">
                            {formatRs(item.unitPrice)} × {item.quantity}
                            {item.barcode && <span className="font-mono ml-2">{item.barcode}</span>}
                          </p>
                        </div>
                      </div>
                      <p className="text-sm font-bold text-on-surface whitespace-nowrap tabular-nums">{formatRs(item.subtotal)}</p>
                    </div>
                  ))}
                </div>
              </div>
            </div>
          ) : null}
        </div>
      </div>
    </div>
  );
}

export default function OrdersPage() {
  const [orders, setOrders] = useState([]);
  const [loading, setLoading] = useState(true);
  const [search, setSearch] = useState("");
  const [selectedOrderId, setSelectedOrderId] = useState(null);
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
            <div key={status} className="bg-surface-container-lowest rounded-xl p-4 border border-outline-variant/20 shadow-sm">
              <div className="flex items-center justify-between">
                <span className="text-xs text-on-surface-variant font-medium">{config.label}</span>
                <span className={`w-2 h-2 rounded-full ${config.dot}`} />
              </div>
              <p className="text-2xl font-bold text-on-surface mt-2">{count}</p>
            </div>
          );
        })}
      </div>

      {/* Search */}
      <div className="mb-6 flex justify-end">
        <SearchBox
          value={search}
          onChange={setSearch}
          placeholder="Search order ID, customer, store or rider"
          count={filteredOrders.length}
          total={orders.length}
        />
      </div>

      {/* Orders Table */}
      <div className="bg-surface-container-lowest rounded-2xl border border-outline-variant/20 shadow-sm overflow-hidden">
        <div className="overflow-x-auto">
          <table className="w-full sticky-actions">
            <thead>
              <tr className="bg-surface-container-low/50 border-b border-outline-variant/20">
                <Th>Order ID</Th>
                <Th>Customer</Th>
                <Th>Store</Th>
                <Th align="center">Items</Th>
                <Th>Total</Th>
                <Th>Status</Th>
                <Th>Escrow</Th>
                <Th>Rider / Type</Th>
                <Th align="right">Action</Th>
              </tr>
            </thead>
            <tbody className="divide-y divide-outline-variant/10">
              {filteredOrders.map((order) => {
                const config = statusConfig[order.status] || statusConfig.confirmed;
                return (
                  <tr
                    key={order.id}
                    id={`order-${order.id}`}
                    className="hover:bg-surface-container-low/30 transition-colors"
                  >
                    <td className="px-4 py-3.5 whitespace-nowrap">
                      <button
                        onClick={() => setSelectedOrderId(order.id)}
                        className="text-sm font-bold text-primary hover:underline block text-left"
                      >
                        {formatOrderId(order.id)}
                      </button>
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
                    <td className="px-4 py-3.5 text-right whitespace-nowrap">
                      <button
                        onClick={() => setSelectedOrderId(order.id)}
                        className="text-xs font-semibold px-2.5 py-1.5 rounded-lg border border-outline-variant/40 hover:bg-surface-container-low text-on-surface-variant transition-colors inline-flex items-center gap-1"
                      >
                        <span className="material-symbols-outlined text-[15px]">visibility</span>
                        Inspect
                      </button>
                    </td>
                  </tr>
                );
              })}

              {filteredOrders.length === 0 && (
                <tr>
                  <td colSpan={9} className="text-center py-12 text-on-surface-variant">
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

      {/* Order Inspection Modal */}
      {selectedOrderId && (
        <OrderInspectionModal
          orderId={selectedOrderId}
          onClose={() => setSelectedOrderId(null)}
        />
      )}
    </div>
  );
}
