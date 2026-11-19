"use client";

import { useState, useEffect } from "react";
import { useRouter } from "next/navigation";
import { getPolicies, updatePolicies, isAuthError } from "../../lib/api";
import { PageLoader, ErrorBox, Spinner, formatDate } from "../../lib/ui";
import AuditTrail from "../../lib/auditTrail";

// Display grouping only; any policy not listed here shows under "Other rules"
const groups = [
  { title: "Catalog & Inventory", icon: "inventory_2", keys: ["auto_approve_products", "default_buffer", "low_stock_units"] },
  { title: "Fees & Commission", icon: "payments", keys: ["commission_pct", "delivery_fee", "delivery_fee_per_km", "cancel_penalty_pct"] },
  { title: "Escrow & Disputes", icon: "account_balance_wallet", keys: ["dispute_window_min"] },
  {
    title: "Order Timeouts",
    icon: "timer_off",
    keys: ["vendor_accept_timeout_min", "rider_assign_timeout_min", "rider_pickup_timeout_min", "rider_store_wait_max_min"],
  },
  { title: "Wallet & Withdrawals", icon: "output", keys: ["min_withdrawal"] },
  {
    title: "Delivery & Rider Payouts",
    icon: "two_wheeler",
    keys: ["max_delivery_km", "geofence_m", "pickup_geofence_m", "task_radius_km", "rider_base_fee", "rider_per_km", "rider_per_wait_min", "rider_free_wait_min"],
    simulator: true,
  },
];

function toDraft(policies) {
  return Object.fromEntries(policies.map((p) => [p.key, String(p.value)]));
}

/** Same rules as PUT /api/admin/policies. Returns an error message or null. */
function validate(policy, raw) {
  if (String(raw).trim() === "") return "Enter a value.";
  const value = Number(raw);
  if (!Number.isFinite(value)) return "Must be a number.";
  if (value < 0) return "Must be 0 or more.";
  if (policy.unit === "%" && value > 100) return "Can't be more than 100%.";
  if (policy.unit === "0/1" && ![0, 1].includes(value)) return "Must be 0 or 1.";
  if (policy.unit === "units" && !Number.isInteger(value)) return "Must be a whole number.";
  return null;
}

function isChanged(policy, draft) {
  return !(String(draft ?? "").trim() !== "" && Number(draft) === policy.value);
}

function minutesHint(value) {
  const n = Number(value);
  if (!Number.isFinite(n) || n < 60) return null;
  const hours = n / 60;
  if (hours < 48) return `≈ ${Number(hours.toFixed(1))} hour${hours === 1 ? "" : "s"}`;
  const days = hours / 24;
  return `≈ ${Number(days.toFixed(1))} days`;
}

/** Plain number for a formula: 3.5, 20, 0.25 (no thousands separators, at most 2 decimals) */
const plain = (n) => String(Number(n.toFixed(2)));

const rs2 = (n) => `Rs. ${n.toLocaleString("en-PK", { minimumFractionDigits: 2, maximumFractionDigits: 2 })}`;

/** Same formula as the backend: base + perKm × km + perWaitMin × max(0, wait − freeWait) */
function riderPayout({ base, perKm, perWait, freeWait }, km, wait) {
  const paidWait = Math.max(0, wait - freeWait);
  return { paidWait, total: base + perKm * km + perWait * paidWait };
}

function SimInput({ id, label, unit, value, onChange }) {
  return (
    <div>
      <label htmlFor={id} className="block text-[11px] font-semibold text-outline uppercase tracking-wider mb-1">
        {label}
      </label>
      <div className="flex items-center w-36 bg-surface-container-lowest border border-outline-variant/50 rounded-lg overflow-hidden focus-within:ring-2 focus-within:ring-primary/30 focus-within:border-primary transition-all">
        <input
          id={id}
          type="number"
          inputMode="decimal"
          min={0}
          step="0.5"
          value={value}
          onChange={(e) => onChange(e.target.value)}
          className="flex-1 min-w-0 px-2.5 py-1.5 bg-transparent text-sm font-semibold text-on-surface focus:outline-none"
        />
        <span className="px-2.5 py-1.5 text-xs font-semibold text-on-surface-variant border-l border-outline-variant/40">{unit}</span>
      </div>
    </div>
  );
}

