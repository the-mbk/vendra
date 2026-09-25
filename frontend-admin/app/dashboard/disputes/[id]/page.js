"use client";

import { useState, useEffect } from "react";
import { useRouter, useParams } from "next/navigation";
import { getDispute, getPolicies, resolveDispute, fileUrl, isAuthError } from "../../../lib/api";
import {
  PageLoader, ErrorBox, Spinner, EscrowBadge, OrderStatusBadge, roleColors,
  formatRs, formatDate, formatOrderId, humanize, notifyCountsChanged,
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
      <span className="text-xs font-semibold text-outline uppercase tracking-wide">{label}</span>
      <span className="text-sm text-on-surface text-right">{children}</span>
    </div>
  );
}

function Card({ title, icon, children, className = "" }) {
  return (
    <div className={`bg-white rounded-2xl border border-outline-variant/20 shadow-sm overflow-hidden ${className}`}>
      <div className="flex items-center gap-2 px-5 py-3.5 bg-surface-container-low/50 border-b border-outline-variant/20">
        <span className="material-symbols-outlined text-primary text-[20px]">{icon}</span>
        <h3 className="text-xs font-semibold text-on-surface-variant uppercase tracking-wider">{title}</h3>
      </div>
      <div className="p-5">{children}</div>
    </div>
  );
}

/** What each resolution does, based on the order's current state (mirrors the backend) */
function describeOptions(dispute, commissionPct) {
  const order = dispute.order || {};
  const delivered = order.status === "delivered";
  const held = formatRs(order.heldAmount);
  const riderPaid = Number(order.totalAmount) - Number(order.heldAmount) > 0;
  const commission = commissionPct != null ? `${commissionPct}% platform commission` : "platform commission";

  return {
    refund: {
      title: "Refund the customer",
      icon: "undo",
      tone: "blue",
      summary: `Everything still held (${held}) goes back to ${order.customerName || "the customer"}'s wallet.`,
      details: [
        delivered
          ? "The order stays delivered; the store receives nothing for it."
          : "The order hasn't been delivered, so it is cancelled and its reserved stock is released back to the store.",
        riderPaid
          ? `The rider's payout (${formatRs(Number(order.totalAmount) - Number(order.heldAmount))}) already left escrow at delivery and is not reversed.`
          : null,
      ].filter(Boolean),
    },
    release: {
      title: delivered ? "Release payment to the store" : "Reject the dispute & continue",
      icon: "storefront",
      tone: "emerald",
      summary: delivered
        ? `${order.storeName || "The store"} is paid now: the item subtotal minus the ${commission}.`
        : "The order isn't delivered yet, so nothing is paid out now. Escrow goes back to held and the order continues as normal.",
      details: delivered
        ? ["The customer gets no refund.", "The escrow is marked released and the order is settled."]
        : ["The store is paid automatically after delivery and the dispute window, as usual.", "The customer gets no refund."],
    },
  };
}

const toneClasses = {
  blue: {
    selected: "border-blue-500 bg-blue-50 ring-2 ring-blue-500/20",
    icon: "bg-blue-100 text-blue-700",
    button: "bg-blue-600 hover:bg-blue-700",
  },
  emerald: {
    selected: "border-emerald-500 bg-emerald-50 ring-2 ring-emerald-500/20",
    icon: "bg-emerald-100 text-emerald-700",
    button: "bg-emerald-600 hover:bg-emerald-700",
  },
};

