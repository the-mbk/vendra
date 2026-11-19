"use client";

import { useState, useEffect } from "react";
import { useRouter, useParams } from "next/navigation";
import { getDisputeDossier, resolveDispute, fileUrl, isAuthError } from "../../../lib/api";
import {
  PageLoader, ErrorBox, Spinner, EscrowBadge, OrderStatusBadge, MaskedPhone, roleColors, resolutionConfig,
  formatRs, formatDate, formatMinutes, formatOrderId, humanize, notifyCountsChanged,
} from "../../../lib/ui";

/** Shown instead of a broken image when a signed evidence link has expired */
function ExpiredLink({ onReload, reloading, compact = false }) {
  return (
    <div className={`w-full h-full flex flex-col items-center justify-center text-center gap-2 ${compact ? "p-2" : "p-6"}`}>
      <span className="material-symbols-outlined text-outline text-[28px]">link_off</span>
      <p className={`${compact ? "text-[11px]" : "text-sm"} font-semibold text-on-surface-variant`}>
        Link expired — reload the page
      </p>
      <button
        type="button"
        onClick={(ev) => { ev.stopPropagation(); onReload(); }}
        disabled={reloading}
        className="inline-flex items-center gap-1 text-xs font-semibold px-3 py-1.5 rounded-lg bg-primary text-white hover:bg-primary-container transition-colors disabled:opacity-60"
      >
        {reloading ? (
          <Spinner className="w-3.5 h-3.5" color="text-white" />
        ) : (
          <span className="material-symbols-outlined text-[16px]">refresh</span>
        )}
        Reload
      </button>
    </div>
  );
}

function InfoRow({ label, children }) {
  return (
    <div className="flex items-start justify-between gap-4 py-2.5">
      <span className="text-xs font-semibold text-outline uppercase tracking-wide shrink-0">{label}</span>
      <span className="text-sm text-on-surface text-right min-w-0">{children}</span>
    </div>
  );
}

/** Small label + value pair for the order strip */
function Fact({ label, children }) {
  return (
    <div className="min-w-0">
      <p className="text-[11px] font-semibold text-outline uppercase tracking-wider">{label}</p>
      <div className="text-sm text-on-surface mt-0.5 truncate">{children}</div>
    </div>
  );
}

function Card({ title, icon, tag, children, className = "" }) {
  return (
    <div className={`bg-surface-container-lowest rounded-2xl border border-outline-variant/20 shadow-sm overflow-hidden ${className}`}>
      <div className="flex items-center gap-2 px-5 py-3.5 bg-surface-container-low/50 border-b border-outline-variant/20">
        {tag && (
          <span className="w-6 h-6 rounded-md bg-primary text-white text-xs font-bold flex items-center justify-center shrink-0">
            {tag}
          </span>
        )}
        <span className="material-symbols-outlined text-primary text-[20px]">{icon}</span>
        <h3 className="text-xs font-semibold text-on-surface-variant uppercase tracking-wider">{title}</h3>
      </div>
      <div className="p-5">{children}</div>
    </div>
  );
}

/** Small uppercase heading inside a panel */
function SubHeading({ children }) {
  return <p className="text-[11px] font-semibold text-outline uppercase tracking-wider mb-2">{children}</p>;
}

// ── GPS helpers ──

const M_PER_DEG_LAT = 111320;

const hasPoint = (p) => p != null && p.lat != null && p.lng != null;

function formatMeters(m) {
  if (m == null) return "—";
  return m < 1000 ? `${Math.round(m)} m` : `${Number((m / 1000).toFixed(2))} km`;
}

function Coordinates({ point }) {
  if (!hasPoint(point)) return <span className="text-outline">Not recorded</span>;
  const label = `${Number(point.lat).toFixed(5)}, ${Number(point.lng).toFixed(5)}`;
  return (
    <a
      href={`https://www.google.com/maps?q=${point.lat},${point.lng}`}
      target="_blank"
      rel="noopener noreferrer"
      title="Open in Google Maps"
      className="inline-flex items-center gap-1 font-mono text-xs text-primary hover:underline"
    >
      {label}
      <span className="material-symbols-outlined text-[14px]">open_in_new</span>
    </a>
  );
}

/** "42 m from pin" with an inside/outside-geofence badge */
function PinDistance({ meters, geofence }) {
  if (meters == null) return <span className="text-outline">—</span>;
  const inside = geofence != null && meters <= Number(geofence);
  return (
    <span className="inline-flex flex-wrap items-center justify-end gap-1.5">
      <span>{formatMeters(meters)} from pin</span>
      {geofence != null && (
        <span
          className={`inline-flex items-center gap-0.5 px-2 py-0.5 rounded-full text-[11px] font-semibold ${
            inside ? "bg-emerald-100 text-emerald-700" : "bg-red-100 text-red-700"
          }`}
        >
          <span className="material-symbols-outlined text-[13px]">{inside ? "check" : "close"}</span>
          {inside ? "Inside" : "Outside"} {geofence} m geofence
        </span>
      )}
    </span>
  );
}

const coordTitle = (label, p) => `${label}: ${Number(p.lat).toFixed(5)}, ${Number(p.lng).toFixed(5)}`;

/**
 * Plain SVG plot of the rider's GPS trail with the store, the customer's pin (and its
 * geofence) and where the handover happened. Local equirectangular projection; north is up.
 */
