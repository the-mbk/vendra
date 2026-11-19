"use client";

// ══════════════════════════════════════════════════════════════
// Live fleet map: online riders, stores (with orders waiting for a
// rider) and every delivery in flight drawn rider → store → customer.
// GET /api/admin/fleet every 10 s. Pick a delivery to zoom to it.
// ══════════════════════════════════════════════════════════════

import { useState, useEffect } from "react";
import { useRouter } from "next/navigation";
import { getFleet, isAuthError } from "../../lib/api";
import { PageLoader, ErrorBox, formatOrderId, formatMinutes } from "../../lib/ui";
import TileMap from "../../lib/tileMap";

const POLL_MS = 10000;

const STAGES = {
  ready_for_pickup: { label: "Waiting for a rider", color: "bg-amber-100 text-amber-700" },
  assigned: { label: "Rider heading to store", color: "bg-blue-100 text-blue-700" },
  picked: { label: "Picked up", color: "bg-cyan-100 text-cyan-700" },
  on_the_way: { label: "On the way", color: "bg-orange-100 text-orange-700" },
};

const ROUTE = { toStore: "#d97706", toCustomer: "#232774" };

function StoreMarker({ waiting }) {
  return (
    <div className="relative">
      {waiting > 0 && <span className="absolute inset-0 rounded-lg bg-amber-400/60 animate-ping" />}
      <div className="relative w-8 h-8 rounded-lg bg-surface-container-lowest border-2 border-secondary-container flex items-center justify-center shadow">
        <span className="material-symbols-outlined text-[18px] text-secondary-container">storefront</span>
      </div>
      {waiting > 0 && (
        <span className="absolute -top-2 -right-2 min-w-5 h-5 px-1 rounded-full bg-amber-500 text-white text-[11px] font-bold flex items-center justify-center">
          {waiting}
        </span>
      )}
    </div>
  );
}

function RiderMarker({ engaged }) {
  return (
    <div className={`w-8 h-8 rounded-full flex items-center justify-center shadow border-2 border-white ${engaged ? "bg-emerald-600" : "bg-blue-600"}`}>
      <span className="material-symbols-outlined text-[18px] text-white">two_wheeler</span>
    </div>
  );
}

function CustomerMarker() {
  return <span className="material-symbols-outlined text-[30px] text-primary drop-shadow" style={{ marginTop: -14 }}>location_on</span>;
}

function Legend() {
  const item = (swatch, label) => (
    <span className="inline-flex items-center gap-1.5 text-xs text-on-surface-variant">{swatch}{label}</span>
  );
  return (
    <div className="flex flex-wrap gap-x-4 gap-y-1.5">
      {item(<span className="w-3 h-3 rounded-full bg-emerald-600" />, "Rider on a delivery")}
      {item(<span className="w-3 h-3 rounded-full bg-blue-600" />, "Rider online, free")}
      {item(<span className="w-3 h-3 rounded bg-surface-container-lowest border-2 border-secondary-container" />, "Store (badge: waiting for a rider)")}
      {item(<span className="w-5 border-t-2 border-dashed" style={{ borderColor: ROUTE.toStore }} />, "Rider to store")}
      {item(<span className="w-5 border-t-2 border-dashed" style={{ borderColor: ROUTE.toCustomer }} />, "To the customer")}
    </div>
  );
}