/** Live preview of one rider payout, using the rider rates exactly as typed (saved or not) */
function RiderPayoutSimulator({ byKey, drafts }) {
  const [km, setKm] = useState("3.5");
  const [wait, setWait] = useState("8");

  const base = byKey.rider_base_fee;
  const perKm = byKey.rider_per_km;
  const perWait = byKey.rider_per_wait_min;
  const freeWait = byKey.rider_free_wait_min; // optional: treated as 0 when absent
  if (!base || !perKm || !perWait) return null;

  const policies = [base, perKm, perWait, freeWait].filter(Boolean);
  const invalidCount = policies.filter((p) => validate(p, drafts[p.key] ?? "")).length;
  const unsaved = policies.some((p) => isChanged(p, drafts[p.key]));
  const ratesFrom = (valueOf) => ({
    base: Number(valueOf(base)),
    perKm: Number(valueOf(perKm)),
    perWait: Number(valueOf(perWait)),
    freeWait: freeWait ? Number(valueOf(freeWait)) : 0,
  });
  const rates = ratesFrom((p) => drafts[p.key]);
  const tripKm = Number(km);
  const waitMin = Number(wait);
  const tripValid = km.trim() !== "" && wait.trim() !== "" && tripKm >= 0 && waitMin >= 0;
  const { paidWait, total } = riderPayout(rates, tripKm, waitMin);
  const savedTotal = riderPayout(ratesFrom((p) => p.value), tripKm, waitMin).total;
  const showPreview = tripValid && invalidCount === 0;

  return (
    <div className="px-5 py-4 border-t border-outline-variant/20 bg-surface-container-low/40">
      <div className="flex items-center gap-2 flex-wrap mb-3">
        <span className="material-symbols-outlined text-primary text-[20px]">calculate</span>
        <p className="text-sm font-semibold text-on-surface">Rider payout simulator</p>
        <span
          className={`text-[11px] font-semibold px-2 py-0.5 rounded-full ${
            unsaved ? "bg-amber-100 text-amber-700" : "bg-surface-container text-on-surface-variant"
          }`}
        >
          {unsaved ? "Using unsaved values" : "Using saved values"}
        </span>
      </div>

      <div className="flex flex-wrap items-end gap-4 mb-3">
        <SimInput id="sim-km" label="Trip distance" unit="km" value={km} onChange={setKm} />
        <SimInput id="sim-wait" label="Wait at store" unit="min" value={wait} onChange={setWait} />
        {showPreview && (
          <div className="pb-1">
            <p className="text-[11px] font-semibold text-outline uppercase tracking-wider">Rider earns</p>
            <p className="text-2xl font-bold text-on-surface tabular-nums leading-tight">{rs2(total)}</p>
          </div>
        )}
      </div>

      {invalidCount > 0 ? (
        <p className="text-sm text-error">
          Fix the invalid rider payout value{invalidCount > 1 ? "s" : ""} above to see a preview.
        </p>
      ) : !tripValid ? (
        <p className="text-sm text-outline">Enter a distance and waiting time of 0 or more.</p>
      ) : (
        <>
          <p className="text-sm text-on-surface font-mono bg-surface-container-lowest border border-outline-variant/30 rounded-lg px-3 py-2 overflow-x-auto whitespace-nowrap">
            Example {plain(tripKm)} km trip with {plain(waitMin)} min wait = Rs. {plain(rates.base)} + ({plain(tripKm)} ×{" "}
            {plain(rates.perKm)}) + ({plain(paidWait)} × {plain(rates.perWait)}) = <span className="font-bold">{rs2(total)}</span>
          </p>
          <p className="text-xs text-on-surface-variant mt-2">
            Base fee + distance × per-km rate + paid waiting × per-minute rate. The first {plain(rates.freeWait)} min at
            the store are free, so {plain(waitMin)} min of waiting pays for {plain(paidWait)} min.
            {unsaved && Math.abs(savedTotal - total) >= 0.005 && (
              <>
                {" "}With the saved rates this trip pays {rs2(savedTotal)} ({total > savedTotal ? "+" : "−"}
                {rs2(Math.abs(total - savedTotal))}).
              </>
            )}
          </p>
        </>
      )}
    </div>
  );
}