function TrailPlot({ delivery }) {
  const W = 320;
  const H = 210;
  const PAD = 18;
  const trail = (delivery.trail || []).filter(hasPoint);
  const store = hasPoint(delivery.store) ? delivery.store : null;
  const pin = hasPoint(delivery.customerPin) ? delivery.customerPin : null;
  const handover = hasPoint(delivery.handover) ? delivery.handover : null;
  const geofence = Number(delivery.geofenceMeters) || 0;
  const all = [...trail, store, pin, handover].filter(Boolean);

  if (all.length < 2) {
    return (
      <div className="rounded-xl border border-dashed border-outline-variant/50 py-8 text-center text-xs text-outline">
        Not enough GPS points to draw the route.
      </div>
    );
  }

  const lat0 = all.reduce((sum, p) => sum + Number(p.lat), 0) / all.length;
  const lng0 = all.reduce((sum, p) => sum + Number(p.lng), 0) / all.length;
  const kx = Math.cos((lat0 * Math.PI) / 180);
  const toMeters = (p) => ({ x: (Number(p.lng) - lng0) * M_PER_DEG_LAT * kx, y: (Number(p.lat) - lat0) * M_PER_DEG_LAT });

  // Bounds in metres, including the geofence circle around the pin
  const bounds = all.map(toMeters);
  if (pin && geofence) {
    const m = toMeters(pin);
    bounds.push({ x: m.x - geofence, y: m.y - geofence }, { x: m.x + geofence, y: m.y + geofence });
  }
  const minX = Math.min(...bounds.map((p) => p.x));
  const maxX = Math.max(...bounds.map((p) => p.x));
  const minY = Math.min(...bounds.map((p) => p.y));
  const maxY = Math.max(...bounds.map((p) => p.y));
  const scale = Math.min((W - 2 * PAD) / Math.max(maxX - minX, 50), (H - 2 * PAD) / Math.max(maxY - minY, 50));
  const midX = (minX + maxX) / 2;
  const midY = (minY + maxY) / 2;
  const toSvg = (p) => {
    const m = toMeters(p);
    return { x: W / 2 + (m.x - midX) * scale, y: H / 2 - (m.y - midY) * scale };
  };

  const trailSvg = trail.map(toSvg);
  const s = store && toSvg(store);
  const c = pin && toSvg(pin);
  const h = handover && toSvg(handover);

  return (
    <div>
      <svg
        viewBox={`0 0 ${W} ${H}`}
        role="img"
        aria-label="Rider GPS trail with store, customer pin and handover point"
        className="w-full h-auto rounded-xl border border-outline-variant/30 bg-surface-container-low/40"
      >
        {c && geofence > 0 && (
          <circle
            cx={c.x}
            cy={c.y}
            r={geofence * scale}
            fill="var(--color-success)"
            fillOpacity="0.08"
            stroke="var(--color-success)"
            strokeOpacity="0.6"
            strokeDasharray="4 3"
          >
            <title>{`Handover geofence: ${geofence} m around the customer's pin`}</title>
          </circle>
        )}
        {trailSvg.length > 1 && (
          <polyline
            points={trailSvg.map((p) => `${p.x.toFixed(1)},${p.y.toFixed(1)}`).join(" ")}
            fill="none"
            stroke="var(--color-primary)"
            strokeWidth="2"
            strokeLinejoin="round"
            strokeLinecap="round"
          >
            <title>{`Rider trail: ${trail.length} GPS points`}</title>
          </polyline>
        )}
        {trailSvg.length === 1 && <circle cx={trailSvg[0].x} cy={trailSvg[0].y} r="3" fill="var(--color-primary)" />}
        {s && (
          <rect
            x={s.x - 6}
            y={s.y - 6}
            width="12"
            height="12"
            rx="2"
            fill="var(--color-secondary-container)"
            stroke="var(--color-surface-container-lowest)"
            strokeWidth="2"
          >
            <title>{coordTitle("Store", store)}</title>
          </rect>
        )}
        {c && (
          <circle cx={c.x} cy={c.y} r="6" fill="var(--color-success)" stroke="var(--color-surface-container-lowest)" strokeWidth="2">
            <title>{coordTitle("Customer pin", pin)}</title>
          </circle>
        )}
        {h && (
          <path
            d={`M ${h.x} ${h.y - 7} L ${h.x + 7} ${h.y} L ${h.x} ${h.y + 7} L ${h.x - 7} ${h.y} Z`}
            fill="var(--color-on-surface)"
            stroke="var(--color-surface-container-lowest)"
            strokeWidth="2"
          >
            <title>{coordTitle("Handover", handover)}</title>
          </path>
        )}
        <text x={W - 8} y={H - 8} textAnchor="end" fontSize="10" fill="var(--color-outline)">
          {`Width ≈ ${formatMeters((W - 2 * PAD) / scale)} · north up`}
        </text>
      </svg>
      <div className="flex flex-wrap gap-x-4 gap-y-1 mt-2 text-[11px] text-on-surface-variant">
        <span className="inline-flex items-center gap-1.5"><span className="w-3 h-0.5 bg-primary rounded" />Rider trail</span>
        <span className="inline-flex items-center gap-1.5"><span className="w-2.5 h-2.5 rounded-sm bg-secondary-container" />Store</span>
        <span className="inline-flex items-center gap-1.5"><span className="w-2.5 h-2.5 rounded-full bg-success" />Customer pin</span>
        <span className="inline-flex items-center gap-1.5"><span className="w-2 h-2 rotate-45 bg-on-surface" />Handover</span>
      </div>
    </div>
  );
}

function Timeline({ steps }) {
  return (
    <ol>
      {steps.map((step, i) => (
        <li key={step.label} className="flex gap-3">
          <div className="flex flex-col items-center">
            <span
              className={`mt-1 w-2.5 h-2.5 rounded-full shrink-0 ${step.at ? "bg-primary" : "border-2 border-outline-variant"}`}
            />
            {i < steps.length - 1 && <span className="w-px flex-1 bg-outline-variant/50 my-0.5" />}
          </div>
          <div className="pb-3 min-w-0">
            <p className={`text-sm ${step.at ? "text-on-surface font-medium" : "text-outline"}`}>{step.label}</p>
            <p className="text-xs text-outline">{step.at ? formatDate(step.at, true) : "Not recorded"}</p>
          </div>
        </li>
      ))}
    </ol>
  );
}

