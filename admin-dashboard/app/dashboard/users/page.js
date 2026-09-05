"use client";

import { useState, useEffect } from "react";
import { useRouter } from "next/navigation";
import { getUsers } from "../../lib/api";

const roleConfig = {
  admin: { label: "Admin", color: "bg-purple-100 text-purple-700", icon: "admin_panel_settings" },
  vendor: { label: "Vendor", color: "bg-blue-100 text-blue-700", icon: "storefront" },
  customer: { label: "Customer", color: "bg-emerald-100 text-emerald-700", icon: "person" },
  rider: { label: "Rider", color: "bg-orange-100 text-orange-700", icon: "delivery_truck_speed" },
};

export default function UsersPage() {
  const [users, setUsers] = useState([]);
  const [loading, setLoading] = useState(true);
  const [roleFilter, setRoleFilter] = useState("all");
  const router = useRouter();

  useEffect(() => {
    const token = localStorage.getItem("vendra_admin_token");
    if (!token) { router.push("/"); return; }

    async function fetchUsers() {
      try {
        const res = await getUsers();
        setUsers(res.data);
      } catch (err) {
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
                  </tr>
                );
              })}

              {filteredUsers.length === 0 && (
                <tr>
                  <td colSpan={5} className="text-center py-12 text-on-surface-variant">
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
