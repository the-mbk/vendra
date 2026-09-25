"use client";

import { useState, useEffect, useRef } from "react";
import { useRouter } from "next/navigation";
import { getUsers, resetUserPassword, isAuthError } from "../../lib/api";
import { Spinner } from "../../lib/ui";

const roleConfig = {
  admin: { label: "Admin", color: "bg-purple-100 text-purple-700", icon: "admin_panel_settings" },
  vendor: { label: "Vendor", color: "bg-blue-100 text-blue-700", icon: "storefront" },
  customer: { label: "Customer", color: "bg-emerald-100 text-emerald-700", icon: "person" },
  rider: { label: "Rider", color: "bg-orange-100 text-orange-700", icon: "delivery_truck_speed" },
};

/** One-time display of a temporary password issued by an admin */
function TemporaryPasswordPanel({ result, onDismiss }) {
  const passwordRef = useRef(null);
  const [copyState, setCopyState] = useState(null); // "copied" | "manual"

  function selectPassword() {
    const el = passwordRef.current;
    if (!el || typeof window === "undefined") return;
    const range = document.createRange();
    range.selectNodeContents(el);
    const selection = window.getSelection();
    selection.removeAllRanges();
    selection.addRange(range);
  }

  function handleCopy() {
    // Called straight from the click so the browser allows clipboard access
    if (navigator.clipboard?.writeText) {
      navigator.clipboard.writeText(result.password).then(
        () => setCopyState("copied"),
        () => { selectPassword(); setCopyState("manual"); }
      );
    } else {
      selectPassword();
      setCopyState("manual");
    }
  }

  return (
    <div className="bg-white rounded-2xl border-2 border-primary/30 shadow-md shadow-primary/10 p-5 mb-6">
      <div className="flex items-start gap-3">
        <div className="w-10 h-10 rounded-xl bg-primary/10 flex items-center justify-center shrink-0">
          <span className="material-symbols-outlined text-primary text-[22px]">key</span>
        </div>
        <div className="flex-1 min-w-0">
          <p className="text-sm font-bold text-on-surface">
            Temporary password for {result.name}
            <span className="font-normal text-outline"> ({result.email})</span>
          </p>

          <div className="flex items-center gap-3 flex-wrap mt-3">
            <code
              ref={passwordRef}
              onClick={selectPassword}
              className="font-mono text-xl font-bold tracking-wider text-on-surface bg-surface-container-low border border-outline-variant/50 rounded-xl px-4 py-2 select-all cursor-text"
            >
              {result.password}
            </code>
            <button
              type="button"
              onClick={handleCopy}
              className="inline-flex items-center gap-1.5 text-sm font-semibold px-4 py-2 rounded-xl bg-primary text-white hover:bg-primary-container transition-colors"
            >
              <span className="material-symbols-outlined text-[18px]">
                {copyState === "copied" ? "check" : "content_copy"}
              </span>
              {copyState === "copied" ? "Copied" : "Copy"}
            </button>
          </div>
          {copyState === "manual" && (
            <p className="text-xs text-amber-700 mt-2">
              Couldn&apos;t copy automatically — the password is selected, press Ctrl+C to copy it.
            </p>
          )}

          <ul className="mt-4 space-y-1.5 text-xs text-on-surface-variant">
            <li className="flex gap-2">
              <span className="material-symbols-outlined text-[16px] text-primary">person</span>
              Give this password to {result.name} directly.
            </li>
            <li className="flex gap-2">
              <span className="material-symbols-outlined text-[16px] text-primary">lock_reset</span>
              They must choose a new password after signing in with it.
            </li>
            <li className="flex gap-2">
              <span className="material-symbols-outlined text-[16px] text-amber-600">visibility_off</span>
              <span className="font-semibold text-on-surface">It won&apos;t be shown again</span> — if it&apos;s lost, reset the password again.
            </li>
          </ul>
        </div>
        <button
          type="button"
          onClick={onDismiss}
          className="text-xs font-semibold px-3 py-1.5 rounded-lg bg-surface-container-low text-on-surface-variant hover:bg-surface-container transition-colors shrink-0"
        >
          Done
        </button>
      </div>
    </div>
  );
}