function ResolvePanel({ dispute, commissionPct, onResolved }) {
  const [choice, setChoice] = useState(null); // "refund" | "release"
  const [note, setNote] = useState("");
  const [confirming, setConfirming] = useState(false);
  const [submitting, setSubmitting] = useState(false);
  const [error, setError] = useState(null);
  const options = describeOptions(dispute, commissionPct);

  async function handleConfirm() {
    setSubmitting(true);
    setError(null);
    try {
      const res = await resolveDispute(dispute.id, choice, note.trim());
      onResolved(res.message || "Dispute resolved.");
    } catch (err) {
      setError(err.message);
      setConfirming(false);
    } finally {
      setSubmitting(false);
    }
  }

  const selected = choice ? options[choice] : null;

  return (
    <Card title="Decision" icon="gavel">
      <p className="text-sm text-on-surface-variant mb-4">
        Payment for this order is frozen while the dispute is open. Choose how to settle it. Every party is notified
        of the outcome.
      </p>

      <div className="grid grid-cols-1 md:grid-cols-2 gap-3 mb-4">
        {Object.entries(options).map(([key, opt]) => {
          const tone = toneClasses[opt.tone];
          const isSelected = choice === key;
          return (
            <button
              key={key}
              type="button"
              disabled={confirming || submitting}
              onClick={() => { setChoice(key); setError(null); }}
              className={`text-left rounded-xl border p-4 transition-all disabled:cursor-not-allowed ${
                isSelected ? tone.selected : "border-outline-variant/40 hover:border-outline-variant hover:bg-surface-container-low/40"
              }`}
            >
              <div className="flex items-center gap-2 mb-2">
                <div className={`w-8 h-8 rounded-lg flex items-center justify-center ${tone.icon}`}>
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
            </button>
          );
        })}
      </div>

      <label className="block text-sm font-semibold text-on-surface mb-1.5">
        Note to the parties <span className="font-normal text-outline">(optional)</span>
      </label>
      <textarea
        value={note}
        onChange={(e) => setNote(e.target.value)}
        disabled={confirming || submitting}
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
          disabled={!choice}
          className="w-full py-3 bg-primary text-white font-semibold rounded-xl hover:bg-primary-container transition-colors disabled:opacity-50 disabled:cursor-not-allowed"
        >
          {choice ? `Continue: ${selected.title}` : "Choose refund or release"}
        </button>
      ) : (
        <div className="rounded-xl border border-amber-300 bg-amber-50 p-4">
          <div className="flex items-start gap-3 mb-4">
            <span className="material-symbols-outlined text-amber-700 text-[22px]">warning</span>
            <div>
              <p className="text-sm font-bold text-amber-900">Confirm: {selected.title.toLowerCase()}?</p>
              <p className="text-xs text-amber-800 mt-1">{selected.summary}</p>
              {note.trim() && <p className="text-xs text-amber-800 mt-1">Note: &ldquo;{note.trim()}&rdquo;</p>}
              <p className="text-xs font-semibold text-amber-900 mt-2">This moves money and can&apos;t be undone.</p>
            </div>
          </div>
          <div className="flex gap-2">
            <button
              onClick={() => setConfirming(false)}
              disabled={submitting}
              className="flex-1 py-2.5 rounded-xl text-sm font-semibold text-on-surface-variant bg-white border border-outline-variant/50 hover:bg-surface-container-low transition-colors disabled:opacity-50"
            >
              Back
            </button>
            <button
              onClick={handleConfirm}
              disabled={submitting}
              className={`flex-1 py-2.5 rounded-xl text-sm font-semibold text-white transition-colors disabled:opacity-60 flex items-center justify-center gap-2 ${toneClasses[selected.tone].button}`}
            >
              {submitting && <Spinner className="w-4 h-4" color="text-white" />}
              {submitting ? "Resolving..." : `Yes, ${choice}`}
            </button>
          </div>
        </div>
      )}
    </Card>
  );
}

