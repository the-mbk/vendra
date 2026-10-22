"use client";

import { useState, useEffect } from "react";
import { useRouter } from "next/navigation";
import {
  getVendors, approveVendor, disapproveVendor, approveVendorLocation, rejectVendorLocation, isAuthError,
} from "../../lib/api";
import {
  notifyCountsChanged, matchesSearch, SearchBox, NoSearchResults, TabButton, Spinner, formatDate, formatRs, Th,
} from "../../lib/ui";

const tabs = [
  { key: "all", label: "All" },
  { key: "pending", label: "Pending" },
  { key: "approved", label: "Approved" },
  { key: "location", label: "Location requests" },
];

const REJECT_REASON_MAX = 300;

function hasCoords(lat, lng) {
  return lat != null && lng != null && Number.isFinite(Number(lat)) && Number.isFinite(Number(lng));
}

function formatCoords(lat, lng) {
  return `${Number(lat).toFixed(5)}, ${Number(lng).toFixed(5)}`;
}

function mapUrl(lat, lng) {
  return `https://www.openstreetmap.org/?mlat=${lat}&mlon=${lng}#map=17/${lat}/${lng}`;
}

function LocationChangeBadge() {
  return (
    <span className="inline-flex items-center gap-1 px-2.5 py-1 rounded-full text-xs font-semibold whitespace-nowrap bg-blue-100 text-blue-700">
      <span className="material-symbols-outlined text-[14px]">edit_location_alt</span>
      Location change
    </span>
  );
}

/** One side of the current-vs-requested comparison */
function LocationCard({ title, icon, tone, lat, lng, address, emptyText }) {
  const located = hasCoords(lat, lng);
  return (
    <div className={`flex-1 min-w-0 rounded-xl border p-4 ${tone}`}>
      <div className="flex items-center gap-2 mb-2">
        <span className="material-symbols-outlined text-[18px]">{icon}</span>
        <p className="text-xs font-semibold uppercase tracking-wider">{title}</p>
      </div>
      {located ? (
        <>
          <p className="text-sm font-mono font-semibold text-on-surface">{formatCoords(lat, lng)}</p>
          <p className="text-xs text-on-surface-variant mt-1 break-words">{address || "No address given"}</p>
          <a
            href={mapUrl(lat, lng)}
            target="_blank"
            rel="noopener noreferrer"
            className="inline-flex items-center gap-1 mt-3 text-xs font-semibold text-primary hover:underline"
          >
            <span className="material-symbols-outlined text-[16px]">map</span>
            View on map
            <span className="material-symbols-outlined text-[14px]">open_in_new</span>
          </a>
        </>
      ) : (
        <>
          <p className="text-sm text-outline">{emptyText}</p>
          {address && <p className="text-xs text-on-surface-variant mt-1 break-words">{address}</p>}
        </>
      )}
    </div>
  );
}

