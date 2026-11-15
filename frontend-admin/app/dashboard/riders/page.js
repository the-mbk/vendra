"use client";

import { useState, useEffect } from "react";
import { useRouter } from "next/navigation";
import { getRiders, approveRider, rejectRider, isAuthError } from "../../lib/api";
import {
  PageLoader, ErrorBox, Th, TabButton, SearchBox, NoSearchResults, Spinner, notifyCountsChanged,
  formatRs, formatNumber, formatDate, formatOrderId, humanize, matchesSearch,
} from "../../lib/ui";

const vehicleIcons = {
  motorbike: "two_wheeler",
  motorcycle: "two_wheeler",
  scooter: "moped",
  bicycle: "pedal_bike",
  car: "directions_car",
  rickshaw: "electric_rickshaw",
};

const REJECT_REASON_MAX = 300;

const approvalConfig = {
  pending: { label: "Awaiting review", cls: "bg-amber-100 text-amber-800", icon: "hourglass_top" },
  approved: { label: "Approved", cls: "bg-emerald-100 text-emerald-700", icon: "verified" },
  rejected: { label: "Sent back", cls: "bg-red-100 text-red-700", icon: "block" },
};

function ApprovalBadge({ status }) {
  const c = approvalConfig[status] || approvalConfig.approved;
  return (
    <span className={`inline-flex items-center gap-1 px-2.5 py-1 rounded-full text-xs font-semibold whitespace-nowrap ${c.cls}`}>
      <span className="material-symbols-outlined text-[14px]">{c.icon}</span>
      {c.label}
    </span>
  );
}

function DocRow({ label, value }) {
  return (
    <div className="flex items-center justify-between gap-4 py-2.5 border-b border-outline-variant/15 last:border-0">
      <span className="text-sm text-on-surface-variant">{label}</span>
      <span className="text-sm font-semibold text-on-surface font-mono text-right">{value || "—"}</span>
    </div>
  );
}