function ProductThumb({ url, name }) {
  const [failed, setFailed] = useState(false);
  if (!url || failed) {
    return (
      <div className="w-14 h-14 rounded-lg bg-surface-container-low border border-outline-variant/30 flex items-center justify-center shrink-0">
        <span className="material-symbols-outlined text-outline-variant text-[24px]">image_not_supported</span>
      </div>
    );
  }
  return (
    <a href={fileUrl(url)} target="_blank" rel="noreferrer" title="Open catalog photo" className="shrink-0">
      {/* eslint-disable-next-line @next/next/no-img-element -- catalog photos are served by the API host */}
      <img
        src={fileUrl(url)}
        alt={name}
        onError={() => setFailed(true)}
        className="w-14 h-14 rounded-lg object-cover border border-outline-variant/30 bg-white"
      />
    </a>
  );
}

// ── Panels ──

function ClaimPanel({ claim, delivery, failedUrls, reloading, onReload, onOpen, onFailed }) {
  const evidence = claim.evidence || [];
  const reporterPoint = { lat: claim.reporterLat, lng: claim.reporterLng };
  return (
    <Card title={`${humanize(claim.role)} claim`} icon="report" tag="A">
      <div className="flex items-center gap-2 flex-wrap mb-2">
        <span className="text-xs font-semibold px-2.5 py-1 rounded-full bg-red-50 text-red-700">{humanize(claim.issueType)}</span>
        <span className="text-xs text-on-surface-variant">
          by <span className="font-semibold text-on-surface">{claim.name}</span>
        </span>
        <span
          className={`px-2 py-0.5 rounded-full text-[11px] font-semibold ${
            roleColors[claim.role] || "bg-surface-container-low text-on-surface-variant"
          }`}
        >
          {humanize(claim.role)}
        </span>
      </div>
      <p className="text-xs text-outline mb-4 flex items-center gap-1">
        <span className="material-symbols-outlined text-[14px]">schedule</span>
        Filed {formatDate(claim.createdAt, true)}
      </p>

      <SubHeading>Statement</SubHeading>
      <p className="text-sm text-on-surface whitespace-pre-line leading-relaxed mb-4">{claim.description}</p>

      <SubHeading>Photo evidence ({evidence.length})</SubHeading>
      {evidence.length > 0 ? (
        <div className="grid grid-cols-2 gap-2 mb-4">
          {evidence.map((e) =>
            failedUrls.has(e.url) ? (
              <div
                key={e.id}
                className="aspect-square rounded-xl overflow-hidden border border-dashed border-outline-variant/60 bg-surface-container-low"
              >
                <ExpiredLink compact onReload={onReload} reloading={reloading} />
              </div>
            ) : (
              <button
                key={e.id}
                onClick={() => onOpen(e.id)}
                className="group relative aspect-square rounded-xl overflow-hidden border border-outline-variant/30 bg-surface-container-low"
              >
                {/* eslint-disable-next-line @next/next/no-img-element -- evidence is served by the API host */}
                <img
                  src={fileUrl(e.url)}
                  alt={e.name || `Evidence ${e.id}`}
                  onError={() => onFailed(e.url)}
                  className="w-full h-full object-cover group-hover:scale-105 transition-transform"
                />
                <span className="absolute inset-x-0 bottom-0 bg-black/50 text-white text-[10px] px-2 py-1 truncate text-left">
                  {e.name || `Photo ${e.id}`}
                </span>
              </button>
            )
          )}
        </div>
      ) : (
        <p className="text-sm text-on-surface-variant flex items-center gap-2 mb-4">
          <span className="material-symbols-outlined text-outline-variant">hide_image</span>
          No photos were attached.
        </p>
      )}

      <SubHeading>Reporter location</SubHeading>
      {hasPoint(reporterPoint) ? (
        <div className="divide-y divide-outline-variant/10 -my-2.5">
          <InfoRow label="GPS"><Coordinates point={reporterPoint} /></InfoRow>
          <InfoRow label="Distance">
            <PinDistance meters={claim.reporterDistanceFromPinMeters} geofence={delivery.geofenceMeters} />
          </InfoRow>
        </div>
      ) : (
        <p className="text-sm text-outline">No GPS position was sent with this report.</p>
      )}
    </Card>
  );
}

function StorePanel({ store }) {
  const items = store.items || [];
  const notRecorded = <span className="text-outline">Not recorded</span>;
  return (
    <Card title="Store catalog record" icon="storefront" tag="B">
      <p className="text-sm font-semibold text-on-surface">{store.name}</p>
      {store.address && <p className="text-xs text-outline">{store.address}</p>}

      <div className="rounded-xl border border-outline-variant/30 px-4 py-1 my-4">
        <div className="divide-y divide-outline-variant/10">
          <InfoRow label="Packing">
            <span
              className={`inline-flex items-center gap-1 px-2 py-0.5 rounded-full text-[11px] font-semibold ${
                store.fullyPacked ? "bg-emerald-100 text-emerald-700" : "bg-amber-100 text-amber-800"
              }`}
            >
              <span className="material-symbols-outlined text-[13px]">{store.fullyPacked ? "check" : "warning"}</span>
              {store.fullyPacked ? "Every item checked off" : "Not fully packed"}
            </span>
          </InfoRow>
          <InfoRow label="Packed">{store.packedAt ? formatDate(store.packedAt, true) : notRecorded}</InfoRow>
          <InfoRow label="Packed by">{store.packedByName || notRecorded}</InfoRow>
          <InfoRow label="Ready">{store.readyAt ? formatDate(store.readyAt, true) : notRecorded}</InfoRow>
        </div>
      </div>

      <SubHeading>Order lines ({items.length})</SubHeading>
      <ul className="space-y-3">
        {items.map((item) => {
          const short = Number(item.packedQuantity ?? 0) < Number(item.quantity);
          const meta = [item.category, item.weightGrams ? `${item.weightGrams} g` : null, item.barcode].filter(Boolean);
          return (
            <li key={item.id} className="flex gap-3">
              <ProductThumb url={item.imageUrl} name={item.name} />
              <div className="min-w-0 flex-1">
                <p className="text-sm font-medium text-on-surface truncate" title={item.name}>{item.name}</p>
                <p className="text-xs text-outline truncate">{meta.length > 0 ? meta.join(" · ") : "—"}</p>
                <div className="flex flex-wrap items-center gap-x-3 gap-y-1 mt-1">
                  <span className="text-xs text-on-surface-variant tabular-nums">
                    {item.quantity} × {formatRs(item.unitPrice)}
                  </span>
                  <span
                    className={`text-[11px] font-semibold px-1.5 py-0.5 rounded ${
                      short ? "bg-red-100 text-red-700" : "bg-emerald-100 text-emerald-700"
                    }`}
                  >
                    Packed {item.packedQuantity ?? 0}/{item.quantity}
                  </span>
                </div>
              </div>
            </li>
          );
        })}
        {items.length === 0 && <li className="text-sm text-outline">No order lines found.</li>}
      </ul>
    </Card>
  );
}

