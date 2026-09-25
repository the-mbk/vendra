"use client";

import { useState, useEffect } from "react";
import { useRouter } from "next/navigation";
import { getVendors, approveVendor, disapproveVendor, isAuthError } from "../../lib/api";
import { notifyCountsChanged } from "../../lib/ui";

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
  const [filter, setFilter] = useState("all"); // all, pending, approved
  const router = useRouter();

  useEffect(() => {
    const token = localStorage.getItem("vendra_admin_token");
    if (!token) { router.push("/"); return; }

    async function fetchVendors() {
      try {
        const res = await getVendors();
        setVendors(res.data);
      } catch (err) {
        if (isAuthError(err)) router.push("/");
        console.error("Error fetching vendors:", err);
      } finally {
        setLoading(false);
      }
    }
    fetchVendors();
  }, [router]);

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

  const filteredVendors = vendors.filter((v) => {
    if (filter === "pending") return !v.isApproved;
    if (filter === "approved") return v.isApproved;
    return true;
  });

  const pendingCount = vendors.filter((v) => !v.isApproved).length;

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

      {/* Filter Tabs */}
      <div className="flex gap-2 mb-6">
        {["all", "pending", "approved"].map((f) => (
          <button
            key={f}
            onClick={() => setFilter(f)}
            className={`px-4 py-2 rounded-xl text-sm font-semibold transition-colors ${
              filter === f
                ? "bg-primary text-white"
                : "bg-surface-container-low text-on-surface-variant hover:bg-surface-container"
            }`}
          >
            {f.charAt(0).toUpperCase() + f.slice(1)}
            {f === "pending" && pendingCount > 0 && (
              <span className="ml-2 bg-white/20 text-white px-1.5 py-0.5 rounded-full text-[11px]">
                {pendingCount}
              </span>
            )}
          </button>
        ))}
      </div>

      {/* Vendors Table */}
      <div className="bg-white rounded-2xl border border-outline-variant/20 shadow-sm overflow-hidden">
        <div className="overflow-x-auto">
          <table className="w-full">
            <thead>
              <tr className="bg-surface-container-low/50 border-b border-outline-variant/20">
                <th className="text-left px-5 py-3.5 text-xs font-semibold text-on-surface-variant uppercase tracking-wider">Store</th>
                <th className="text-left px-5 py-3.5 text-xs font-semibold text-on-surface-variant uppercase tracking-wider">Owner</th>
                <th className="text-left px-5 py-3.5 text-xs font-semibold text-on-surface-variant uppercase tracking-wider">CNIC</th>
                <th className="text-left px-5 py-3.5 text-xs font-semibold text-on-surface-variant uppercase tracking-wider">Products</th>
                <th className="text-left px-5 py-3.5 text-xs font-semibold text-on-surface-variant uppercase tracking-wider">Revenue</th>
                <th className="text-left px-5 py-3.5 text-xs font-semibold text-on-surface-variant uppercase tracking-wider">Status</th>
                <th className="text-right px-5 py-3.5 text-xs font-semibold text-on-surface-variant uppercase tracking-wider">Actions</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-outline-variant/10">
              {filteredVendors.map((vendor) => (
                <tr key={vendor.id} className="hover:bg-surface-container-low/30 transition-colors">
                  <td className="px-5 py-4">
                    <div className="flex items-center gap-3">
                      <div className="w-10 h-10 bg-primary/10 rounded-xl flex items-center justify-center shrink-0">
                        <span className="material-symbols-outlined text-primary text-[20px]">storefront</span>
                      </div>
                      <div>
                        <p className="text-sm font-semibold text-on-surface">{vendor.storeName}</p>
                        <p className="text-xs text-outline">{vendor.email}</p>
                      </div>
                    </div>
                  </td>
                  <td className="px-5 py-4">
                    <p className="text-sm text-on-surface">{vendor.ownerName}</p>
                    <p className="text-xs text-outline">{vendor.phone || "—"}</p>
                  </td>
                  <td className="px-5 py-4">
                    <code className="text-sm bg-surface-container-low px-2 py-1 rounded text-on-surface font-mono">
                      {vendor.cnic || "Not provided"}
                    </code>
                  </td>
                  <td className="px-5 py-4 text-sm text-on-surface font-medium">{vendor.productCount}</td>
                  <td className="px-5 py-4 text-sm text-on-surface font-medium">
                    Rs. {vendor.totalRevenue.toLocaleString()}
                  </td>
                  <td className="px-5 py-4">
                    <StatusBadge approved={vendor.isApproved} />
                  </td>
                  <td className="px-5 py-4 text-right">
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
                  </td>
                </tr>
              ))}

              {filteredVendors.length === 0 && (
                <tr>
                  <td colSpan={7} className="text-center py-12 text-on-surface-variant">
                    <span className="material-symbols-outlined text-[48px] text-outline-variant block mb-2">search_off</span>
                    No vendors found for this filter.
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
