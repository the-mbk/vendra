"use client";

// ══════════════════════════════════════════════════════════════
// Vendra Admin Dashboard - Shared UI helpers
// Small building blocks reused by the dashboard pages
// ══════════════════════════════════════════════════════════════

import { useState } from "react";

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

/** "3,631" — plain counts with thousands separators */
export function formatNumber(value) {
  return (Number(value) || 0).toLocaleString("en-PK");
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
  admin: "bg-purple-100 text-purple-700",
};

/** Card payment statuses (GET /api/admin/payments) */
export const paymentStatusConfig = {
  succeeded: { label: "Succeeded", color: "bg-emerald-100 text-emerald-700", dot: "bg-emerald-500" },
  processing: { label: "Processing", color: "bg-slate-100 text-slate-700", dot: "bg-slate-500" },
  requires_action: { label: "Awaiting OTP", color: "bg-amber-100 text-amber-700", dot: "bg-amber-500" },
  failed: { label: "Failed", color: "bg-red-100 text-red-700", dot: "bg-red-500" },
  canceled: { label: "Canceled", color: "bg-slate-100 text-slate-500", dot: "bg-slate-400" },
};

/** Withdrawal (card payout) statuses (GET /api/admin/withdrawals) */
export const withdrawalStatusConfig = {
  pending: { label: "Queued", color: "bg-slate-100 text-slate-700", dot: "bg-slate-500" },
  in_transit: { label: "In transit", color: "bg-blue-100 text-blue-700", dot: "bg-blue-500" },
  paid: { label: "Paid", color: "bg-emerald-100 text-emerald-700", dot: "bg-emerald-500" },
  failed: { label: "Failed · returned", color: "bg-red-100 text-red-700", dot: "bg-red-500" },
};

/** "Visa •••• 4242" */
export function CardLabel({ card }) {
  if (!card?.last4) return <span className="text-xs text-outline">—</span>;
  return (
    <span className="inline-flex items-center gap-1.5 text-sm text-on-surface whitespace-nowrap">
      <span className="material-symbols-outlined text-[16px] text-outline">credit_card</span>
      <span className="font-medium">{humanize(card.brand)}</span>
      <span className="font-mono text-on-surface-variant">•••• {card.last4}</span>
    </span>
  );
}

/** Name, email and role of the user on a payment or withdrawal */
export function UserCell({ user }) {
  if (!user) return <span className="text-xs text-outline">—</span>;
  return (
    <div className="min-w-0">
      <div className="flex items-center gap-1.5">
        <p className="text-sm font-medium text-on-surface truncate">{user.name}</p>
        {user.role && (
          <span
            className={`px-1.5 py-0.5 rounded text-[10px] font-semibold uppercase tracking-wide ${
              roleColors[user.role] || "bg-surface-container-low text-on-surface-variant"
            }`}
          >
            {user.role}
          </span>
        )}
      </div>
      <p className="text-xs text-outline truncate">{user.email}</p>
    </div>
  );
}

/** Monospace gateway id (pi_…, po_…) with a copy button */
export function CopyId({ value }) {
  const [copied, setCopied] = useState(false);
  if (!value) return <span className="text-xs text-outline">—</span>;

  function handleCopy() {
    navigator.clipboard?.writeText(value).then(
      () => {
        setCopied(true);
        setTimeout(() => setCopied(false), 1500);
      },
      () => {}
    );
  }

  return (
    <span className="inline-flex items-center gap-1 whitespace-nowrap">
      <code className="text-xs font-mono bg-surface-container-low text-on-surface-variant px-1.5 py-0.5 rounded select-all">
        {value}
      </code>
      <button
        type="button"
        onClick={handleCopy}
        title={copied ? "Copied" : "Copy"}
        aria-label={`Copy ${value}`}
        className={`material-symbols-outlined text-[16px] p-0.5 rounded hover:bg-surface-container-low transition-colors ${
          copied ? "text-emerald-600" : "text-outline hover:text-on-surface"
        }`}
      >
        {copied ? "check" : "content_copy"}
      </button>
    </span>
  );
}