/**
 * Each party's track record (false-dispute trap): the customer's earlier claims and how
 * they ended, and the store's and rider's abuse signals over the last 30 days.
 */
function TrackRecord({ history, customerName, storeName, riderName }) {
  const { customer, store, rider, windowDays } = history;
  const columns = [
    {
      who: customerName || "Customer",
      role: "Customer",
      rows: [
        { label: "Delivered orders", value: customer.deliveredOrders },
        { label: "Earlier claims", value: customer.earlierClaims },
        { label: "Claims rejected", value: customer.claimsRejected, warn: customer.claimsRejected > 0 },
        { label: "Claims upheld", value: customer.claimsUpheld },
      ],
    },
    {
      who: storeName,
      role: "Store",
      rows: [
        { label: `Online orders dropped for walk-ins (${windowDays}d)`, value: store.walkInOverrides, warn: store.walkInOverrides > 0 },
        { label: "Other claims upheld against it", value: store.claimsUpheld, warn: store.claimsUpheld > 0 },
      ],
    },
    rider && {
      who: riderName || "Rider",
      role: "Rider",
      rows: [
        { label: "Deliveries completed", value: rider.deliveries },
        { label: `Accepted tasks let lapse (${windowDays}d)`, value: rider.taskTimeouts, warn: rider.taskTimeouts > 0 },
        { label: `Handovers locked by wrong codes (${windowDays}d)`, value: rider.handoverLockouts, warn: rider.handoverLockouts > 0 },
      ],
    },
  ].filter(Boolean);

  return (
    <div className="bg-surface-container-lowest rounded-2xl border border-outline-variant/20 shadow-sm p-5 mb-5">
      <div className="flex items-center gap-2 mb-4">
        <span className="material-symbols-outlined text-[20px] text-on-surface-variant">history</span>
        <h3 className="text-sm font-bold text-on-surface">Track records</h3>
        <span className="text-xs text-outline">Earlier behaviour of everyone involved, not counting this dispute</span>
      </div>
      <div className={`grid grid-cols-1 gap-5 ${columns.length === 3 ? "md:grid-cols-3" : "md:grid-cols-2"}`}>
        {columns.map((c) => (
          <div key={c.role}>
            <p className="text-[11px] font-semibold text-outline uppercase tracking-wider">{c.role}</p>
            <p className="text-sm font-semibold text-on-surface mb-2 truncate" title={c.who}>{c.who}</p>
            <dl className="space-y-1.5">
              {c.rows.map((r) => (
                <div key={r.label} className="flex items-center justify-between gap-3 text-sm">
                  <dt className="text-on-surface-variant">{r.label}</dt>
                  <dd className={`font-semibold tabular-nums ${r.warn ? "text-amber-700" : "text-on-surface"}`}>{r.value}</dd>
                </div>
              ))}
            </dl>
          </div>
        ))}
      </div>
    </div>
  );
}

function DeliveryPanel({ delivery }) {
  const wait = delivery.waitMinutes;
  const free = Number(delivery.freeWaitMinutes) || 0;
  const over = wait != null ? Math.max(0, wait - free) : 0;
  const trailCount = delivery.trail?.length || 0;

  return (
    <Card title="Rider delivery audit" icon="two_wheeler" tag="C">
      <p className="text-sm font-semibold text-on-surface">{delivery.riderName || "No rider assigned"}</p>
      {delivery.riderPhone && <MaskedPhone phone={delivery.riderPhone} />}
      {delivery.deliveryType === "self_pickup" && (
        <p className="mt-2 text-xs text-on-surface-variant bg-surface-container-low rounded-lg px-3 py-2 flex items-start gap-1.5">
          <span className="material-symbols-outlined text-[16px] text-outline">info</span>
          Self-pickup order: the customer collected it at the store, so no rider was involved.
        </p>
      )}

      <div className="mt-4">
        <SubHeading>Timeline</SubHeading>
        <Timeline
          steps={[
            { label: "Rider assigned", at: delivery.assignedAt },
            { label: "Arrived at store", at: delivery.arrivedAt },
            { label: "Picked up", at: delivery.pickedAt },
            { label: "Handover code verified", at: delivery.handoverCodeVerifiedAt },
            { label: "Delivered", at: delivery.deliveredAt },
          ]}
        />
      </div>

      <div className="rounded-xl border border-outline-variant/30 px-4 py-1 my-4">
        <div className="divide-y divide-outline-variant/10">
          <InfoRow label="Store wait">
            {wait == null ? (
              <span className="text-outline">Not recorded</span>
            ) : (
              <span className="inline-flex flex-wrap items-center justify-end gap-1.5">
                <span className="tabular-nums">{formatMinutes(wait)}</span>
                <span
                  className={`px-2 py-0.5 rounded-full text-[11px] font-semibold ${
                    over > 0 ? "bg-amber-100 text-amber-800" : "bg-emerald-100 text-emerald-700"
                  }`}
                >
                  {over > 0 ? `${formatMinutes(over)} over ${free} min free` : `Within ${free} min free`}
                </span>
              </span>
            )}
          </InfoRow>
          <InfoRow label="Trip">{delivery.distanceKm != null ? `${delivery.distanceKm} km` : "—"}</InfoRow>
          <InfoRow label="Handover GPS"><Coordinates point={delivery.handover} /></InfoRow>
          {hasPoint(delivery.handover) && (
            <InfoRow label="Distance">
              <PinDistance meters={delivery.handoverDistanceFromPinMeters} geofence={delivery.geofenceMeters} />
            </InfoRow>
          )}
          <InfoRow label="Customer pin"><Coordinates point={delivery.customerPin} /></InfoRow>
          <InfoRow label="GPS trail">{trailCount} point{trailCount === 1 ? "" : "s"}</InfoRow>
        </div>
      </div>

      <TrailPlot delivery={delivery} />
    </Card>
  );
}

