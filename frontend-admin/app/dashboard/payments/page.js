"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import { getPayments } from "../../lib/api";
import { useDebouncedValue, usePagedList } from "../../lib/hooks";
import {
  PageLoader, ErrorBox, Th, TabButton, Pill, CardLabel, UserCell, CopyId, LoadMore, SearchBox, NoSearchResults,
  paymentStatusConfig, formatRs, formatDate, formatOrderId, humanize,
} from "../../lib/ui";

const filters = [
  { key: "all", label: "All" },
  { key: "succeeded", label: "Succeeded" },
  { key: "requires_action", label: "Awaiting OTP" },
  { key: "processing", label: "Processing" },
  { key: "failed", label: "Failed" },
  { key: "canceled", label: "Canceled" },
];

const purposeConfig = {
  topup: { label: "Wallet top-up", icon: "add_card" },
  checkout: { label: "Card checkout", icon: "shopping_bag" },
};

function Purpose({ purpose }) {
  const config = purposeConfig[purpose] || { label: humanize(purpose), icon: "payments" };
  return (
    <span className="inline-flex items-center gap-1 text-xs font-medium text-on-surface-variant whitespace-nowrap">
      <span className="material-symbols-outlined text-[16px]">{config.icon}</span>
      {config.label}
    </span>
  );
}

export default function PaymentsPage() {
  const [filter, setFilter] = useState("all");
  const [search, setSearch] = useState("");
  const debouncedSearch = useDebouncedValue(search, 300);
  const list = usePagedList(getPayments, filter, debouncedSearch);
  const router = useRouter();

  return (
    <div>
      {/* Header */}
      <div className="flex items-center justify-between mb-6 gap-4">
        <div>
          <h1 className="text-2xl font-bold text-on-surface">Card Payments</h1>
          <p className="text-on-surface-variant text-sm mt-1">
            Every card charge through Vendra Pay: wallet top-ups and card checkouts. Money enters Vendra only this way.
          </p>
        </div>
        <button
          onClick={list.reload}
          disabled={list.loading}
          className="flex items-center gap-1.5 px-3 py-2 rounded-xl text-sm font-semibold text-on-surface-variant bg-surface-container-low hover:bg-surface-container transition-colors disabled:opacity-50 shrink-0"
        >
          <span className={`material-symbols-outlined text-[18px] ${list.refreshing ? "animate-spin" : ""}`}>refresh</span>
          Refresh
        </button>
      </div>

      {/* Filter Tabs + Search (searched on the server) */}
      <div className="flex flex-wrap items-center justify-between gap-3 mb-6">
        <div className="flex flex-wrap gap-2">
          {filters.map((f) => (
            <TabButton key={f.key} active={filter === f.key} onClick={() => setFilter(f.key)}>
              {f.label}
            </TabButton>
          ))}
        </div>
        <SearchBox value={search} onChange={setSearch} placeholder="Search name, email, gateway ID, order # or card last 4" />
      </div>

      {list.loading && !list.refreshing ? (
        <PageLoader label="Loading payments..." />
      ) : list.error ? (
        <ErrorBox title="Error loading payments" message={list.error} />
      ) : (
        <div className="bg-white rounded-2xl border border-outline-variant/20 shadow-sm overflow-hidden">
          <div className="overflow-x-auto">
            <table className="w-full">
              <thead>
                <tr className="bg-surface-container-low/50 border-b border-outline-variant/20">
                  <Th>User</Th>
                  <Th>Purpose</Th>
                  <Th align="right">Amount</Th>
                  <Th>Card</Th>
                  <Th>Status</Th>
                  <Th>Gateway ID</Th>
                  <Th>Order / time</Th>
                </tr>
              </thead>
              <tbody className="divide-y divide-outline-variant/10">
                {list.items.map((p) => (
                  <tr key={p.id} className="hover:bg-surface-container-low/30 transition-colors align-top">
                    <td className="px-4 py-3.5 max-w-[230px]"><UserCell user={p.user} /></td>
                    <td className="px-4 py-3.5"><Purpose purpose={p.purpose} /></td>
                    <td className="px-4 py-3.5 text-sm font-semibold text-on-surface text-right whitespace-nowrap">
                      {formatRs(p.amount)}
                    </td>
                    <td className="px-4 py-3.5"><CardLabel card={p.card} /></td>
                    <td className="px-4 py-3.5 min-w-[130px] max-w-[240px]">
                      <Pill config={paymentStatusConfig[p.status]} fallback={humanize(p.status)} />
                      {p.status === "requires_action" && p.nextAction?.attemptsLeft != null && (
                        <p className="text-[11px] text-outline mt-1">
                          {p.nextAction.attemptsLeft} OTP attempt{p.nextAction.attemptsLeft === 1 ? "" : "s"} left
                        </p>
                      )}
                      {p.failureMessage && <p className="text-xs text-error mt-1">{p.failureMessage}</p>}
                      {p.orderError && (
                        <div className="text-xs text-amber-800 bg-amber-50 border border-amber-200 rounded-lg px-2 py-1.5 mt-1.5">
                          <p className="font-semibold">Paid, but the order wasn&apos;t placed (money kept in wallet)</p>
                          <p className="mt-0.5">{p.orderError}</p>
                        </div>
                      )}
                    </td>
                    <td className="px-4 py-3.5"><CopyId value={p.gatewayIntentId} /></td>
                    <td className="px-4 py-3.5 whitespace-nowrap">
                      {p.orderId ? (
                        <button
                          onClick={() => router.push(`/dashboard/orders#order-${p.orderId}`)}
                          className="text-sm font-bold text-primary hover:underline"
                        >
                          {formatOrderId(p.orderId)}
                        </button>
                      ) : (
                        <span className="text-xs text-outline">—</span>
                      )}
                      <p className="text-[11px] text-outline mt-0.5">{formatDate(p.createdAt, true)}</p>
                    </td>
                  </tr>
                ))}

                {list.items.length === 0 && (
                  <tr>
                    <td colSpan={7} className="text-center py-12 text-on-surface-variant">
                      {list.search ? (
                        <NoSearchResults query={list.search} onClear={() => setSearch("")} />
                      ) : (
                        <>
                          <span className="material-symbols-outlined text-[48px] text-outline-variant block mb-2">credit_card</span>
                          {filter === "all"
                            ? "No card payments yet. They appear here when a customer tops up their wallet or pays for an order by card."
                            : "No payments with this status."}
                        </>
                      )}
                    </td>
                  </tr>
                )}
              </tbody>
            </table>
          </div>
          <div className="border-t border-outline-variant/10">
            <LoadMore
              hasMore={list.hasMore}
              loading={list.loadingMore}
              error={list.moreError}
              onClick={list.loadMore}
              shown={list.items.length}
            />
          </div>
        </div>
      )}
    </div>
  );
}