export default function UsersPage() {
  const [users, setUsers] = useState([]);
  const [loading, setLoading] = useState(true);
  const [roleFilter, setRoleFilter] = useState("all");
  const [confirmResetId, setConfirmResetId] = useState(null);
  const [resettingId, setResettingId] = useState(null);
  const [resetResult, setResetResult] = useState(null); // { name, email, password }
  const [resetError, setResetError] = useState(null);
  const router = useRouter();

  async function handleReset(user) {
    setResettingId(user.id);
    setConfirmResetId(null);
    setResetError(null);
    setResetResult(null);
    try {
      const res = await resetUserPassword(user.id);
      setResetResult({ name: user.fullName, email: user.email, password: res.data.temporaryPassword });
      if (typeof window !== "undefined") window.scrollTo({ top: 0, behavior: "smooth" });
    } catch (err) {
      if (isAuthError(err) && err.status === 401) { router.push("/"); return; }
      setResetError(`Couldn't reset the password for ${user.fullName}: ${err.message}`);
    } finally {
      setResettingId(null);
    }
  }

  useEffect(() => {
    const token = localStorage.getItem("vendra_admin_token");
    if (!token) { router.push("/"); return; }

    async function fetchUsers() {
      try {
        const res = await getUsers();
        setUsers(res.data);
      } catch (err) {
        if (isAuthError(err)) router.push("/");
        console.error("Error fetching users:", err);
      } finally {
        setLoading(false);
      }
    }
    fetchUsers();
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

  const filteredUsers = roleFilter === "all" ? users : users.filter((u) => u.role === roleFilter);

  // Role counts
  const roleCounts = users.reduce((acc, u) => { acc[u.role] = (acc[u.role] || 0) + 1; return acc; }, {});

  return (
    <div>
      {/* Header */}
      <div className="flex items-center justify-between mb-6">
        <div>
          <h1 className="text-2xl font-bold text-on-surface">User Management</h1>
          <p className="text-on-surface-variant text-sm mt-1">{users.length} total users on the platform</p>
        </div>
      </div>

      {resetResult && (
        <TemporaryPasswordPanel
          key={`${resetResult.email}-${resetResult.password}`}
          result={resetResult}
          onDismiss={() => setResetResult(null)}
        />
      )}

      {resetError && (
        <div className="rounded-xl px-4 py-3 mb-6 text-sm flex items-center gap-2 border bg-red-50 border-red-200 text-red-700">
          <span className="material-symbols-outlined text-[18px]">error</span>
          <span className="flex-1">{resetError}</span>
          <button onClick={() => setResetError(null)} className="material-symbols-outlined text-[18px] opacity-60 hover:opacity-100">
            close
          </button>
        </div>
      )}

      {/* Role Cards */}
      <div className="grid grid-cols-2 md:grid-cols-4 gap-4 mb-6">
        {Object.entries(roleConfig).map(([role, config]) => (
          <button
            key={role}
            onClick={() => setRoleFilter(roleFilter === role ? "all" : role)}
            className={`bg-white rounded-xl p-4 border text-left transition-all ${
              roleFilter === role
                ? "border-primary shadow-md shadow-primary/10"
                : "border-outline-variant/20 hover:border-outline-variant/40"
            }`}
          >
            <div className="flex items-center gap-2 mb-2">
              <span className={`material-symbols-outlined text-[20px] ${
                roleFilter === role ? "text-primary" : "text-on-surface-variant"
              }`}>{config.icon}</span>
              <span className="text-xs font-semibold text-on-surface-variant uppercase">{config.label}s</span>
            </div>
            <p className="text-2xl font-bold text-on-surface">{roleCounts[role] || 0}</p>
          </button>
        ))}
      </div>

      {/* Users Table */}
      <div className="bg-white rounded-2xl border border-outline-variant/20 shadow-sm overflow-hidden">
        <div className="overflow-x-auto">
          <table className="w-full">
            <thead>
              <tr className="bg-surface-container-low/50 border-b border-outline-variant/20">
                <th className="text-left px-5 py-3.5 text-xs font-semibold text-on-surface-variant uppercase tracking-wider">User</th>
                <th className="text-left px-5 py-3.5 text-xs font-semibold text-on-surface-variant uppercase tracking-wider">Role</th>
                <th className="text-left px-5 py-3.5 text-xs font-semibold text-on-surface-variant uppercase tracking-wider">Phone</th>
                <th className="text-left px-5 py-3.5 text-xs font-semibold text-on-surface-variant uppercase tracking-wider">Store</th>
                <th className="text-left px-5 py-3.5 text-xs font-semibold text-on-surface-variant uppercase tracking-wider">Joined</th>
                <th className="text-right px-5 py-3.5 text-xs font-semibold text-on-surface-variant uppercase tracking-wider">Actions</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-outline-variant/10">
              {filteredUsers.map((user) => {
                const config = roleConfig[user.role] || roleConfig.customer;
                return (
                  <tr key={user.id} className="hover:bg-surface-container-low/30 transition-colors">
                    <td className="px-5 py-4">
                      <div className="flex items-center gap-3">
                        <div className="w-10 h-10 bg-primary/10 rounded-full flex items-center justify-center shrink-0">
                          <span className="text-primary font-bold text-sm">
                            {user.fullName.split(" ").map((n) => n[0]).join("").slice(0, 2).toUpperCase()}
                          </span>
                        </div>
                        <div>
                          <p className="text-sm font-semibold text-on-surface">{user.fullName}</p>
                          <p className="text-xs text-outline">{user.email}</p>
                        </div>
                      </div>
                    </td>
                    <td className="px-5 py-4">
                      <span className={`inline-flex items-center gap-1 px-2.5 py-1 rounded-full text-xs font-semibold ${config.color}`}>
                        {config.label}
                      </span>
                    </td>
                    <td className="px-5 py-4 text-sm text-on-surface">{user.phone || "—"}</td>
                    <td className="px-5 py-4 text-sm text-on-surface">{user.storeName || "—"}</td>
                    <td className="px-5 py-4 text-xs text-outline">
                      {new Date(user.createdAt).toLocaleDateString("en-PK", {
                        day: "numeric", month: "short", year: "numeric",
                      })}
                    </td>
                    <td className="px-5 py-4 text-right whitespace-nowrap">
                      {user.role === "admin" ? (
                        <span className="text-xs text-outline">—</span>
                      ) : resettingId === user.id ? (
                        <Spinner className="w-5 h-5 inline-block" />
                      ) : confirmResetId === user.id ? (
                        <div className="inline-flex items-center gap-2">
                          <span className="text-xs text-on-surface-variant">Issue a temporary password?</span>
                          <button
                            onClick={() => handleReset(user)}
                            className="text-xs font-semibold px-3 py-1.5 rounded-lg bg-primary text-white hover:bg-primary-container transition-colors"
                          >
                            Yes, reset
                          </button>
                          <button
                            onClick={() => setConfirmResetId(null)}
                            className="text-xs font-semibold px-3 py-1.5 rounded-lg bg-surface-container-low text-on-surface-variant hover:bg-surface-container transition-colors"
                          >
                            Cancel
                          </button>
                        </div>
                      ) : (
                        <button
                          onClick={() => { setConfirmResetId(user.id); setResetError(null); }}
                          disabled={resettingId !== null}
                          className="inline-flex items-center gap-1 text-xs font-semibold px-3 py-1.5 rounded-lg bg-surface-container-low text-on-surface-variant hover:bg-surface-container transition-colors disabled:opacity-50"
                        >
                          <span className="material-symbols-outlined text-[16px]">lock_reset</span>
                          Reset password
                        </button>
                      )}
                    </td>
                  </tr>
                );
              })}

              {filteredUsers.length === 0 && (
                <tr>
                  <td colSpan={6} className="text-center py-12 text-on-surface-variant">
                    <span className="material-symbols-outlined text-[48px] text-outline-variant block mb-2">group_off</span>
                    No users found for this filter.
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