// ── Decision ──

/** Paisa-exact split, mirroring the backend: refund and commission are rounded to the paisa */
function splitPreview(subtotal, refundPct, commissionPct) {
  const subtotalP = Math.round((Number(subtotal) || 0) * 100);
  const refundP = Math.round((subtotalP * refundPct) / 100);
  const grossP = subtotalP - refundP;
  const commissionP = Math.round((grossP * (Number(commissionPct) || 0)) / 100);
  return {
    refund: refundP / 100,
    vendorGross: grossP / 100,
    commission: commissionP / 100,
    vendorNet: (grossP - commissionP) / 100,
  };
}

/** What each resolution does, based on the order's current state (mirrors the backend) */
function describeOptions(delivery, storeName, commissionPct) {
  const delivered = delivery.status === "delivered";
  const riderPayout = Number(delivery.riderPayout) || 0;
  const commission = commissionPct != null ? `${commissionPct}% platform commission` : "platform commission";

  return {
    release: {
      title: "Release escrow to vendor",
      icon: "storefront",
      tone: "emerald",
      summary: delivered
        ? `Rejects the claim. ${storeName || "The store"} is paid now: the item subtotal minus the ${commission}.`
        : "Rejects the claim. The order isn't delivered yet, so nothing is paid out now: escrow goes back to held and the order continues as normal.",
      details: delivered
        ? ["The customer gets no refund.", "The escrow is marked released and the order is settled."]
        : ["The store is paid automatically after delivery and the dispute window, as usual.", "The customer gets no refund."],
    },
    refund: {
      title: "Full refund to customer wallet",
      icon: "undo",
      tone: "blue",
      summary: `Everything still held (${formatRs(delivery.heldAmount)}) goes back to ${delivery.customerName || "the customer"}'s wallet.`,
      details: [
        delivered
          ? "The order stays delivered; the store receives nothing for it."
          : "The order hasn't been delivered, so it is cancelled and its reserved stock is released back to the store.",
        delivered && riderPayout > 0
          ? `The rider's payout (${formatRs(riderPayout)}) already left escrow at delivery and is not reversed.`
          : null,
      ].filter(Boolean),
    },
    split: {
      title: "Partial compensation / split escrow",
      icon: "call_split",
      tone: "purple",
      summary: "Refund a share of the item subtotal to the customer; the store keeps the rest, with commission taken only on its part.",
      details: ["Use when fault is shared, e.g. one item damaged out of several."],
      disabledReason: delivered
        ? null
        : `Only possible once the order is delivered (it is currently ${humanize(delivery.status).toLowerCase()}).`,
    },
  };
}

const toneClasses = {
  blue: {
    selected: "border-blue-500 bg-blue-50 ring-2 ring-blue-500/20",
    icon: "bg-blue-100 text-blue-700",
    button: "bg-blue-600 hover:bg-blue-700 dark:hover:bg-blue-500",
  },
  emerald: {
    selected: "border-emerald-500 bg-emerald-50 ring-2 ring-emerald-500/20",
    icon: "bg-emerald-100 text-emerald-700",
    button: "bg-emerald-600 hover:bg-emerald-700 dark:hover:bg-emerald-500",
  },
  purple: {
    selected: "border-purple-500 bg-purple-50 ring-2 ring-purple-500/20",
    icon: "bg-purple-100 text-purple-700",
    button: "bg-purple-600 hover:bg-purple-700 dark:hover:bg-purple-500",
  },
};

function PreviewRow({ label, value, strong }) {
  return (
    <div className={`flex items-center justify-between gap-3 py-1.5 ${strong ? "border-t border-outline-variant/30 mt-1 pt-2" : ""}`}>
      <span className={`text-sm ${strong ? "font-semibold text-on-surface" : "text-on-surface-variant"}`}>{label}</span>
      <span className={`text-sm tabular-nums ${strong ? "font-bold text-on-surface" : "font-semibold text-on-surface"}`}>{value}</span>
    </div>
  );
}