/** Check a rider's CNIC, licence and vehicle, then approve or send back with a reason */
function RiderReviewModal({ rider, onClose, onDone }) {
  const [rejecting, setRejecting] = useState(false);
  const [reason, setReason] = useState("");
  const [submitting, setSubmitting] = useState(null); // "approve" | "reject" | null
  const [error, setError] = useState(null);
  const busy = submitting !== null;

  useEffect(() => {
    function onKey(e) {
      if (e.key === "Escape" && !submitting) onClose();
    }
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [onClose, submitting]);

  async function run(kind) {
    setSubmitting(kind);
    setError(null);
    try {
      const res = kind === "approve" ? await approveRider(rider.id) : await rejectRider(rider.id, reason.trim());
      onDone({ type: "success", text: res.message || (kind === "approve" ? "Rider approved." : "Rider sent back.") });
    } catch (err) {
      setError(err.message);
      setSubmitting(null);
    }
  }

  const bicycle = rider.vehicleType === "bicycle";

  return (
    <div className="fixed inset-0 z-50 bg-black/50 flex items-center justify-center p-6" onClick={() => { if (!busy) onClose(); }}>
      <div
        role="dialog"
        aria-modal="true"
        aria-labelledby="rider-review-title"
        className="bg-white rounded-2xl shadow-xl w-full max-w-lg max-h-[90vh] overflow-y-auto"
        onClick={(e) => e.stopPropagation()}
      >
        <div className="flex items-start gap-3 px-6 py-5 border-b border-outline-variant/20">
          <div className="w-10 h-10 bg-amber-100 rounded-lg flex items-center justify-center shrink-0">
            <span className="material-symbols-outlined text-amber-800 text-[22px]">badge</span>
          </div>
          <div className="flex-1 min-w-0">
            <h3 id="rider-review-title" className="text-lg font-bold text-on-surface">Review rider documents</h3>
            <p className="text-sm text-on-surface-variant truncate">{rider.fullName} · {rider.phone || rider.email}</p>
          </div>
          <button
            onClick={onClose}
            disabled={busy}
            aria-label="Close"
            className="material-symbols-outlined text-[22px] p-1 rounded-lg text-outline hover:text-on-surface hover:bg-surface-container-low transition-colors disabled:opacity-40"
          >
            close
          </button>
        </div>

        <div className="px-6 py-5">
          <div className="flex flex-wrap items-center gap-2 mb-4">
            <ApprovalBadge status={rider.approvalStatus} />
            <span className="inline-flex items-center gap-1 text-xs text-outline">
              <span className="material-symbols-outlined text-[14px]">schedule</span>
              Signed up {formatDate(rider.createdAt, true)}
            </span>
          </div>

          <div className="rounded-xl border border-outline-variant/30 px-4 mb-4">
            <DocRow label="CNIC" value={rider.cnic} />
            <DocRow label="Vehicle" value={humanize(rider.vehicleType)} />
            <DocRow label="Driving licence" value={bicycle ? "Not needed (bicycle)" : rider.licenseNumber} />
            <DocRow label="Registration number" value={bicycle ? "Not needed (bicycle)" : rider.vehicleNumber} />
          </div>
          <p className="text-xs text-outline mb-4">
            Check the numbers against the rider&apos;s CNIC card and licence (e.g. on a video call or at the office) before approving.
          </p>

          {rider.approvalStatus === "rejected" && rider.rejectionReason && (
            <div className="bg-red-50 border border-red-200 text-red-700 px-4 py-3 rounded-xl mb-4 text-sm">
              <span className="font-semibold">Last sent back:</span> {rider.rejectionReason}
            </div>
          )}

          {error && (
            <div className="bg-red-50 border border-red-200 text-red-700 px-4 py-3 rounded-xl mb-4 text-sm flex items-center gap-2">
              <span className="material-symbols-outlined text-[18px]">error</span>
              {error}
            </div>
          )}

          {rejecting ? (
            <div className="rounded-xl border border-red-200 bg-red-50/50 p-4">
              <label htmlFor="rider-reject-reason" className="block text-sm font-semibold text-on-surface mb-1.5">
                What should the rider fix? <span className="font-normal text-outline">(sent to the rider)</span>
              </label>
              <textarea
                id="rider-reject-reason"
                value={reason}
                onChange={(e) => setReason(e.target.value)}
                disabled={busy}
                rows={3}
                maxLength={REJECT_REASON_MAX}
                autoFocus
                placeholder="e.g. The licence number doesn't match the CNIC holder's name."
                className="w-full px-4 py-3 bg-white border border-outline-variant/50 rounded-xl text-sm text-on-surface placeholder:text-outline focus:outline-none focus:ring-2 focus:ring-primary/30 focus:border-primary transition-all disabled:opacity-60"
              />
              <p className="text-[11px] text-outline mt-1 mb-3 text-right">{reason.length}/{REJECT_REASON_MAX}</p>
              <div className="flex gap-2">
                <button
                  onClick={() => { setRejecting(false); setError(null); }}
                  disabled={busy}
                  className="flex-1 py-2.5 rounded-xl text-sm font-semibold text-on-surface-variant bg-white border border-outline-variant/50 hover:bg-surface-container-low transition-colors disabled:opacity-50"
                >
                  Back
                </button>
                <button
                  onClick={() => run("reject")}
                  disabled={busy || !reason.trim()}
                  className="flex-1 py-2.5 rounded-xl text-sm font-semibold text-white bg-red-600 hover:bg-red-700 transition-colors disabled:opacity-50 disabled:cursor-not-allowed flex items-center justify-center gap-2"
                >
                  {submitting === "reject" && <Spinner className="w-4 h-4" color="text-white" />}
                  {submitting === "reject" ? "Sending..." : "Send back"}
                </button>
              </div>
            </div>
          ) : (
            <div className="flex gap-2">
              <button
                onClick={() => { setRejecting(true); setError(null); }}
                disabled={busy || rider.activeOrderId}
                title={rider.activeOrderId ? "The rider is on a delivery" : undefined}
                className="flex-1 py-2.5 rounded-xl text-sm font-semibold bg-red-50 text-red-700 hover:bg-red-100 transition-colors disabled:opacity-50 flex items-center justify-center gap-2"
              >
                <span className="material-symbols-outlined text-[18px]">close</span>
                {rider.approvalStatus === "approved" ? "Suspend" : "Send back"}
              </button>
              {rider.approvalStatus !== "approved" && (
                <button
                  onClick={() => run("approve")}
                  disabled={busy || !rider.cnic}
                  className="flex-1 py-2.5 rounded-xl text-sm font-semibold text-white bg-emerald-600 hover:bg-emerald-700 transition-colors disabled:opacity-50 disabled:cursor-not-allowed flex items-center justify-center gap-2"
                >
                  {submitting === "approve" ? <Spinner className="w-4 h-4" color="text-white" /> : <span className="material-symbols-outlined text-[18px]">check</span>}
                  {submitting === "approve" ? "Approving..." : "Approve rider"}
                </button>
              )}
            </div>
          )}
        </div>
      </div>

      {reviewing && <RiderReviewModal rider={reviewing} onClose={() => setReviewing(null)} onDone={onReviewed} />}
    </div>
  );
}

function OnlineBadge({ online }) {
  return (
    <span
      className={`inline-flex items-center gap-1 px-2.5 py-1 rounded-full text-xs font-semibold whitespace-nowrap ${
        online ? "bg-emerald-100 text-emerald-700" : "bg-slate-100 text-slate-600"
      }`}
    >
      <span className={`w-1.5 h-1.5 rounded-full ${online ? "bg-emerald-500 animate-pulse" : "bg-slate-400"}`} />
      {online ? "Online" : "Offline"}
    </span>
  );
}

export default function RidersPage() {
  const [riders, setRiders] = useState([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(null);
  const [filter, setFilter] = useState("all"); // all, pending, online, busy
  const [search, setSearch] = useState("");
  const [reviewing, setReviewing] = useState(null);
  const [notice, setNotice] = useState(null);
  const [reloadKey, setReloadKey] = useState(0);
  const router = useRouter();

  useEffect(() => {
    const token = localStorage.getItem("vendra_admin_token");
    if (!token) { router.push("/"); return; }

    async function fetchRiders() {
      try {
        const res = await getRiders();
        setRiders(res.data);
      } catch (err) {
        if (isAuthError(err)) router.push("/");
        setError(err.message);
      } finally {
        setLoading(false);
      }
    }
    fetchRiders();
  }, [router, reloadKey]);

  function onReviewed(message) {
    setReviewing(null);
    setNotice(message);
    setReloadKey((k) => k + 1);
    notifyCountsChanged();
  }

  if (loading) return <PageLoader label="Loading riders..." />;
  if (error) return <ErrorBox title="Error loading riders" message={error} />;

  const pendingCount = riders.filter((r) => r.approvalStatus === "pending").length;
  const onlineCount = riders.filter((r) => r.isOnline).length;
  const busyCount = riders.filter((r) => r.activeOrderId).length;
  const totalDeliveries = riders.reduce((sum, r) => sum + (Number(r.deliveries) || 0), 0);
  const totalEarnings = riders.reduce((sum, r) => sum + (Number(r.earnings) || 0), 0);

  const tabRiders = riders.filter((r) => {
    if (filter === "pending") return r.approvalStatus === "pending" || r.approvalStatus === "rejected";
    if (filter === "online") return r.isOnline;
    if (filter === "busy") return r.activeOrderId;
    return true;
  });
  const filtered = tabRiders.filter((r) => matchesSearch(search, r.fullName, r.email, r.phone, r.cnic, r.vehicleNumber));

  const summary = [
    { label: "Registered", value: formatNumber(riders.length), sub: pendingCount ? `${pendingCount} awaiting document review` : undefined, icon: "badge", color: "text-primary" },
    { label: "Online now", value: onlineCount, icon: "wifi_tethering", color: "text-emerald-700" },
    { label: "On a delivery", value: busyCount, icon: "local_shipping", color: "text-orange-700" },
    { label: "Deliveries / paid", value: formatNumber(totalDeliveries), sub: `${formatRs(totalEarnings)} paid to riders`, icon: "payments", color: "text-blue-700" },
  ];

  return (
    <div>
      {/* Header */}
      <div className="flex items-center justify-between mb-6">
        <div>
          <h1 className="text-2xl font-bold text-on-surface">Riders</h1>
          <p className="text-on-surface-variant text-sm mt-1">
            {formatNumber(riders.length)} riders • {onlineCount} online • {busyCount} on an active delivery
          </p>
        </div>
      </div>

      {notice && (
        <div
          className={`px-4 py-3 rounded-xl mb-4 text-sm flex items-center gap-2 border ${
            notice.type === "success" ? "bg-emerald-50 border-emerald-200 text-emerald-800" : "bg-red-50 border-red-200 text-red-700"
          }`}
        >
          <span className="material-symbols-outlined text-[18px]">{notice.type === "success" ? "check_circle" : "error"}</span>
          <span className="flex-1">{notice.text}</span>
          <button onClick={() => setNotice(null)} aria-label="Dismiss" className="material-symbols-outlined text-[18px] opacity-70 hover:opacity-100">close</button>
        </div>
      )}

      {/* Summary Cards */}
      <div className="grid grid-cols-2 md:grid-cols-4 gap-4 mb-6">
        {summary.map((s) => (
          <div key={s.label} className="bg-white rounded-xl p-4 border border-outline-variant/20">
            <div className="flex items-center gap-2 mb-2">
              <span className={`material-symbols-outlined text-[20px] ${s.color}`}>{s.icon}</span>
              <span className="text-xs font-semibold text-on-surface-variant uppercase">{s.label}</span>
            </div>
            <p className="text-2xl font-bold text-on-surface">{s.value}</p>
            {s.sub && <p className="text-xs text-outline mt-0.5">{s.sub}</p>}
          </div>
        ))}
      </div>

      {/* Filter Tabs + Search */}
      <div className="flex flex-wrap items-center justify-between gap-3 mb-6">
        <div className="flex gap-2">
          <TabButton active={filter === "all"} onClick={() => setFilter("all")}>All</TabButton>
          <TabButton active={filter === "pending"} onClick={() => setFilter("pending")} count={pendingCount}>Awaiting review</TabButton>
          <TabButton active={filter === "online"} onClick={() => setFilter("online")} count={onlineCount}>Online</TabButton>
          <TabButton active={filter === "busy"} onClick={() => setFilter("busy")} count={busyCount}>On delivery</TabButton>
        </div>
        <SearchBox
          value={search}
          onChange={setSearch}
          placeholder="Search name, email, phone, CNIC or plate"
          count={filtered.length}
          total={tabRiders.length}
        />
      </div>

      {/* Riders Table */}
      <div className="bg-white rounded-2xl border border-outline-variant/20 shadow-sm overflow-hidden">
        <div className="overflow-x-auto">
          <table className="w-full">
            <thead>
              <tr className="bg-surface-container-low/50 border-b border-outline-variant/20">
                <Th>Rider</Th>
                <Th>Documents</Th>
                <Th>Status</Th>
                <Th>Vehicle</Th>
                <Th align="right">Deliveries</Th>
                <Th align="right">Earnings</Th>
                <Th align="right">Wallet</Th>
                <Th>Active order</Th>
                <Th>Last location</Th>
              </tr>
            </thead>
            <tbody className="divide-y divide-outline-variant/10">
              {filtered.map((rider) => (
                <tr key={rider.id} className="hover:bg-surface-container-low/30 transition-colors">
                  <td className="px-4 py-3.5 max-w-[250px]">
                    <div className="flex items-center gap-3 min-w-0">
                      <div className="w-10 h-10 bg-orange-100 rounded-full flex items-center justify-center shrink-0">
                        <span className="text-secondary font-bold text-sm">
                          {(rider.fullName || "?").split(" ").map((n) => n[0]).join("").slice(0, 2).toUpperCase()}
                        </span>
                      </div>
                      <div className="min-w-0">
                        <p className="text-sm font-semibold text-on-surface truncate">{rider.fullName}</p>
                        <p className="text-xs text-outline truncate" title={rider.email}>{rider.email}</p>
                        <p className="text-xs text-outline">{rider.phone || "—"}</p>
                      </div>
                    </div>
                  </td>
                  <td className="px-4 py-3.5">
                    <button
                      onClick={() => setReviewing(rider)}
                      className="flex flex-col items-start gap-1 text-left group"
                      title="Review documents"
                    >
                      <ApprovalBadge status={rider.approvalStatus} />
                      <span className="text-xs text-outline font-mono group-hover:text-primary">{rider.cnic || "No CNIC on file"}</span>
                    </button>
                  </td>
                  <td className="px-4 py-3.5"><OnlineBadge online={rider.isOnline} /></td>
                  <td className="px-4 py-3.5">
                    <span className="inline-flex items-center gap-1.5 text-sm text-on-surface whitespace-nowrap">
                      <span className="material-symbols-outlined text-[18px] text-on-surface-variant">
                        {vehicleIcons[rider.vehicleType] || "two_wheeler"}
                      </span>
                      {humanize(rider.vehicleType)}
                    </span>
                    {rider.vehicleNumber && <p className="text-xs text-outline font-mono mt-0.5">{rider.vehicleNumber}</p>}
                    {rider.averageRating != null && (
                      <p className="text-xs text-amber-700 mt-0.5 inline-flex items-center gap-0.5">
                        <span className="material-symbols-outlined text-[14px]">star</span>
                        {Number(rider.averageRating).toFixed(1)}
                      </p>
                    )}
                  </td>
                  <td className="px-4 py-3.5 text-sm text-on-surface font-medium text-right tabular-nums">{rider.deliveries || 0}</td>
                  <td className="px-4 py-3.5 text-sm font-semibold text-on-surface text-right whitespace-nowrap tabular-nums">{formatRs(rider.earnings)}</td>
                  <td className="px-4 py-3.5 text-sm text-on-surface text-right whitespace-nowrap tabular-nums">{formatRs(rider.walletBalance)}</td>
                  <td className="px-4 py-3.5">
                    {rider.activeOrderId ? (
                      <span className="inline-flex items-center gap-1 px-2.5 py-1 rounded-full text-xs font-semibold bg-orange-100 text-orange-700 whitespace-nowrap">
                        <span className="material-symbols-outlined text-[14px]">local_shipping</span>
                        {formatOrderId(rider.activeOrderId)}
                      </span>
                    ) : (
                      <span className="text-xs text-outline">Idle</span>
                    )}
                  </td>
                  <td className="px-4 py-3.5 text-xs text-outline min-w-[104px]">
                    {formatDate(rider.lastLocationAt, true)}
                  </td>
                </tr>
              ))}

              {filtered.length === 0 && (
                <tr>
                  <td colSpan={9} className="text-center py-12 text-on-surface-variant">
                    {tabRiders.length > 0 ? (
                      <NoSearchResults query={search} onClear={() => setSearch("")} />
                    ) : (
                      <>
                        <span className="material-symbols-outlined text-[48px] text-outline-variant block mb-2">two_wheeler</span>
                        {riders.length === 0 ? "No riders have signed up yet." : "No riders match this filter."}
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
