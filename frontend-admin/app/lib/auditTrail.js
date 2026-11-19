"use client";

// ══════════════════════════════════════════════════════════════
// Admin audit trail (GET /api/admin/audit-log): who approved a store,
// changed a policy or ruled on a dispute, and when. Append-only on the
// server, so this is a record, not something that can be edited.
// ══════════════════════════════════════════════════════════════

import { useState, useEffect } from "react";
import { useRouter } from "next/navigation";
import { getAuditLog, isAuthError } from "./api";
import { Spinner, LoadMore, formatDate, humanize } from "./ui";

const ICONS = {
  vendor_approved: "storefront", vendor_disapproved: "block", location_approved: "edit_location_alt",
  location_rejected: "wrong_location", product_approved: "inventory", product_hidden: "visibility_off",
  policy_changed: "tune", rider_approved: "two_wheeler", rider_rejected: "person_off",
  dispute_resolved: "gavel", password_reset: "key", escrow_settled: "schedule_send",
};

const PAGE = 20;

/** @param refreshKey bump to reload from the top (e.g. after saving policies) */
export default function AuditTrail({ refreshKey = 0 }) {
  const router = useRouter();
  const [action, setAction] = useState("");
  const [entries, setEntries] = useState([]);
  const [actions, setActions] = useState([]);
  const [meta, setMeta] = useState({ hasMore: false, nextOffset: null });
  const [loading, setLoading] = useState(true);
  const [loadingMore, setLoadingMore] = useState(false);
  const [error, setError] = useState(null);

  useEffect(() => {
    let cancelled = false;
    getAuditLog({ action: action || undefined, limit: PAGE })
      .then((res) => {
        if (cancelled) return;
        setEntries(res.data);
        setMeta(res.meta);
        setActions(res.meta.actions || []);
        setError(null);
      })
      .catch((err) => {
        if (isAuthError(err)) router.push("/");
        if (!cancelled) setError(err.message);
      })
      .finally(() => { if (!cancelled) setLoading(false); });
    return () => { cancelled = true; };
  }, [action, refreshKey, router]);

  async function loadMore() {
    setLoadingMore(true);
    try {
      const res = await getAuditLog({ action: action || undefined, limit: PAGE, offset: meta.nextOffset });
      setEntries((prev) => [...prev, ...res.data]);
      setMeta(res.meta);
    } catch (err) {
      setError(err.message);
    } finally {
      setLoadingMore(false);
    }
  }

  return (
    <div className="bg-surface-container-lowest rounded-2xl border border-outline-variant/20 shadow-sm p-6">
      <div className="flex flex-col sm:flex-row sm:items-start sm:justify-between gap-3 mb-4">
        <div>
          <div className="flex items-center gap-2">
            <span className="material-symbols-outlined text-primary text-[22px]">history</span>
            <h3 className="text-lg font-bold text-on-surface">Admin audit trail</h3>
          </div>
          <p className="text-sm text-on-surface-variant mt-1">Every approval, policy change, ruling and manual release. Entries can&apos;t be edited or deleted.</p>
        </div>
        <select
          value={action}
          onChange={(e) => { setLoading(true); setAction(e.target.value); }}
          aria-label="Filter by action"
          className="px-3 py-2 rounded-xl text-sm bg-surface-container-low border border-outline-variant/40 text-on-surface"
        >
          <option value="">All actions</option>
          {actions.map((a) => <option key={a} value={a}>{humanize(a)}</option>)}
        </select>
      </div>

      {loading ? (
        <div className="py-10 flex justify-center"><Spinner className="w-6 h-6" /></div>
      ) : error && entries.length === 0 ? (
        <p className="text-sm text-error">{error}</p>
      ) : entries.length === 0 ? (
        <p className="text-sm text-outline py-8 text-center">No admin actions recorded yet.</p>
      ) : (
        <>
          <ol className="relative border-l border-outline-variant/40 ml-3">
            {entries.map((e) => (
              <li key={e.id} className="ml-6 pb-4 last:pb-0">
                <span className="absolute -left-3.5 w-7 h-7 rounded-full bg-primary/10 flex items-center justify-center ring-4 ring-surface-container-lowest">
                  <span className="material-symbols-outlined text-[15px] text-primary">{ICONS[e.action] || "info"}</span>
                </span>
                <p className="text-sm text-on-surface">{e.summary}</p>
                <p className="text-xs text-outline mt-0.5">
                  {e.adminName || "Admin"} · {formatDate(e.createdAt, true)}
                  {e.ipAddress ? ` · ${e.ipAddress}` : ""}
                </p>
                {e.details?.reason && <p className="text-xs text-on-surface-variant mt-1">Reason: {e.details.reason}</p>}
                {e.details?.note && <p className="text-xs text-on-surface-variant mt-1">Note: {e.details.note}</p>}
              </li>
            ))}
          </ol>
          <LoadMore hasMore={meta.hasMore} loading={loadingMore} error={null} onClick={loadMore} shown={entries.length} />
        </>
      )}
    </div>
  );
}