/** Approve or reject (with a reason) a vendor's requested store location */
function LocationReviewModal({ vendor, onClose, onDone }) {
  const pending = vendor.pendingLocation;
  const [rejecting, setRejecting] = useState(false);
  const [reason, setReason] = useState("");
  const [submitting, setSubmitting] = useState(null); // "approve" | "reject" | null
  const [error, setError] = useState(null);

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
      const res =
        kind === "approve"
          ? await approveVendorLocation(vendor.id)
          : await rejectVendorLocation(vendor.id, reason.trim());
      onDone({
        type: "success",
        text:
          res.message ||
          (kind === "approve"
            ? `"${vendor.storeName}" moved to its new location.`
            : `Location change for "${vendor.storeName}" rejected.`),
      });
    } catch (err) {
      if (err.status === 409) {
        // Already handled elsewhere (or withdrawn): close and refresh the list
        onDone({ type: "error", text: err.message || "This location request is no longer pending." });
        return;
      }
      setError(err.message);
      setSubmitting(null);
    }
  }

  const reasonText = reason.trim();
  const busy = submitting !== null;

  return (
    <div
      className="fixed inset-0 z-50 bg-black/50 flex items-center justify-center p-6"
      onClick={() => { if (!busy) onClose(); }}
    >
      <div
        role="dialog"
        aria-modal="true"
        aria-labelledby="location-review-title"
        className="bg-white rounded-2xl shadow-xl w-full max-w-2xl max-h-[90vh] overflow-y-auto"
        onClick={(e) => e.stopPropagation()}
      >
        {/* Header */}
        <div className="flex items-start gap-3 px-6 py-5 border-b border-outline-variant/20">
          <div className="w-10 h-10 bg-blue-100 rounded-lg flex items-center justify-center shrink-0">
            <span className="material-symbols-outlined text-blue-700 text-[22px]">edit_location_alt</span>
          </div>
          <div className="flex-1 min-w-0">
            <h3 id="location-review-title" className="text-lg font-bold text-on-surface">Review location change</h3>
            <p className="text-sm text-on-surface-variant truncate">{vendor.storeName}</p>
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
          {/* Summary */}
          <div className="flex flex-wrap items-center gap-2 mb-4">
            <span className="inline-flex items-center gap-1 px-2.5 py-1 rounded-full text-xs font-semibold bg-blue-100 text-blue-700">
              <span className="material-symbols-outlined text-[14px]">straighten</span>
              {pending.movedKm == null ? "First location" : `Moved ${Number(pending.movedKm).toLocaleString("en-PK")} km`}
            </span>
            <span className="inline-flex items-center gap-1 text-xs text-outline">
              <span className="material-symbols-outlined text-[14px]">schedule</span>
              Requested {formatDate(pending.requestedAt, true)}
            </span>
          </div>

          {/* Current vs requested */}
          <div className="flex flex-col md:flex-row md:items-stretch gap-3 mb-5">
            <LocationCard
              title="Current"
              icon="location_on"
              tone="border-outline-variant/40 bg-surface-container-low/50 text-on-surface-variant"
              lat={vendor.latitude}
              lng={vendor.longitude}
              address={vendor.storeAddress}
              emptyText="No location set yet"
            />
            <div className="hidden md:flex items-center text-outline">
              <span className="material-symbols-outlined text-[24px]">arrow_forward</span>
            </div>
            <LocationCard
              title="Requested"
              icon="pin_drop"
              tone="border-blue-200 bg-blue-50/60 text-blue-700"
              lat={pending.latitude}
              lng={pending.longitude}
              address={pending.address}
              emptyText="No coordinates provided"
            />
          </div>

          {error && (
            <div className="bg-red-50 border border-red-200 text-red-700 px-4 py-3 rounded-xl mb-4 text-sm flex items-center gap-2">
              <span className="material-symbols-outlined text-[18px]">error</span>
              {error}
            </div>
          )}

          {rejecting ? (
            <div className="rounded-xl border border-red-200 bg-red-50/50 p-4">
              <label htmlFor="location-reject-reason" className="block text-sm font-semibold text-on-surface mb-1.5">
                Reason for rejecting <span className="font-normal text-outline">(sent to the vendor)</span>
              </label>
              <textarea
                id="location-reject-reason"
                value={reason}
                onChange={(e) => setReason(e.target.value)}
                disabled={busy}
                rows={3}
                maxLength={REJECT_REASON_MAX}
                autoFocus
                placeholder="e.g. The pin is in the middle of the road. Please drop it on your shop's entrance."
                className="w-full px-4 py-3 bg-white border border-outline-variant/50 rounded-xl text-sm text-on-surface placeholder:text-outline focus:outline-none focus:ring-2 focus:ring-primary/30 focus:border-primary transition-all disabled:opacity-60"
              />
              <p className="text-[11px] text-outline mt-1 mb-3 text-right">
                {reason.length}/{REJECT_REASON_MAX}
              </p>
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
                  disabled={busy || !reasonText}
                  className="flex-1 py-2.5 rounded-xl text-sm font-semibold text-white bg-red-600 hover:bg-red-700 transition-colors disabled:opacity-50 disabled:cursor-not-allowed flex items-center justify-center gap-2"
                >
                  {submitting === "reject" && <Spinner className="w-4 h-4" color="text-white" />}
                  {submitting === "reject" ? "Rejecting..." : "Reject request"}
                </button>
              </div>
            </div>
          ) : (
            <div className="flex gap-2">
              <button
                onClick={() => { setRejecting(true); setError(null); }}
                disabled={busy}
                className="flex-1 py-2.5 rounded-xl text-sm font-semibold bg-red-50 text-red-700 hover:bg-red-100 transition-colors disabled:opacity-50 flex items-center justify-center gap-2"
              >
                <span className="material-symbols-outlined text-[18px]">close</span>
                Reject
              </button>
              <button
                onClick={() => run("approve")}
                disabled={busy || !hasCoords(pending.latitude, pending.longitude)}
                className="flex-1 py-2.5 rounded-xl text-sm font-semibold text-white bg-emerald-600 hover:bg-emerald-700 transition-colors disabled:opacity-50 disabled:cursor-not-allowed flex items-center justify-center gap-2"
              >
                {submitting === "approve" ? (
                  <Spinner className="w-4 h-4" color="text-white" />
                ) : (
                  <span className="material-symbols-outlined text-[18px]">check</span>
                )}
                {submitting === "approve" ? "Approving..." : "Approve new location"}
              </button>
            </div>
          )}
        </div>
      </div>
    </div>
  );
}