function ResolvePanel({ dispute, delivery, storeName, commissionPct, onResolved }) {
  const [choice, setChoice] = useState(null); // "release" | "refund" | "split"
  const [refundPct, setRefundPct] = useState("50");
  const [note, setNote] = useState("");
  const [confirming, setConfirming] = useState(false);
  const [submitting, setSubmitting] = useState(false);
  const [error, setError] = useState(null);
  const options = describeOptions(delivery, storeName, commissionPct);
  const busy = confirming || submitting;

  const pct = Number(refundPct);
  const pctValid = refundPct.trim() !== "" && Number.isFinite(pct) && pct >= 1 && pct <= 99;
  const split = pctValid ? splitPreview(delivery.subtotal, pct, commissionPct) : null;
  const canContinue = Boolean(choice) && (choice !== "split" || pctValid);

  async function handleConfirm() {
    setSubmitting(true);
    setError(null);
    try {
      const res = await resolveDispute(dispute.id, choice, note.trim(), choice === "split" ? pct : undefined);
      onResolved(res.message || "Dispute resolved.");
    } catch (err) {
      setError(err.message);
      setConfirming(false);
    } finally {
      setSubmitting(false);
    }
  }

  const selected = choice ? options[choice] : null;
  const confirmSummary =
    choice === "split" && split
      ? `${formatRs(split.refund)} (${pct}% of the ${formatRs(delivery.subtotal)} item subtotal) goes to the customer's wallet; the store receives ${formatRs(split.vendorNet)} after ${formatRs(split.commission)} commission.`
      : selected?.summary;

  return (
    <Card title="Decision" icon="gavel">
      <p className="text-sm text-on-surface-variant mb-4">
        Payment for this order is frozen while the dispute is open. Compare the evidence above, then choose how to settle
        it. Every party is notified of the outcome.
      </p>

      <div className="grid grid-cols-1 lg:grid-cols-3 gap-3 mb-4">
        {Object.entries(options).map(([key, opt]) => {
          const tone = toneClasses[opt.tone];
          const isSelected = choice === key;
          const unavailable = Boolean(opt.disabledReason);
          return (
            <button
              key={key}
              type="button"
              disabled={busy || unavailable}
              onClick={() => { setChoice(key); setError(null); }}
              className={`text-left rounded-xl border p-4 transition-all disabled:cursor-not-allowed ${
                isSelected
                  ? tone.selected
                  : unavailable
                    ? "border-outline-variant/40 opacity-60"
                    : "border-outline-variant/40 hover:border-outline-variant hover:bg-surface-container-low/40"
              }`}
            >
              <div className="flex items-center gap-2 mb-2">
                <div className={`w-8 h-8 rounded-lg flex items-center justify-center shrink-0 ${tone.icon}`}>
                  <span className="material-symbols-outlined text-[18px]">{opt.icon}</span>
                </div>
                <p className="text-sm font-bold text-on-surface flex-1">{opt.title}</p>
                <span className="material-symbols-outlined text-[20px] text-outline">
                  {isSelected ? "radio_button_checked" : "radio_button_unchecked"}
                </span>
              </div>
              <p className="text-xs text-on-surface font-medium">{opt.summary}</p>
              <ul className="mt-2 space-y-1">
                {opt.details.map((d) => (
                  <li key={d} className="text-[11px] text-on-surface-variant flex gap-1.5">
                    <span className="text-outline">•</span>
                    {d}
                  </li>
                ))}
              </ul>
              {opt.disabledReason && (
                <p className="mt-2 text-[11px] font-semibold text-amber-800 flex items-start gap-1">
                  <span className="material-symbols-outlined text-[14px]">lock</span>
                  {opt.disabledReason}
                </p>
              )}
            </button>
          );
        })}
      </div>

      {choice === "split" && (
        <div className="rounded-xl border border-outline-variant/30 p-4 mb-4 grid grid-cols-1 md:grid-cols-2 gap-5">
          <div>
            <label htmlFor="refund-pct" className="block text-sm font-semibold text-on-surface mb-1.5">
              Refund to the customer
            </label>
            <div className="flex items-center gap-3">
              <input
                type="range"
                min={1}
                max={99}
                value={pctValid ? pct : 50}
                onChange={(e) => setRefundPct(e.target.value)}
                disabled={busy}
                aria-label="Refund percentage"
                className="flex-1 accent-primary"
              />
              <div
                className={`flex items-center w-24 bg-surface-container-low border rounded-lg overflow-hidden focus-within:ring-2 transition-all ${
                  pctValid
                    ? "border-outline-variant/50 focus-within:ring-primary/30 focus-within:border-primary"
                    : "border-error focus-within:ring-error/20"
                }`}
              >
                <input
                  id="refund-pct"
                  type="number"
                  min={1}
                  max={99}
                  step={1}
                  value={refundPct}
                  onChange={(e) => setRefundPct(e.target.value)}
                  disabled={busy}
                  className="flex-1 min-w-0 px-2.5 py-1.5 bg-transparent text-sm font-semibold text-on-surface focus:outline-none"
                />
                <span className="px-2 text-xs font-semibold text-on-surface-variant">%</span>
              </div>
            </div>
            <p className={`text-[11px] mt-1.5 ${pctValid ? "text-outline" : "text-error"}`}>
              {pctValid ? "Share of the item subtotal returned to the customer's wallet." : "Enter a percentage from 1 to 99."}
            </p>
          </div>
          <div>
            <PreviewRow label="Item subtotal" value={formatRs(delivery.subtotal)} />
            <PreviewRow label={`Customer refund (${pctValid ? pct : "—"}%)`} value={split ? formatRs(split.refund) : "—"} />
            <PreviewRow label="Vendor gross" value={split ? formatRs(split.vendorGross) : "—"} />
            <PreviewRow label={`Platform commission (${commissionPct ?? "—"}%)`} value={split ? `−${formatRs(split.commission)}` : "—"} />
            <PreviewRow label="Vendor receives" value={split ? formatRs(split.vendorNet) : "—"} strong />
          </div>
        </div>
      )}

      <label htmlFor="resolve-note" className="block text-sm font-semibold text-on-surface mb-1.5">
        Note to the parties <span className="font-normal text-outline">(optional)</span>
      </label>
      <textarea
        id="resolve-note"
        value={note}
        onChange={(e) => setNote(e.target.value)}
        disabled={busy}
        rows={3}
        maxLength={500}
        placeholder="e.g. Photos confirm the screen was cracked on arrival."
        className="w-full px-4 py-3 bg-surface-container-low border border-outline-variant/50 rounded-xl text-sm text-on-surface placeholder:text-outline focus:outline-none focus:ring-2 focus:ring-primary/30 focus:border-primary transition-all disabled:opacity-60"
      />
      <p className="text-[11px] text-outline mt-1 mb-4">Included in the notification sent to the customer, store and rider.</p>

      {error && (
        <div className="bg-red-50 border border-red-200 text-red-700 px-4 py-3 rounded-xl mb-4 text-sm flex items-center gap-2">
          <span className="material-symbols-outlined text-[18px]">error</span>
          {error}
        </div>
      )}

      {!confirming ? (
        <button
          onClick={() => setConfirming(true)}
          disabled={!canContinue}
          className="w-full py-3 bg-primary text-white font-semibold rounded-xl hover:bg-primary-container transition-colors disabled:opacity-50 disabled:cursor-not-allowed"
        >
          {choice ? `Continue: ${selected.title}` : "Choose release, refund or split"}
        </button>
      ) : (
        <div className="rounded-xl border border-amber-300 bg-amber-50 p-4">
          <div className="flex items-start gap-3 mb-4">
            <span className="material-symbols-outlined text-amber-700 text-[22px]">warning</span>
            <div>
              <p className="text-sm font-bold text-amber-900">Confirm: {selected.title.toLowerCase()}?</p>
              <p className="text-xs text-amber-800 mt-1">{confirmSummary}</p>
              {note.trim() && <p className="text-xs text-amber-800 mt-1">Note: &ldquo;{note.trim()}&rdquo;</p>}
              <p className="text-xs font-semibold text-amber-900 mt-2">This moves money and can&apos;t be undone.</p>
            </div>
          </div>
          <div className="flex gap-2">
            <button
              onClick={() => setConfirming(false)}
              disabled={submitting}
              className="flex-1 py-2.5 rounded-xl text-sm font-semibold text-on-surface-variant bg-surface-container-lowest border border-outline-variant/50 hover:bg-surface-container-low transition-colors disabled:opacity-50"
            >
              Back
            </button>
            <button
              onClick={handleConfirm}
              disabled={submitting}
              className={`flex-1 py-2.5 rounded-xl text-sm font-semibold text-white transition-colors disabled:opacity-60 flex items-center justify-center gap-2 ${toneClasses[selected.tone].button}`}
            >
              {submitting && <Spinner className="w-4 h-4" color="text-white" />}
              {submitting ? "Resolving..." : `Yes, ${choice === "split" ? `split ${pct}%` : choice}`}
            </button>
          </div>
        </div>
      )}
    </Card>
  );
}