/** "Load more" footer for paged tables */
export function LoadMore({ hasMore, loading, error, onClick, shown }) {
  if (!hasMore && !error) {
    return shown > 0 ? (
      <p className="text-center text-xs text-outline py-4">
        Showing all {shown} entr{shown === 1 ? "y" : "ies"}
      </p>
    ) : null;
  }
  return (
    <div className="flex flex-col items-center gap-2 py-4">
      {error && <p className="text-xs text-error">{error}</p>}
      {hasMore && (
        <button
          onClick={onClick}
          disabled={loading}
          className="px-4 py-2 rounded-xl text-sm font-semibold text-primary bg-primary/5 hover:bg-primary/10 transition-colors disabled:opacity-50 flex items-center gap-2"
        >
          {loading && <Spinner className="w-4 h-4" />}
          {loading ? "Loading..." : `Load more (${shown} shown)`}
        </button>
      )}
    </div>
  );
}

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
export function Th({ children, align = "left", className = "" }) {
  const alignClass = align === "right" ? "text-right" : align === "center" ? "text-center" : "text-left";
  return (
    <th className={`${alignClass} ${className} px-4 py-3 text-xs font-semibold text-on-surface-variant uppercase tracking-wider whitespace-nowrap`}>
      {children}
    </th>
  );
}

// ── Search ──

/** True when `query` (trimmed, case-insensitive) appears in any of the fields. Empty query matches everything. */
export function matchesSearch(query, ...fields) {
  const q = String(query ?? "").trim().toLowerCase();
  if (!q) return true;
  return fields.some((f) => f != null && f !== "" && String(f).toLowerCase().includes(q));
}

/**
 * Does `query` refer to this numbered record? Accepts "3630", "#3630", "VDR-03630", "#VDR-03630"
 * (any letter prefix, '#' and leading zeros are ignored) or part of the formatted id, e.g. "#VDR-036".
 * As-you-type friendly: "363" also matches 3630.
 */
export function matchesId(query, id, formatted) {
  const q = String(query ?? "").trim().toLowerCase();
  if (!q) return true;
  if (id == null) return false;
  const label = String(formatted || "").toLowerCase();
  // No digits yet ("#VDR-", "vdr"): only a prefix of the formatted id counts, so "d" alone doesn't match everything
  if (!/\d/.test(q)) return label !== "" && (label.startsWith(q) || label.replace(/^#/, "").startsWith(q));
  if (label.includes(q)) return true;
  const digits = q.replace(/^#?\s*(?:[a-z]+-?)?\s*0*/, "");
  return /^\d+$/.test(digits) && String(id).startsWith(digits);
}

/**
 * Search input with an icon and a clear (×) button; Escape clears it.
 * Pass `count` and `total` to show "3 of 20" while a search is active.
 */
export function SearchBox({ value, onChange, placeholder = "Search", count, total, className = "" }) {
  const active = value.length > 0;
  return (
    <div className={`flex items-center gap-3 ${className}`}>
      {active && count != null && total != null && (
        <span className="text-xs text-outline whitespace-nowrap">
          {count} of {total}
        </span>
      )}
      <div className="relative flex-1 min-w-0 sm:w-96 sm:flex-none">
        <span className="material-symbols-outlined absolute left-3 top-1/2 -translate-y-1/2 text-[20px] text-outline pointer-events-none">
          search
        </span>
        <input
          type="search"
          value={value}
          onChange={(e) => onChange(e.target.value)}
          onKeyDown={(e) => {
            if (e.key === "Escape" && active) {
              e.preventDefault();
              onChange("");
            }
          }}
          placeholder={placeholder}
          aria-label={placeholder}
          className="w-full pl-10 pr-9 py-2 bg-white border border-outline-variant/50 rounded-xl text-sm text-on-surface text-ellipsis placeholder:text-outline focus:outline-none focus:ring-2 focus:ring-primary/30 focus:border-primary transition-all [&::-webkit-search-cancel-button]:hidden"
        />
        {active && (
          <button
            type="button"
            onClick={() => onChange("")}
            title="Clear search"
            aria-label="Clear search"
            className="material-symbols-outlined absolute right-2 top-1/2 -translate-y-1/2 text-[18px] p-0.5 rounded-full text-outline hover:text-on-surface hover:bg-surface-container-low transition-colors"
          >
            close
          </button>
        )}
      </div>
    </div>
  );
}

/** Empty-table message for a search that matched nothing (put it inside the table's empty <td>) */
export function NoSearchResults({ query, onClear }) {
  return (
    <>
      <span className="material-symbols-outlined text-[48px] text-outline-variant block mb-2">search_off</span>
      <p>No results for &ldquo;{query.trim()}&rdquo;</p>
      <button
        type="button"
        onClick={onClear}
        className="mt-3 text-xs font-semibold px-3 py-1.5 rounded-lg bg-primary/5 text-primary hover:bg-primary/10 transition-colors"
      >
        Clear search
      </button>
    </>
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
