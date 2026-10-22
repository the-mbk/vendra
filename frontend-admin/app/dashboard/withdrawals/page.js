"use client";

import { useState } from "react";
import { getWithdrawals } from "../../lib/api";
import { useDebouncedValue, usePagedList } from "../../lib/hooks";
import {
  PageLoader, ErrorBox, Th, TabButton, Pill, CardLabel, UserCell, CopyId, LoadMore, SearchBox, NoSearchResults,
  withdrawalStatusConfig, formatRs, formatDate, humanize,
} from "../../lib/ui";

const filters = [
  { key: "all", label: "All" },
  { key: "in_transit", label: "In transit" },
  { key: "paid", label: "Paid" },
  { key: "failed", label: "Failed" },
  { key: "pending", label: "Queued" },
];

export default function WithdrawalsPage() {
  const [filter, setFilter] = useState("all");
  const [search, setSearch] = useState("");
  const debouncedSearch = useDebouncedValue(search, 300);
  const list = usePagedList(getWithdrawals, filter, debouncedSearch);

  return (
    <div>
      {/* Header */}
      <div className="flex items-center justify-between mb-6 gap-4">
        <div>
          <h1 className="text-2xl font-bold text-on-surface">Withdrawals</h1>
          <p className="text-on-surface-variant text-sm mt-1">
            Payouts from user wallets to their cards. The wallet is debited at once; a failed payout returns the money to it.
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
        <SearchBox value={search} onChange={setSearch} placeholder="Search name, email, payout ID or card last 4" />
      </div>

      {list.loading && !list.refreshing ? (
        <PageLoader label="Loading withdrawals..." />
      ) : list.error ? (
        <ErrorBox title="Error loading withdrawals" message={list.error} />
      ) : (
        <div className="bg-white rounded-2xl border border-outline-variant/20 shadow-sm overflow-hidden">
          <div className="overflow-x-auto">
            <table className="w-full">
              <thead>
                <tr className="bg-surface-container-low/50 border-b border-outline-variant/20">
                  <Th>User</Th>
                  <Th align="right">Amount</Th>
                  <Th>Card</Th>
                  <Th>Status</Th>
                  <Th>Payout ID</Th>
                  <Th>Requested</Th>
                  <Th>Settled</Th>
                </tr>
              </thead>
              <tbody className="divide-y divide-outline-variant/10">
                {list.items.map((w) => (
                  <tr key={w.id} className="hover:bg-surface-container-low/30 transition-colors align-top">
                    <td className="px-4 py-3.5 max-w-[230px]"><UserCell user={w.user} /></td>
                    <td className="px-4 py-3.5 text-sm font-semibold text-on-surface text-right whitespace-nowrap">
                      {formatRs(w.amount)}
                    </td>
                    <td className="px-4 py-3.5"><CardLabel card={w.card} /></td>
                    <td className="px-4 py-3.5 min-w-[130px] max-w-[240px]">
                      <Pill config={withdrawalStatusConfig[w.status]} fallback={humanize(w.status)} />
                      {w.failureMessage && <p className="text-xs text-error mt-1">{w.failureMessage}</p>}
                    </td>
                    <td className="px-4 py-3.5"><CopyId value={w.gatewayPayoutId} /></td>
                    <td className="px-4 py-3.5 text-xs text-outline whitespace-nowrap">{formatDate(w.createdAt, true)}</td>
                    <td className="px-4 py-3.5 text-xs text-outline whitespace-nowrap">
                      {w.settledAt ? formatDate(w.settledAt, true) : w.status === "in_transit" ? "On the way…" : "—"}
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
                          <span className="material-symbols-outlined text-[48px] text-outline-variant block mb-2">output</span>
                          {filter === "all"
                            ? "No withdrawals yet. They appear here when a customer, vendor or rider cashes out their wallet to a card."
                            : "No withdrawals with this status."}
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