export default function DisputeDetailPage() {
  const { id } = useParams();
  const [dispute, setDispute] = useState(null);
  const [commissionPct, setCommissionPct] = useState(null);
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
    async function fetchDispute() {
      try {
        const res = await getDispute(id);
        if (cancelled) return;
        // Fetched fresh on every open/reload so the signed evidence links are valid (~1 hour)
        setDispute(res.data);
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
    async function fetchCommission() {
      try {
        const res = await getPolicies();
        const pct = res.data.find((p) => p.key === "commission_pct");
        if (!cancelled && pct) setCommissionPct(pct.value);
      } catch {
        // Only used for the explanation text
      }
    }
    fetchDispute();
    fetchCommission();
    return () => { cancelled = true; };
  }, [router, id, reloadKey]);

  useEffect(() => {
    if (lightboxId == null) return;
    function onKey(e) { if (e.key === "Escape") setLightboxId(null); }
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [lightboxId]);

  /** Re-fetch the dispute to get freshly signed evidence links */
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

  if (loading) return <PageLoader label="Loading dispute..." />;
  if (error) {
    return (
      <div>
        <BackLink onClick={() => router.push("/dashboard/disputes")} />
        <ErrorBox title="Error loading dispute" message={error} />
      </div>
    );
  }

  const order = dispute.order || {};
  const isOpen = dispute.status === "open";
  const lightbox = lightboxId == null ? null : dispute.evidence?.find((e) => e.id === lightboxId) || null;
  const lightboxFailed = lightbox ? failedUrls.has(lightbox.url) : false;

  return (
    <div>
      <BackLink onClick={() => router.push("/dashboard/disputes")} />

      {/* Header */}
      <div className="flex items-start justify-between gap-4 mb-6">
        <div>
          <div className="flex items-center gap-3 flex-wrap">
            <h1 className="text-2xl font-bold text-on-surface">Dispute #D-{String(dispute.id).padStart(4, "0")}</h1>
            {isOpen ? (
              <span className="inline-flex items-center gap-1 px-2.5 py-1 rounded-full text-xs font-semibold bg-red-100 text-red-700">
                <span className="w-1.5 h-1.5 rounded-full bg-red-500" /> Open
              </span>
            ) : (
              <span className="inline-flex items-center gap-1 px-2.5 py-1 rounded-full text-xs font-semibold bg-emerald-100 text-emerald-700">
                <span className="w-1.5 h-1.5 rounded-full bg-emerald-500" /> Resolved
              </span>
            )}
          </div>
          <p className="text-on-surface-variant text-sm mt-1">
            {humanize(dispute.issueType)} on order {formatOrderId(dispute.orderId)} • raised {formatDate(dispute.createdAt, true)}
          </p>
        </div>
      </div>

      {outcome && (
        <div className="rounded-xl px-4 py-3 mb-6 text-sm flex items-center gap-2 border bg-emerald-50 border-emerald-200 text-emerald-800">
          <span className="material-symbols-outlined text-[18px]">check_circle</span>
          <span className="flex-1"><span className="font-semibold">Dispute resolved.</span> {outcome}</span>
        </div>
      )}

      <div className="grid grid-cols-1 lg:grid-cols-3 gap-5">
        {/* Left: issue, evidence, decision */}
        <div className="lg:col-span-2 space-y-5">
          <Card title="Reported issue" icon="report">
            <div className="flex items-center gap-2 flex-wrap mb-3">
              <span className="text-xs font-semibold px-2.5 py-1 rounded-full bg-red-50 text-red-700">
                {humanize(dispute.issueType)}
              </span>
              <span className="text-xs text-on-surface-variant">
                Raised by <span className="font-semibold text-on-surface">{dispute.raisedBy?.name}</span>
              </span>
              <span
                className={`px-2 py-0.5 rounded-full text-[11px] font-semibold ${
                  roleColors[dispute.raisedBy?.role] || "bg-surface-container-low text-on-surface-variant"
                }`}
              >
                {humanize(dispute.raisedBy?.role)}
              </span>
            </div>
            <p className="text-sm text-on-surface whitespace-pre-line leading-relaxed">{dispute.description}</p>
          </Card>

          <Card title={`Evidence photos (${dispute.evidence?.length || 0})`} icon="photo_library">
            {dispute.evidence?.length > 0 ? (
              <div className="grid grid-cols-2 md:grid-cols-4 gap-3">
                {dispute.evidence.map((e) =>
                  failedUrls.has(e.url) ? (
                    <div
                      key={e.id}
                      className="aspect-square rounded-xl overflow-hidden border border-dashed border-outline-variant/60 bg-surface-container-low"
                    >
                      <ExpiredLink compact onReload={reloadEvidence} reloading={reloading} />
                    </div>
                  ) : (
                    <button
                      key={e.id}
                      onClick={() => setLightboxId(e.id)}
                      className="group relative aspect-square rounded-xl overflow-hidden border border-outline-variant/30 bg-surface-container-low"
                    >
                      {/* eslint-disable-next-line @next/next/no-img-element -- evidence is served by the API host */}
                      <img
                        src={fileUrl(e.url)}
                        alt={e.name || `Evidence ${e.id}`}
                        onError={() => markFailed(e.url)}
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
              <p className="text-sm text-on-surface-variant flex items-center gap-2">
                <span className="material-symbols-outlined text-outline-variant">hide_image</span>
                No photos were attached to this dispute.
              </p>
            )}
          </Card>

          {isOpen ? (
            <ResolvePanel dispute={dispute} commissionPct={commissionPct} onResolved={handleResolved} />
          ) : (
            <Card title="Resolution" icon="task_alt">
              <div className="flex items-center gap-3 mb-3">
                <div
                  className={`w-10 h-10 rounded-lg flex items-center justify-center ${
                    dispute.resolution === "refund" ? "bg-blue-100 text-blue-700" : "bg-emerald-100 text-emerald-700"
                  }`}
                >
                  <span className="material-symbols-outlined text-[20px]">
                    {dispute.resolution === "refund" ? "undo" : "storefront"}
                  </span>
                </div>
                <div>
                  <p className="text-sm font-bold text-on-surface">
                    {dispute.resolution === "refund" ? "Refunded to the customer" : "Released to the store"}
                  </p>
                  <p className="text-xs text-outline">Resolved {formatDate(dispute.resolvedAt, true)}</p>
                </div>
              </div>
              <p className="text-sm text-on-surface-variant">
                <span className="font-semibold text-on-surface">Admin note: </span>
                {dispute.adminNote || "No note was added."}
              </p>
            </Card>
          )}
        </div>

        {/* Right: order summary */}
        <div className="space-y-5">
          <Card title="Order summary" icon="receipt_long">
            <div className="divide-y divide-outline-variant/10 -my-2.5">
              <InfoRow label="Order"><span className="font-bold text-primary">{formatOrderId(dispute.orderId)}</span></InfoRow>
              <InfoRow label="Store">{order.storeName || "—"}</InfoRow>
              <InfoRow label="Customer">{order.customerName || "—"}</InfoRow>
              <InfoRow label="Rider">{order.riderName || <span className="text-outline">No rider</span>}</InfoRow>
              <InfoRow label="Delivery">{humanize(order.deliveryType)}</InfoRow>
              <InfoRow label="Order status"><OrderStatusBadge status={order.status} /></InfoRow>
              <InfoRow label="Escrow"><EscrowBadge status={order.escrowStatus} /></InfoRow>
              <InfoRow label="Order total">{formatRs(order.totalAmount)}</InfoRow>
            </div>
          </Card>

          <div className="bg-primary rounded-2xl p-5 text-white shadow-md shadow-primary/20">
            <p className="text-xs font-semibold uppercase tracking-wider text-white/70">Held in escrow</p>
            <p className="text-3xl font-bold mt-1">{formatRs(order.heldAmount)}</p>
            <p className="text-xs text-white/70 mt-2">
              Order total minus any rider payout already paid at delivery. This is the amount a refund returns.
            </p>
          </div>
        </div>
      </div>

      {/* Lightbox */}
      {lightbox && (
        <div
          className="fixed inset-0 z-50 bg-black/80 flex items-center justify-center p-6"
          onClick={() => setLightboxId(null)}
        >
          <div className="relative max-w-4xl max-h-full" onClick={(e) => e.stopPropagation()}>
            {lightboxFailed ? (
              <div className="w-[min(80vw,420px)] h-64 rounded-xl bg-white">
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