export default function FleetMapPage() {
  const [fleet, setFleet] = useState(null);
  const [error, setError] = useState(null);
  const [focusId, setFocusId] = useState(null);
  const router = useRouter();

  useEffect(() => {
    if (!localStorage.getItem("vendra_admin_token")) {
      router.push("/");
      return undefined;
    }
    let cancelled = false;
    async function load() {
      try {
        const res = await getFleet();
        if (!cancelled) {
          setFleet(res.data);
          setError(null);
        }
      } catch (err) {
        if (isAuthError(err)) router.push("/");
        if (!cancelled) setError(err.message);
      }
    }
    load();
    const timer = setInterval(load, POLL_MS);
    return () => {
      cancelled = true;
      clearInterval(timer);
    };
  }, [router]);

  if (!fleet) return error ? <ErrorBox title="Could not load the fleet" message={error} /> : <PageLoader label="Loading the live map..." />;

  const ridersById = new Map(fleet.riders.map((r) => [r.id, r]));
  const active = fleet.deliveries.filter((d) => d.stage !== "delivered");
  const focus = active.find((d) => d.id === focusId);

  const riderPoint = (d) => {
    const r = d.riderId ? ridersById.get(d.riderId) : null;
    return r?.lat != null ? { lat: r.lat, lng: r.lng } : null;
  };

  const markers = [
    ...fleet.stores.map((s) => ({
      id: `s${s.id}`, lat: s.lat, lng: s.lng, title: `${s.name}${s.waitingForRider ? ` · ${s.waitingForRider} waiting for a rider` : ""}`,
      render: () => <StoreMarker waiting={s.waitingForRider} />,
    })),
    ...active.filter((d) => d.customer).map((d) => ({
      id: `c${d.id}`, ...d.customer, title: `${formatOrderId(d.id)} drop-off`, render: () => <CustomerMarker />,
    })),
    ...fleet.riders.filter((r) => r.lat != null).map((r) => ({
      id: `r${r.id}`, lat: r.lat, lng: r.lng,
      title: `${r.name} · ${r.state === "engaged" ? `on ${formatOrderId(r.activeOrderId)}` : "free"}`,
      render: () => <RiderMarker engaged={r.state === "engaged"} />,
    })),
  ];

  const lines = active.flatMap((d) => {
    const rider = riderPoint(d);
    const out = [];
    const enRoute = d.stage === "picked" || d.stage === "on_the_way";
    if (rider && d.store && !enRoute) out.push({ id: `rs${d.id}`, from: rider, to: d.store, color: ROUTE.toStore, dashed: true });
    if (d.customer && (enRoute ? rider : d.store)) {
      out.push({ id: `sc${d.id}`, from: enRoute ? rider : d.store, to: d.customer, color: ROUTE.toCustomer, dashed: !enRoute });
    }
    return out;
  });

  const fit = focus ? [focus.store, focus.customer, riderPoint(focus)].filter(Boolean) : undefined;
  const waitingStores = fleet.stores.filter((s) => s.waitingForRider > 0).length;

  return (
    <div>
      <div className="flex flex-wrap items-end justify-between gap-3 mb-5">
        <div>
          <h1 className="text-2xl font-bold text-on-surface">Live Fleet Map</h1>
          <p className="text-on-surface-variant text-sm mt-1">
            {fleet.counts.engaged} on deliveries · {fleet.counts.idle} free · {active.length} deliveries in flight
            {waitingStores > 0 ? ` · ${waitingStores} store${waitingStores === 1 ? "" : "s"} waiting for a rider` : ""}
          </p>
        </div>
        <p className="text-xs text-outline">Updates every {POLL_MS / 1000} s</p>
      </div>
      {error && <p className="text-xs text-error mb-3">Last refresh failed ({error}); showing the previous positions.</p>}

      <div className="grid grid-cols-1 xl:grid-cols-[1fr_320px] gap-5">
        <div className="space-y-3">
          <TileMap markers={markers} lines={lines} fit={fit} height={560} />
          <Legend />
        </div>

        <div className="bg-surface-container-lowest rounded-2xl border border-outline-variant/20 shadow-sm p-4 self-start">
          <div className="flex items-center justify-between mb-2">
            <h3 className="text-sm font-bold text-on-surface">Deliveries in flight</h3>
            {focus && (
              <button onClick={() => setFocusId(null)} className="text-xs font-semibold text-primary hover:underline">Show all</button>
            )}
          </div>
          {active.length === 0 ? (
            <p className="text-sm text-outline py-6 text-center">No deliveries on the road right now.</p>
          ) : (
            <ul className="space-y-2 max-h-[520px] overflow-y-auto">
              {active.map((d) => {
                const stage = STAGES[d.stage] || { label: d.stage, color: "" };
                return (
                  <li key={d.id}>
                    <button
                      onClick={() => setFocusId(d.id === focusId ? null : d.id)}
                      className={`w-full text-left p-3 rounded-xl border transition-colors ${
                        d.id === focusId ? "border-primary bg-primary/5" : "border-outline-variant/30 hover:bg-surface-container-low/50"
                      }`}
                    >
                      <div className="flex items-center justify-between gap-2">
                        <span className="text-sm font-bold text-primary">{formatOrderId(d.id)}</span>
                        <span className={`px-2 py-0.5 rounded-full text-[11px] font-semibold ${stage.color}`}>{stage.label}</span>
                      </div>
                      <p className="text-xs text-on-surface mt-1 truncate">{d.storeName}</p>
                      <p className="text-xs text-outline truncate">{d.riderName || "No rider yet"}</p>
                      {d.waitingNow && (
                        <p className={`text-[11px] mt-1 font-semibold ${d.waitExceeded ? "text-error" : "text-amber-700"}`}>
                          Rider waiting at the store {formatMinutes(d.waitMinutes)}
                        </p>
                      )}
                    </button>
                  </li>
                );
              })}
            </ul>
          )}
        </div>
      </div>
    </div>
  );
}