/** Saved / unsaved / invalid badge shown next to a policy's name */
function StatusBadge({ policy, error, changed, saved, isFlag }) {
  if (error) {
    return (
      <span className="inline-flex items-center gap-1 text-[11px] font-semibold px-2 py-0.5 rounded-full bg-red-100 text-red-700">
        <span className="material-symbols-outlined text-[13px]">error</span>
        Invalid
      </span>
    );
  }
  if (changed) {
    return (
      <span className="text-[11px] font-semibold px-2 py-0.5 rounded-full bg-amber-100 text-amber-700">
        Unsaved (was {isFlag ? (policy.value === 1 ? "On" : "Off") : `${policy.value} ${policy.unit}`})
      </span>
    );
  }
  if (saved) {
    return (
      <span className="inline-flex items-center gap-1 text-[11px] font-semibold px-2 py-0.5 rounded-full bg-emerald-100 text-emerald-700">
        <span className="material-symbols-outlined text-[13px]">check</span>
        Saved
      </span>
    );
  }
  return null;
}

function Toggle({ checked, onChange }) {
  return (
    <button
      type="button"
      role="switch"
      aria-checked={checked}
      onClick={() => onChange(!checked)}
      className={`relative inline-flex h-7 w-12 shrink-0 items-center rounded-full transition-colors ${
        checked ? "bg-primary" : "bg-outline-variant"
      }`}
    >
      <span
        className={`inline-block h-5 w-5 rounded-full bg-white shadow transition-transform ${
          checked ? "translate-x-6" : "translate-x-1"
        }`}
      />
    </button>
  );
}

function PolicyRow({ policy, draft, saved, onChange }) {
  const error = validate(policy, draft);
  const changed = isChanged(policy, draft);
  const isFlag = policy.unit === "0/1";
  const hint = policy.unit === "min" ? minutesHint(draft) : null;
  // In development mode fast timers cap some values; the backend reports what it actually uses
  const effective = Number(policy.effectiveValue);
  const overridden = policy.effectiveValue != null && Number.isFinite(effective) && effective !== Number(policy.value);

  return (
    <div
      className={`flex flex-col md:flex-row md:items-center gap-4 px-5 py-4 ${
        error ? "bg-red-50/50" : changed ? "bg-amber-50/50" : ""
      }`}
    >
      <div className="flex-1 min-w-0">
        <div className="flex items-center gap-2 flex-wrap">
          <p className="text-sm font-semibold text-on-surface">{policy.label}</p>
          <code className="text-[11px] bg-surface-container-low text-outline px-1.5 py-0.5 rounded font-mono">{policy.key}</code>
          <StatusBadge policy={policy} error={error} changed={changed} saved={saved} isFlag={isFlag} />
          {overridden && (
            <span
              title={`Saved value is ${policy.value} ${policy.unit}; development mode's fast timers use ${effective} ${policy.unit} instead. Production uses the saved value.`}
              className="inline-flex items-center gap-1 text-[11px] font-semibold px-2 py-0.5 rounded-full bg-purple-50 text-purple-700 border border-purple-200"
            >
              <span className="material-symbols-outlined text-[13px]">construction</span>
              Development mode: using {isFlag ? (effective === 1 ? "On" : "Off") : `${effective} ${policy.unit}`}
            </span>
          )}
        </div>
        <p className="text-xs text-on-surface-variant mt-1">{policy.description}</p>
        <p className="text-[11px] text-outline mt-1">Last updated {formatDate(policy.updatedAt, true)}</p>
      </div>

      <div className="md:w-[240px] shrink-0">
        {isFlag ? (
          <div className="flex items-center gap-3 md:justify-end">
            <span className={`text-sm font-semibold ${Number(draft) === 1 ? "text-primary" : "text-outline"}`}>
              {Number(draft) === 1 ? "On" : "Off"}
            </span>
            <Toggle checked={Number(draft) === 1} onChange={(on) => onChange(on ? "1" : "0")} />
          </div>
        ) : (
          <div>
            <div
              className={`flex items-center bg-surface-container-low border rounded-xl overflow-hidden focus-within:ring-2 transition-all ${
                error
                  ? "border-error focus-within:ring-error/20"
                  : "border-outline-variant/50 focus-within:ring-primary/30 focus-within:border-primary"
              }`}
            >
              <input
                type="number"
                inputMode="decimal"
                min={0}
                max={policy.unit === "%" ? 100 : undefined}
                step={policy.unit === "units" ? 1 : "any"}
                value={draft}
                onChange={(e) => onChange(e.target.value)}
                className="flex-1 min-w-0 px-3 py-2.5 bg-transparent text-sm font-semibold text-on-surface focus:outline-none"
              />
              <span className="px-3 text-xs font-semibold text-on-surface-variant border-l border-outline-variant/40 py-2.5 bg-surface-container-lowest/60">
                {policy.unit}
              </span>
            </div>
            {error ? (
              <p className="text-[11px] text-error mt-1">{error}</p>
            ) : hint ? (
              <p className="text-[11px] text-outline mt-1">{hint}</p>
            ) : null}
          </div>
        )}
      </div>
    </div>
  );
}

