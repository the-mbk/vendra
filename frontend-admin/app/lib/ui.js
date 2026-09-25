"use client";

// ══════════════════════════════════════════════════════════════
// Vendra Admin Dashboard - Shared UI helpers
// Small building blocks reused by the dashboard pages
// ══════════════════════════════════════════════════════════════

/** Event fired after an admin action that changes sidebar badge counts */
export const COUNTS_EVENT = "vendra:counts-changed";

export function notifyCountsChanged() {
  if (typeof window !== "undefined") window.dispatchEvent(new Event(COUNTS_EVENT));
}

/** "Rs. 1,234" or "Rs. 849.90" — paisa amounts always show 2 decimals */
export function formatRs(value) {
  const n = Number(value) || 0;
  const decimals = Number.isInteger(n) ? 0 : 2;
  return `Rs. ${n.toLocaleString("en-PK", { minimumFractionDigits: decimals, maximumFractionDigits: 2 })}`;
}

export function formatDate(value, withTime = false) {
  if (!value) return "—";
  return new Date(value).toLocaleString("en-PK", {
    day: "numeric",
    month: "short",
    year: "numeric",
    ...(withTime && { hour: "numeric", minute: "2-digit" }),
  });
}

export function formatOrderId(id) {
  return `#VDR-${String(id).padStart(5, "0")}`;
}

/** "damaged_item" → "Damaged item" */
export function humanize(value) {
  if (!value) return "—";
  const s = String(value).replace(/_/g, " ");
  return s.charAt(0).toUpperCase() + s.slice(1);
}

export function Spinner({ className = "w-8 h-8", color = "text-primary" }) {
  return (
    <svg className={`animate-spin ${color} ${className}`} fill="none" viewBox="0 0 24 24">
      <circle className="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" strokeWidth="4" />
      <path className="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4z" />
    </svg>
  );
}

export function PageLoader({ label }) {
  return (
    <div className="flex items-center justify-center h-64">
      <div className="flex flex-col items-center gap-3">
        <Spinner />
        {label && <p className="text-sm text-outline">{label}</p>}
      </div>
    </div>
  );
}

export function ErrorBox({ title = "Something went wrong", message }) {
  return (
    <div className="bg-red-50 border border-red-200 text-red-700 p-4 rounded-xl">
      <p className="font-semibold">{title}</p>
      {message && <p className="text-sm mt-1">{message}</p>}
    </div>
  );
}

export const escrowConfig = {
  held: { label: "Held", color: "bg-amber-100 text-amber-700", dot: "bg-amber-500" },
  disputed: { label: "Disputed", color: "bg-red-100 text-red-700", dot: "bg-red-500" },
  released: { label: "Released", color: "bg-emerald-100 text-emerald-700", dot: "bg-emerald-500" },
  refunded: { label: "Refunded", color: "bg-blue-100 text-blue-700", dot: "bg-blue-500" },
};

export const orderStatusConfig = {
  pending: { label: "Pending", color: "bg-slate-100 text-slate-700", dot: "bg-slate-500" },
  confirmed: { label: "Confirmed", color: "bg-blue-100 text-blue-700", dot: "bg-blue-500" },
  packed: { label: "Packed", color: "bg-purple-100 text-purple-700", dot: "bg-purple-500" },
  ready_for_pickup: { label: "Ready", color: "bg-amber-100 text-amber-700", dot: "bg-amber-500" },
  picked: { label: "Picked Up", color: "bg-cyan-100 text-cyan-700", dot: "bg-cyan-500" },
  on_the_way: { label: "On the Way", color: "bg-orange-100 text-orange-700", dot: "bg-orange-500" },
  delivered: { label: "Delivered", color: "bg-emerald-100 text-emerald-700", dot: "bg-emerald-500" },
  cancelled: { label: "Cancelled", color: "bg-red-100 text-red-700", dot: "bg-red-500" },
};

/** Badge colours for the party that raised a dispute */
export const roleColors = {
  customer: "bg-emerald-100 text-emerald-700",
  vendor: "bg-blue-100 text-blue-700",
  rider: "bg-orange-100 text-orange-700",
};

/** Rounded status pill using one of the config maps above */
export function Pill({ config, fallback = "—" }) {
  if (!config) return <span className="text-xs text-outline">{fallback}</span>;
  return (
    <span className={`inline-flex items-center gap-1 px-2.5 py-1 rounded-full text-xs font-semibold whitespace-nowrap ${config.color}`}>
      <span className={`w-1.5 h-1.5 rounded-full ${config.dot}`} />
      {config.label}
    </span>
  );
}

export function EscrowBadge({ status }) {
  return <Pill config={escrowConfig[status]} fallback={status || "—"} />;
}

export function OrderStatusBadge({ status }) {
  return <Pill config={orderStatusConfig[status] || { ...orderStatusConfig.confirmed, label: humanize(status) }} />;
}

/** Shared table header cell */
export function Th({ children, align = "left" }) {
  return (
    <th className={`${align === "right" ? "text-right" : "text-left"} px-5 py-3.5 text-xs font-semibold text-on-surface-variant uppercase tracking-wider whitespace-nowrap`}>
      {children}
    </th>
  );
}

/** Filter tab button (same look as the vendors page tabs) */
export function TabButton({ active, onClick, children, count }) {
  return (
    <button
      onClick={onClick}
      className={`px-4 py-2 rounded-xl text-sm font-semibold transition-colors ${
        active
          ? "bg-primary text-white"
          : "bg-surface-container-low text-on-surface-variant hover:bg-surface-container"
      }`}
    >
      {children}
      {count > 0 && (
        <span
          className={`ml-2 px-1.5 py-0.5 rounded-full text-[11px] ${
            active ? "bg-white/20 text-white" : "bg-primary/10 text-primary"
          }`}
        >
          {count}
        </span>
      )}
    </button>
  );
}
