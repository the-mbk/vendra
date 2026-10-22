"use client";

import { useState, useEffect } from "react";
import { useRouter } from "next/navigation";
import { getRiders, isAuthError } from "../../lib/api";
import {
  PageLoader, ErrorBox, Th, TabButton, SearchBox, NoSearchResults,
  formatRs, formatNumber, formatDate, formatOrderId, humanize, matchesSearch,
} from "../../lib/ui";

const vehicleIcons = {
  motorbike: "two_wheeler",
  bicycle: "pedal_bike",
  car: "directions_car",
  rickshaw: "electric_rickshaw",
};

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
  const [filter, setFilter] = useState("all"); // all, online, busy
  const [search, setSearch] = useState("");
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
  }, [router]);

  if (loading) return <PageLoader label="Loading riders..." />;
  if (error) return <ErrorBox title="Error loading riders" message={error} />;

  const onlineCount = riders.filter((r) => r.isOnline).length;
  const busyCount = riders.filter((r) => r.activeOrderId).length;
  const totalDeliveries = riders.reduce((sum, r) => sum + (Number(r.deliveries) || 0), 0);
  const totalEarnings = riders.reduce((sum, r) => sum + (Number(r.earnings) || 0), 0);

  const tabRiders = riders.filter((r) => {
    if (filter === "online") return r.isOnline;
    if (filter === "busy") return r.activeOrderId;
    return true;
  });
  const filtered = tabRiders.filter((r) => matchesSearch(search, r.fullName, r.email, r.phone));

  const summary = [
    { label: "Registered", value: formatNumber(riders.length), icon: "badge", color: "text-primary" },
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
          <TabButton active={filter === "online"} onClick={() => setFilter("online")} count={onlineCount}>Online</TabButton>
          <TabButton active={filter === "busy"} onClick={() => setFilter("busy")} count={busyCount}>On delivery</TabButton>
        </div>
        <SearchBox
          value={search}
          onChange={setSearch}
          placeholder="Search name, email or phone"
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
                  <td className="px-4 py-3.5"><OnlineBadge online={rider.isOnline} /></td>
                  <td className="px-4 py-3.5">
                    <span className="inline-flex items-center gap-1.5 text-sm text-on-surface whitespace-nowrap">
                      <span className="material-symbols-outlined text-[18px] text-on-surface-variant">
                        {vehicleIcons[rider.vehicleType] || "two_wheeler"}
                      </span>
                      {humanize(rider.vehicleType)}
                    </span>
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
                  <td colSpan={8} className="text-center py-12 text-on-surface-variant">
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