export default function PoliciesPage() {
  const [policies, setPolicies] = useState([]);
  const [drafts, setDrafts] = useState({});
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(null);
  const [saving, setSaving] = useState(false);
  const [message, setMessage] = useState(null); // { type, text }
  const [savedKeys, setSavedKeys] = useState(() => new Set()); // rules the last Save changed ("Saved" badge)
  const [auditKey, setAuditKey] = useState(0); // reloads the audit trail after a save
  const router = useRouter();

  useEffect(() => {
    const token = localStorage.getItem("vendra_admin_token");
    if (!token) { router.push("/"); return; }

    async function fetchPolicies() {
      try {
        const res = await getPolicies();
        setPolicies(res.data);
        setDrafts(toDraft(res.data));
      } catch (err) {
        if (isAuthError(err)) router.push("/");
        setError(err.message);
      } finally {
        setLoading(false);
      }
    }
    fetchPolicies();
  }, [router]);

  const changedPolicies = policies.filter((p) => drafts[p.key] !== undefined && isChanged(p, drafts[p.key]));
  const errors = policies.filter((p) => validate(p, drafts[p.key] ?? ""));
  const canSave = changedPolicies.length > 0 && errors.length === 0 && !saving;

  function setDraft(key, value) {
    setDrafts((prev) => ({ ...prev, [key]: value }));
    setSavedKeys((prev) => {
      if (!prev.has(key)) return prev;
      const next = new Set(prev);
      next.delete(key);
      return next;
    });
    setMessage(null);
  }

  async function handleSave() {
    if (!canSave) return;
    setSaving(true);
    setMessage(null);
    try {
      const values = Object.fromEntries(changedPolicies.map((p) => [p.key, Number(drafts[p.key])]));
      const res = await updatePolicies(values);
      setPolicies(res.data);
      setDrafts(toDraft(res.data));
      setSavedKeys(new Set(changedPolicies.map((p) => p.key)));
      setAuditKey((k) => k + 1);
      setMessage({
        type: "success",
        text: `${res.message || "Policies updated."} (${changedPolicies.length} rule${changedPolicies.length > 1 ? "s" : ""} changed)`,
      });
    } catch (err) {
      if (isAuthError(err)) router.push("/");
      setMessage({ type: "error", text: err.message });
    } finally {
      setSaving(false);
    }
  }

  function handleDiscard() {
    setDrafts(toDraft(policies));
    setMessage(null);
  }

  if (loading) return <PageLoader label="Loading policies..." />;
  if (error) return <ErrorBox title="Error loading policies" message={error} />;

  const byKey = Object.fromEntries(policies.map((p) => [p.key, p]));
  const grouped = new Set(groups.flatMap((g) => g.keys));
  const sections = [
    ...groups.map((g) => ({ ...g, items: g.keys.map((k) => byKey[k]).filter(Boolean) })),
    { title: "Other rules", icon: "tune", items: policies.filter((p) => !grouped.has(p.key)) },
  ].filter((s) => s.items.length > 0);

  return (
    <div className="pb-24">
      {/* Header */}
      <div className="flex items-center justify-between mb-6">
        <div>
          <h1 className="text-2xl font-bold text-on-surface">Policy Engine</h1>
          <p className="text-on-surface-variant text-sm mt-1">
            {policies.length} business rules that control fees, payouts, escrow and delivery.
          </p>
        </div>
      </div>

      {/* Live-apply notice */}
      <div className="bg-blue-50 border border-blue-200 rounded-xl p-4 mb-6 flex items-start gap-3">
        <div className="w-10 h-10 bg-blue-100 rounded-lg flex items-center justify-center shrink-0">
          <span className="material-symbols-outlined text-blue-700 text-[22px]">bolt</span>
        </div>
        <div>
          <p className="text-sm font-semibold text-blue-900">Changes apply immediately. No redeploy needed.</p>
          <p className="text-xs text-blue-700 mt-0.5">
            The backend reads these values on every action, so a saved change is used by the very next checkout,
            delivery, payout or escrow release. Open customer, vendor and rider apps are told about the change and
            reload it straight away. The delivery fee is the base fee plus the per-km rate for the distance from the
            store to the customer, rounded to the nearest Rs 10.
          </p>
        </div>
      </div>

      {message && (
        <div
          className={`rounded-xl px-4 py-3 mb-6 text-sm flex items-center gap-2 border ${
            message.type === "success"
              ? "bg-emerald-50 border-emerald-200 text-emerald-800"
              : "bg-red-50 border-red-200 text-red-700"
          }`}
        >
          <span className="material-symbols-outlined text-[18px]">
            {message.type === "success" ? "check_circle" : "error"}
          </span>
          <span className="flex-1">
            {message.type === "error" && <span className="font-semibold">The server rejected the change: </span>}
            {message.text}
          </span>
          <button onClick={() => setMessage(null)} className="material-symbols-outlined text-[18px] opacity-60 hover:opacity-100">
            close
          </button>
        </div>
      )}

      <div className="space-y-5">
        {sections.map((section) => (
          <div key={section.title} className="bg-surface-container-lowest rounded-2xl border border-outline-variant/20 shadow-sm overflow-hidden">
            <div className="flex items-center gap-2 px-5 py-3.5 bg-surface-container-low/50 border-b border-outline-variant/20">
              <span className="material-symbols-outlined text-primary text-[20px]">{section.icon}</span>
              <h3 className="text-xs font-semibold text-on-surface-variant uppercase tracking-wider">{section.title}</h3>
            </div>
            <div className="divide-y divide-outline-variant/10">
              {section.items.map((policy) => (
                <PolicyRow
                  key={policy.key}
                  policy={policy}
                  draft={drafts[policy.key] ?? ""}
                  saved={savedKeys.has(policy.key)}
                  onChange={(v) => setDraft(policy.key, v)}
                />
              ))}
            </div>
            {section.simulator && <RiderPayoutSimulator byKey={byKey} drafts={drafts} />}
          </div>
        ))}
      </div>

      <div className="mt-6">
        <AuditTrail refreshKey={auditKey} />
      </div>

      {/* Save bar */}
      <div className="fixed bottom-0 left-[260px] right-0 z-10 bg-surface-container-lowest/90 backdrop-blur-md border-t border-outline-variant/30 px-8 py-4 flex items-center justify-between gap-4">
        <p className="text-sm text-on-surface-variant">
          {errors.length > 0 ? (
            <span className="text-error font-medium">
              Fix {errors.length} invalid value{errors.length > 1 ? "s" : ""} before saving.
            </span>
          ) : changedPolicies.length > 0 ? (
            <>
              <span className="font-semibold text-on-surface">{changedPolicies.length}</span> unsaved change
              {changedPolicies.length > 1 ? "s" : ""}
            </>
          ) : (
            "All policies saved."
          )}
        </p>
        <div className="flex items-center gap-2">
          <button
            onClick={handleDiscard}
            disabled={changedPolicies.length === 0 || saving}
            className="px-4 py-2.5 rounded-xl text-sm font-semibold text-on-surface-variant bg-surface-container-low hover:bg-surface-container transition-colors disabled:opacity-40 disabled:cursor-not-allowed"
          >
            Discard
          </button>
          <button
            onClick={handleSave}
            disabled={!canSave}
            className="px-5 py-2.5 bg-primary text-white text-sm font-semibold rounded-xl hover:bg-primary-container transition-colors disabled:opacity-50 disabled:cursor-not-allowed flex items-center gap-2"
          >
            {saving ? <Spinner className="w-4 h-4" color="text-white" /> : <span className="material-symbols-outlined text-[18px]">save</span>}
            {saving ? "Saving..." : "Save changes"}
          </button>
        </div>
      </div>
    </div>
  );
}
