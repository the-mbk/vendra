"use client";

import { useState, useEffect } from "react";
import { useRouter } from "next/navigation";
import { getDisputes, isAuthError } from "../../lib/api";
import {
  PageLoader, ErrorBox, Th, TabButton, EscrowBadge, roleColors,
  formatRs, formatDate, formatOrderId, humanize,
} from "../../lib/ui";

function DisputeStatus({ dispute }) {
  if (dispute.status === "open") {
    return (
      <span className="inline-flex items-center gap-1 px-2.5 py-1 rounded-full text-xs font-semibold bg-red-100 text-red-700 whitespace-nowrap">
        <span className="w-1.5 h-1.5 rounded-full bg-red-500" />
        Open
      </span>
    );
  }
  const refund = dispute.resolution === "refund";
  return (
    <span
      className={`inline-flex items-center gap-1 px-2.5 py-1 rounded-full text-xs font-semibold whitespace-nowrap ${
        refund ? "bg-blue-100 text-blue-700" : "bg-emerald-100 text-emerald-700"
      }`}
    >
      <span className={`w-1.5 h-1.5 rounded-full ${refund ? "bg-blue-500" : "bg-emerald-500"}`} />
      Resolved · {refund ? "Refund" : "Release"}
    </span>
  );
}

export default function DisputesPage() {
  const [disputes, setDisputes] = useState([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(null);
  const [filter, setFilter] = useState("all"); // all, open, resolved
  const router = useRouter();

  useEffect(() => {
    const token = localStorage.getItem("vendra_admin_token");
    if (!token) { router.push("/"); return; }

    async function fetchDisputes() {
      try {
        // No status filter: the API returns open disputes first, newest first
        const res = await getDisputes();
        setDisputes(res.data);
      } catch (err) {
        if (isAuthError(err)) router.push("/");
        setError(err.message);
      } finally {
        setLoading(false);
      }
    }
    fetchDisputes();
  }, [router]);

  if (loading) return <PageLoader label="Loading disputes..." />;
  if (error) return <ErrorBox title="Error loading disputes" message={error} />;

  const openCount = disputes.filter((d) => d.status === "open").length;
  const resolvedCount = disputes.length - openCount;
  const heldInDisputes = disputes
    .filter((d) => d.status === "open")
    .reduce((sum, d) => sum + (Number(d.order?.heldAmount) || 0), 0);
  const filtered = filter === "all" ? disputes : disputes.filter((d) => d.status === filter);

  return (
    <div>
      {/* Header */}
      <div className="flex items-center justify-between mb-6">
        <div>
          <h1 className="text-2xl font-bold text-on-surface">Disputes</h1>
          <p className="text-on-surface-variant text-sm mt-1">
            {disputes.length} total • {openCount} open • {formatRs(heldInDisputes)} frozen in escrow
          </p>
        </div>
      </div>

      {openCount > 0 && (
        <div className="bg-red-50 border border-red-200 rounded-xl p-4 mb-6 flex items-center gap-3">
          <div className="w-10 h-10 bg-red-100 rounded-lg flex items-center justify-center shrink-0">
            <span className="material-symbols-outlined text-red-700 text-[22px]">gavel</span>
          </div>
          <div>
            <p className="text-sm font-semibold text-red-800">
              {openCount} dispute{openCount > 1 ? "s" : ""} waiting for a decision
            </p>
            <p className="text-xs text-red-600">
              Payment on these orders is frozen until you refund the customer or release it to the store.
            </p>
          </div>
          {filter !== "open" && (
            <button onClick={() => setFilter("open")} className="ml-auto text-sm font-semibold text-red-700 hover:underline">
              View Open →
            </button>
          )}
        </div>
      )}

      {/* Filter Tabs */}
      <div className="flex gap-2 mb-6">
        <TabButton active={filter === "all"} onClick={() => setFilter("all")}>All</TabButton>
        <TabButton active={filter === "open"} onClick={() => setFilter("open")} count={openCount}>Open</TabButton>
        <TabButton active={filter === "resolved"} onClick={() => setFilter("resolved")} count={resolvedCount}>Resolved</TabButton>
      </div>

      {/* Disputes Table */}
      <div className="bg-white rounded-2xl border border-outline-variant/20 shadow-sm overflow-hidden">
        <div className="overflow-x-auto">
          <table className="w-full">
            <thead>
              <tr className="bg-surface-container-low/50 border-b border-outline-variant/20">
                <Th>Dispute</Th>
                <Th>Issue</Th>
                <Th>Raised by</Th>
                <Th>Store / Customer</Th>
                <Th>Held</Th>
                <Th>Escrow</Th>
                <Th>Status</Th>
                <Th align="right">Action</Th>
              </tr>
            </thead>
            <tbody className="divide-y divide-outline-variant/10">
              {filtered.map((d) => (
                <tr
                  key={d.id}
                  onClick={() => router.push(`/dashboard/disputes/${d.id}`)}
                  className={`cursor-pointer hover:bg-surface-container-low/30 transition-colors ${
                    d.status === "open" ? "" : "opacity-80"
                  }`}
                >
                  <td className="px-5 py-4 whitespace-nowrap">
                    <p className="text-sm font-bold text-primary">#D-{String(d.id).padStart(4, "0")}</p>
                    <p className="text-xs text-outline">Order {formatOrderId(d.orderId)}</p>
                    <p className="text-[11px] text-outline">{formatDate(d.createdAt, true)}</p>
                  </td>
                  <td className="px-5 py-4 max-w-[260px]">
                    <p className="text-sm font-semibold text-on-surface">{humanize(d.issueType)}</p>
                    <p className="text-xs text-outline line-clamp-2">{d.description}</p>
                    {d.evidence?.length > 0 && (
                      <p className="text-[11px] text-on-surface-variant mt-1 flex items-center gap-1">
                        <span className="material-symbols-outlined text-[14px]">photo_library</span>
                        {d.evidence.length} photo{d.evidence.length > 1 ? "s" : ""}
                      </p>
                    )}
                  </td>
                  <td className="px-5 py-4 whitespace-nowrap">
                    <p className="text-sm text-on-surface">{d.raisedBy?.name}</p>
                    <span
                      className={`inline-block mt-0.5 px-2 py-0.5 rounded-full text-[11px] font-semibold ${
                        roleColors[d.raisedBy?.role] || "bg-surface-container-low text-on-surface-variant"
                      }`}
                    >
                      {humanize(d.raisedBy?.role)}
                    </span>
                  </td>
                  <td className="px-5 py-4 whitespace-nowrap">
                    <p className="text-sm text-on-surface">{d.order?.storeName}</p>
                    <p className="text-xs text-outline">{d.order?.customerName}</p>
                  </td>
                  <td className="px-5 py-4 text-sm font-semibold text-on-surface whitespace-nowrap">
                    {formatRs(d.order?.heldAmount)}
                  </td>
                  <td className="px-5 py-4"><EscrowBadge status={d.order?.escrowStatus} /></td>
                  <td className="px-5 py-4"><DisputeStatus dispute={d} /></td>
                  <td className="px-5 py-4 text-right whitespace-nowrap">
                    <span
                      className={`text-xs font-semibold px-3 py-1.5 rounded-lg ${
                        d.status === "open" ? "bg-primary text-white" : "bg-surface-container-low text-primary"
                      }`}
                    >
                      {d.status === "open" ? "Review" : "View"}
                    </span>
                  </td>
                </tr>
              ))}

              {filtered.length === 0 && (
                <tr>
                  <td colSpan={8} className="text-center py-12 text-on-surface-variant">
                    <span className="material-symbols-outlined text-[48px] text-outline-variant block mb-2">
                      {filter === "open" ? "task_alt" : "inbox"}
                    </span>
                    {filter === "open" ? "No open disputes. All clear." : "No disputes found for this filter."}
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