function ResolutionCard({ dispute }) {
  const config = resolutionConfig[dispute.resolution] || resolutionConfig.release;
  return (
    <Card title="Resolution" icon="task_alt">
      <div className="flex items-center gap-3 mb-3">
        <div className={`w-10 h-10 rounded-lg flex items-center justify-center shrink-0 ${config.color}`}>
          <span className="material-symbols-outlined text-[20px]">{config.icon}</span>
        </div>
        <div>
          <p className="text-sm font-bold text-on-surface">
            {config.title}
            {dispute.resolution === "split" && dispute.refundPct != null && (
              <span className="font-normal text-on-surface-variant">
                {" "}· {dispute.refundPct}% of the items refunded, the rest released to the store
              </span>
            )}
          </p>
          <p className="text-xs text-outline">Resolved {formatDate(dispute.resolvedAt, true)}</p>
        </div>
      </div>
      <p className="text-sm text-on-surface-variant">
        <span className="font-semibold text-on-surface">Admin note: </span>
        {dispute.adminNote || "No note was added."}
      </p>
    </Card>
  );
}

export default function DisputeDetailPage() {
  const { id } = useParams();
  const [dossier, setDossier] = useState(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(null);
  const [outcome, setOutcome] = useState(null);
  const [reloadKey, setReloadKey] = useState(0);
  const [lightboxId, setLightboxId] = useState(null); // evidence id
  const [failedUrls, setFailedUrls] = useState(() => new Set()); // evidence links that failed to load
  const [reloading, setReloading] = useState(false);
  const router = useRouter();

  useEffect(() => {
    const token = localStorage.getItem("vendra_admin_token");
    if (!token) { router.push("/"); return; }

    let cancelled = false;
    async function fetchDossier() {
      try {
        const res = await getDisputeDossier(id);
        if (cancelled) return;
        // Fetched fresh on every open/reload so the signed evidence links are valid (~1 hour)
        setDossier(res.data);
        setError(null);
      } catch (err) {
        if (isAuthError(err) && err.status === 401) router.push("/");
        if (!cancelled) setError(err.message);
      } finally {
        if (!cancelled) {
          setLoading(false);
          setReloading(false);
        }
      }
    }
    fetchDossier();
    return () => { cancelled = true; };
  }, [router, id, reloadKey]);

  useEffect(() => {
    if (lightboxId == null) return;
    function onKey(e) { if (e.key === "Escape") setLightboxId(null); }
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [lightboxId]);

  /** Re-fetch the dossier to get freshly signed evidence links */
  function reloadEvidence() {
    setReloading(true);
    setFailedUrls(new Set());
    setReloadKey((k) => k + 1);
  }

  function markFailed(url) {
    setFailedUrls((prev) => (prev.has(url) ? prev : new Set(prev).add(url)));
  }

  function handleResolved(message) {
    setOutcome(message);
    setReloadKey((k) => k + 1);
    notifyCountsChanged();
  }

  if (loading) return <PageLoader label="Loading dispute dossier..." />;
  if (!dossier) {
    return (
      <div>
        <BackLink onClick={() => router.push("/dashboard/disputes")} />
        <ErrorBox title="Error loading dispute" message={error} />
      </div>
    );
  }

  const { dispute, claim, store, delivery, history, commissionPct } = dossier;
  const isOpen = dispute.status === "open";
  const resolution = resolutionConfig[dispute.resolution];
  const lightbox = lightboxId == null ? null : claim.evidence?.find((e) => e.id === lightboxId) || null;
  const lightboxFailed = lightbox ? failedUrls.has(lightbox.url) : false;

  return (
    <div>
      <BackLink onClick={() => router.push("/dashboard/disputes")} />

      {/* Header */}
      <div className="flex flex-wrap items-start justify-between gap-4 mb-6">
        <div>
          <div className="flex items-center gap-3 flex-wrap">
            <h1 className="text-2xl font-bold text-on-surface">Dispute #D-{String(dispute.id).padStart(4, "0")}</h1>
            {isOpen ? (
              <span className="inline-flex items-center gap-1 px-2.5 py-1 rounded-full text-xs font-semibold bg-red-100 text-red-700">
                <span className="w-1.5 h-1.5 rounded-full bg-red-500" /> Open
              </span>
            ) : (
              <span
                className={`inline-flex items-center gap-1 px-2.5 py-1 rounded-full text-xs font-semibold ${
                  resolution?.color || "bg-emerald-100 text-emerald-700"
                }`}
              >
                <span className={`w-1.5 h-1.5 rounded-full ${resolution?.dot || "bg-emerald-500"}`} />
                Resolved{resolution && ` · ${resolution.label}`}
              </span>
            )}
          </div>
          <p className="text-on-surface-variant text-sm mt-1">
            {humanize(dispute.issueType)} on order {formatOrderId(dispute.orderId)} • raised {formatDate(dispute.createdAt, true)}
          </p>
        </div>
        <div className="rounded-xl border border-outline-variant/30 bg-surface-container-lowest px-4 py-2.5 text-right">
          <p className="text-[11px] font-semibold text-outline uppercase tracking-wider">
            {["held", "disputed"].includes(delivery.escrowStatus) ? "Held in escrow" : "Escrow amount (settled)"}
          </p>
          <p className="text-xl font-bold text-on-surface tabular-nums">{formatRs(delivery.heldAmount)}</p>
          <p className="text-[11px] text-outline">Order total minus the rider payout. A full refund returns this.</p>
        </div>
      </div>

      {outcome && (
        <div className="rounded-xl px-4 py-3 mb-6 text-sm flex items-center gap-2 border bg-emerald-50 border-emerald-200 text-emerald-800">
          <span className="material-symbols-outlined text-[18px]">check_circle</span>
          <span className="flex-1"><span className="font-semibold">Dispute resolved.</span> {outcome}</span>
        </div>
      )}
      {error && <p className="text-xs text-error mb-4">Refreshing the dossier failed ({error}); showing the previous data.</p>}

      {/* Order strip */}
      <div className="bg-surface-container-lowest rounded-2xl border border-outline-variant/20 shadow-sm p-5 mb-5 grid grid-cols-2 md:grid-cols-4 xl:grid-cols-8 gap-4">
        <Fact label="Order"><span className="font-bold text-primary">{formatOrderId(delivery.orderId)}</span></Fact>
        <Fact label="Placed">{formatDate(delivery.placedAt, true)}</Fact>
        <Fact label="Customer">
          {delivery.customerName || "—"}
          {delivery.customerPhone && <span className="block"><MaskedPhone phone={delivery.customerPhone} /></span>}
        </Fact>
        <Fact label="Delivery">{humanize(delivery.deliveryType)}</Fact>
        <Fact label="Status"><OrderStatusBadge status={delivery.status} /></Fact>
        <Fact label="Escrow"><EscrowBadge status={delivery.escrowStatus} /></Fact>
        <Fact label="Items + fee">
          <span className="tabular-nums">{formatRs(delivery.subtotal)} + {formatRs(delivery.deliveryFee)}</span>
        </Fact>
        <Fact label="Order total"><span className="font-semibold tabular-nums">{formatRs(delivery.totalAmount)}</span></Fact>
      </div>

      {/* Forensic evidence dossier: A claim · B store record · C rider audit */}
      <div className="grid grid-cols-1 lg:grid-cols-3 gap-5 mb-5 items-start">
        <ClaimPanel
          claim={claim}
          delivery={delivery}
          failedUrls={failedUrls}
          reloading={reloading}
          onReload={reloadEvidence}
          onOpen={setLightboxId}
          onFailed={markFailed}
        />
        <StorePanel store={store} />
        <DeliveryPanel delivery={delivery} />
      </div>

      {history && <TrackRecord history={history} customerName={delivery.customerName} storeName={store.name} riderName={delivery.riderName} />}

      {isOpen ? (
        <ResolvePanel
          dispute={dispute}
          delivery={delivery}
          storeName={store.name}
          commissionPct={commissionPct}
          onResolved={handleResolved}
        />
      ) : (
        <ResolutionCard dispute={dispute} />
      )}

      {/* Lightbox */}
      {lightbox && (
        <div
          className="fixed inset-0 z-50 bg-black/80 flex items-center justify-center p-6"
          onClick={() => setLightboxId(null)}
        >
          <div className="relative max-w-4xl max-h-full" onClick={(e) => e.stopPropagation()}>
            {lightboxFailed ? (
              <div className="w-[min(80vw,420px)] h-64 rounded-xl bg-surface-container-lowest">
                <ExpiredLink onReload={reloadEvidence} reloading={reloading} />
              </div>
            ) : (
              // eslint-disable-next-line @next/next/no-img-element -- evidence is served by the API host
              <img
                src={fileUrl(lightbox.url)}
                alt={lightbox.name || "Evidence"}
                onError={() => markFailed(lightbox.url)}
                className="max-h-[80vh] max-w-full rounded-xl object-contain bg-white"
              />
            )}
            <div className="flex items-center justify-between mt-3 text-white text-sm">
              <span className="truncate">{lightbox.name}</span>
              <div className="flex items-center gap-3 shrink-0">
                {!lightboxFailed && (
                  <a href={fileUrl(lightbox.url)} target="_blank" rel="noreferrer" className="hover:underline">
                    Open original
                  </a>
                )}
                <button onClick={() => setLightboxId(null)} className="flex items-center gap-1 hover:underline">
                  <span className="material-symbols-outlined text-[18px]">close</span>
                  Close
                </button>
              </div>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}

function BackLink({ onClick }) {
  return (
    <button
      onClick={onClick}
      className="flex items-center gap-1 text-sm font-semibold text-primary hover:underline mb-4"
    >
      <span className="material-symbols-outlined text-[18px]">arrow_back</span>
      All disputes
    </button>
  );
}