function StatusBadge({ approved }) {
  return (
    <span
      className={`inline-flex items-center gap-1 px-2.5 py-1 rounded-full text-xs font-semibold ${
        approved
          ? "bg-emerald-100 text-emerald-700"
          : "bg-amber-100 text-amber-700"
      }`}
    >
      <span
        className={`w-1.5 h-1.5 rounded-full ${approved ? "bg-emerald-500" : "bg-amber-500"}`}
      />
      {approved ? "Approved" : "Pending"}
    </span>
  );
}

export default function VendorsPage() {
  const [vendors, setVendors] = useState([]);
  const [loading, setLoading] = useState(true);
  const [actionLoading, setActionLoading] = useState(null);
  const [filter, setFilter] = useState("all"); // all, pending, approved, location
  const [search, setSearch] = useState("");
  const [reloadKey, setReloadKey] = useState(0);
  const [reviewVendor, setReviewVendor] = useState(null);
  const [message, setMessage] = useState(null); // { type: "success" | "error", text }
  const router = useRouter();

  useEffect(() => {
    const token = localStorage.getItem("vendra_admin_token");
    if (!token) { router.push("/"); return; }

    let cancelled = false;
    async function fetchVendors() {
      try {
        const res = await getVendors();
        if (cancelled) return;
        setVendors(res.data);
        // Deep link from the dashboard: /dashboard/vendors?filter=location (first load only)
        if (reloadKey === 0 && new URLSearchParams(window.location.search).get("filter") === "location") {
          setFilter("location");
        }
      } catch (err) {
        if (isAuthError(err)) router.push("/");
        console.error("Error fetching vendors:", err);
      } finally {
        if (!cancelled) setLoading(false);
      }
    }
    fetchVendors();
    return () => { cancelled = true; };
  }, [router, reloadKey]);

  function handleLocationReviewed(result) {
    setReviewVendor(null);
    setMessage(result);
    setReloadKey((k) => k + 1);
    notifyCountsChanged();
  }

  async function handleApprove(vendorId) {
    setActionLoading(vendorId);
    try {
      await approveVendor(vendorId);
      setVendors((prev) =>
        prev.map((v) => (v.id === vendorId ? { ...v, isApproved: true } : v))
      );
      notifyCountsChanged();
    } catch (err) {
      alert("Failed to approve vendor: " + err.message);
    } finally {
      setActionLoading(null);
    }
  }

  async function handleDisapprove(vendorId) {
    if (!confirm("Are you sure you want to disapprove this vendor? Their products will be hidden from customers.")) return;
    setActionLoading(vendorId);
    try {
      await disapproveVendor(vendorId);
      setVendors((prev) =>
        prev.map((v) => (v.id === vendorId ? { ...v, isApproved: false } : v))
      );
      notifyCountsChanged();
    } catch (err) {
      alert("Failed to disapprove vendor: " + err.message);
    } finally {
      setActionLoading(null);
    }
  }

  const tabVendors = vendors.filter((v) => {
    if (filter === "pending") return !v.isApproved;
    if (filter === "approved") return v.isApproved;
    if (filter === "location") return Boolean(v.pendingLocation);
    return true;
  });
  const filteredVendors = tabVendors.filter((v) =>
    matchesSearch(search, v.storeName, v.ownerName, v.email, v.phone, v.storeAddress, v.cnic)
  );

  const pendingCount = vendors.filter((v) => !v.isApproved).length;
  const locationCount = vendors.filter((v) => v.pendingLocation).length;

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

  return (
    <div>
      {/* Header */}
      <div className="flex items-center justify-between mb-6">
        <div>
          <h1 className="text-2xl font-bold text-on-surface">Vendor Management</h1>
          <p className="text-on-surface-variant text-sm mt-1">
            {vendors.length} total vendors • {pendingCount} pending approval
            {locationCount > 0 && <> • {locationCount} location change{locationCount > 1 ? "s" : ""} to review</>}
          </p>
        </div>
      </div>

      {/* Pending Approval Alert */}
      {pendingCount > 0 && (
        <div className="bg-amber-50 border border-amber-200 rounded-xl p-4 mb-6 flex items-center gap-3">
          <div className="w-10 h-10 bg-amber-100 rounded-lg flex items-center justify-center shrink-0">
            <span className="material-symbols-outlined text-amber-700 text-[22px]">pending_actions</span>
          </div>
          <div>
            <p className="text-sm font-semibold text-amber-800">
              {pendingCount} vendor{pendingCount > 1 ? "s" : ""} awaiting approval
            </p>
            <p className="text-xs text-amber-600">Review their CNIC and store details before approving</p>
          </div>
          <button
            onClick={() => setFilter("pending")}
            className="ml-auto text-sm font-semibold text-amber-700 hover:underline"
          >
            View Pending →
          </button>
        </div>
      )}

      {/* Location change requests */}
      {locationCount > 0 && (
        <div className="bg-blue-50 border border-blue-200 rounded-xl p-4 mb-6 flex items-center gap-3">
          <div className="w-10 h-10 bg-blue-100 rounded-lg flex items-center justify-center shrink-0">
            <span className="material-symbols-outlined text-blue-700 text-[22px]">edit_location_alt</span>
          </div>
          <div>
            <p className="text-sm font-semibold text-blue-900">
              {locationCount} store location change{locationCount > 1 ? "s" : ""} awaiting review
            </p>
            <p className="text-xs text-blue-700">The store keeps its current location until you approve the move</p>
          </div>
          <button
            onClick={() => setFilter("location")}
            className="ml-auto text-sm font-semibold text-blue-700 hover:underline"
          >
            View Requests →
          </button>
        </div>
      )}

      {/* Filter Tabs + Search */}
      <div className="flex flex-wrap items-center justify-between gap-3 mb-6">
        <div className="flex flex-wrap gap-2">
          {tabs.map((t) => (
            <TabButton
              key={t.key}
              active={filter === t.key}
              onClick={() => setFilter(t.key)}
              count={t.key === "pending" ? pendingCount : t.key === "location" ? locationCount : 0}
            >
              {t.label}
            </TabButton>
          ))}
        </div>
        <SearchBox
          value={search}
          onChange={setSearch}
          placeholder="Search store, owner, email or phone"
          count={filteredVendors.length}
          total={tabVendors.length}
        />
      </div>

      {message && (
        <div
          className={`rounded-xl px-4 py-3 mb-4 text-sm flex items-center gap-2 border ${
            message.type === "success"
              ? "bg-emerald-50 border-emerald-200 text-emerald-800"
              : "bg-red-50 border-red-200 text-red-700"
          }`}
        >
          <span className="material-symbols-outlined text-[18px]">
            {message.type === "success" ? "check_circle" : "error"}
          </span>
          <span className="flex-1">{message.text}</span>
          <button onClick={() => setMessage(null)} className="material-symbols-outlined text-[18px] opacity-60 hover:opacity-100">
            close
          </button>
        </div>
      )}

      {/* Vendors Table */}
      <div className="bg-white rounded-2xl border border-outline-variant/20 shadow-sm overflow-hidden">
        <div className="overflow-x-auto">
          <table className="w-full sticky-actions">
            <thead>
              <tr className="bg-surface-container-low/50 border-b border-outline-variant/20">
                <Th>Store</Th>
                <Th>Owner</Th>
                <Th>CNIC</Th>
                <Th align="right">Products</Th>
                <Th align="right">Revenue</Th>
                <Th>Status</Th>
                <Th align="right">Actions</Th>
              </tr>
            </thead>
            <tbody className="divide-y divide-outline-variant/10">
              {filteredVendors.map((vendor) => (
                <tr key={vendor.id} className="hover:bg-surface-container-low/30 transition-colors">
                  <td className="px-4 py-3.5 max-w-[300px]">
                    <div className="flex items-center gap-3 min-w-0">
                      <div className="w-10 h-10 bg-primary/10 rounded-xl flex items-center justify-center shrink-0">
                        <span className="material-symbols-outlined text-primary text-[20px]">storefront</span>
                      </div>
                      <div className="min-w-0">
                        <p className="text-sm font-semibold text-on-surface truncate" title={vendor.storeName}>{vendor.storeName}</p>
                        <p className="text-xs text-outline truncate" title={vendor.email}>{vendor.email}</p>
                      </div>
                    </div>
                  </td>
                  <td className="px-4 py-3.5 whitespace-nowrap">
                    <p className="text-sm text-on-surface">{vendor.ownerName}</p>
                    <p className="text-xs text-outline">{vendor.phone || "—"}</p>
                  </td>
                  <td className="px-4 py-3.5 whitespace-nowrap">
                    <code className="text-xs bg-surface-container-low px-2 py-1 rounded text-on-surface font-mono">
                      {vendor.cnic || "Not provided"}
                    </code>
                  </td>
                  <td className="px-4 py-3.5 text-sm text-on-surface font-medium text-right tabular-nums">{vendor.productCount}</td>
                  <td className="px-4 py-3.5 text-sm text-on-surface font-semibold text-right whitespace-nowrap tabular-nums">
                    {formatRs(vendor.totalRevenue)}
                  </td>
                  <td className="px-4 py-3.5">
                    <div className="flex flex-col items-start gap-1.5">
                      <StatusBadge approved={vendor.isApproved} />
                      {vendor.pendingLocation && <LocationChangeBadge />}
                    </div>
                  </td>
                  <td className="px-4 py-3.5 text-right whitespace-nowrap">
                    <div className="flex flex-col items-end gap-1.5">
                    {vendor.pendingLocation && actionLoading !== vendor.id && (
                      <button
                        onClick={() => { setMessage(null); setReviewVendor(vendor); }}
                        className="text-xs font-semibold px-3 py-1.5 rounded-lg bg-blue-50 text-blue-700 hover:bg-blue-100 transition-colors inline-flex items-center gap-1"
                      >
                        <span className="material-symbols-outlined text-[16px]">edit_location_alt</span>
                        Review location
                      </button>
                    )}
                    {actionLoading === vendor.id ? (
                      <svg className="animate-spin w-5 h-5 text-primary inline-block" fill="none" viewBox="0 0 24 24">
                        <circle className="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" strokeWidth="4" />
                        <path className="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4z" />
                      </svg>
                    ) : vendor.isApproved ? (
                      <button
                        onClick={() => handleDisapprove(vendor.id)}
                        className="text-xs font-semibold px-3 py-1.5 rounded-lg bg-red-50 text-red-700 hover:bg-red-100 transition-colors"
                      >
                        Disapprove
                      </button>
                    ) : (
                      <button
                        onClick={() => handleApprove(vendor.id)}
                        className="text-xs font-semibold px-3 py-1.5 rounded-lg bg-emerald-50 text-emerald-700 hover:bg-emerald-100 transition-colors"
                      >
                        ✓ Approve
                      </button>
                    )}
                    </div>
                  </td>
                </tr>
              ))}

              {filteredVendors.length === 0 && (
                <tr>
                  <td colSpan={7} className="text-center py-12 text-on-surface-variant">
                    {search.trim() && tabVendors.length > 0 ? (
                      <NoSearchResults query={search} onClear={() => setSearch("")} />
                    ) : (
                      <>
                        <span className="material-symbols-outlined text-[48px] text-outline-variant block mb-2">
                          {filter === "location" ? "task_alt" : "search_off"}
                        </span>
                        {filter === "location" ? "No store location changes are waiting for review." : "No vendors found for this filter."}
                      </>
                    )}
                  </td>
                </tr>
              )}
            </tbody>
          </table>
        </div>
      </div>

      {reviewVendor && reviewVendor.pendingLocation && (
        <LocationReviewModal
          vendor={reviewVendor}
          onClose={() => setReviewVendor(null)}
          onDone={handleLocationReviewed}
        />
      )}
    </div>
  );
}
