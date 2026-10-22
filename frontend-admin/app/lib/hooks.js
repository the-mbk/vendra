"use client";

// ══════════════════════════════════════════════════════════════
// Vendra Admin Dashboard - Shared hooks
// ══════════════════════════════════════════════════════════════

import { useCallback, useEffect, useState } from "react";
import { useRouter } from "next/navigation";
import { getPublicConfig, isAuthError } from "./api";

/**
 * GET /api/public-config?role=admin, fetched once and shared.
 * Returns null until it loads (or if the API is unreachable), so callers
 * should treat "no config" as production: no badge, no demo accounts.
 */
export function usePublicConfig() {
  const [config, setConfig] = useState(null);

  useEffect(() => {
    let cancelled = false;
    getPublicConfig()
      .then((data) => { if (!cancelled) setConfig(data); })
      .catch(() => { /* optional: the UI falls back to production behaviour */ });
    return () => { cancelled = true; };
  }, []);

  return config;
}

/** `value`, updated only after it has stopped changing for `delay` ms (for search-as-you-type) */
export function useDebouncedValue(value, delay = 300) {
  const [debounced, setDebounced] = useState(value);

  useEffect(() => {
    const timer = setTimeout(() => setDebounced(value), delay);
    return () => clearTimeout(timer);
  }, [value, delay]);

  return debounced;
}

/**
 * A paged admin list (`?status=&search=&limit=&offset=` → `{ data, meta: { hasMore, nextOffset } }`).
 * Reloads from the first page whenever `status` or `search` changes; `loadMore()` appends the next page.
 * While a new search loads, the previous rows stay on screen (`refreshing`).
 */
export function usePagedList(fetchPage, status, search = "") {
  const router = useRouter();
  // `result.status`/`result.search` record which filter the rows belong to, so a filter change
  // shows the loader until its first page arrives (no synchronous reset needed).
  const [result, setResult] = useState(null); // { status, search, reloadKey, items, meta, error }
  const [loadingMore, setLoadingMore] = useState(false);
  const [moreError, setMoreError] = useState(null);
  const [reloadKey, setReloadKey] = useState(0);
  const term = search.trim();

  useEffect(() => {
    const token = localStorage.getItem("vendra_admin_token");
    if (!token) { router.push("/"); return; }

    let cancelled = false;
    fetchPage({ status: status === "all" ? undefined : status, search: term || undefined, offset: 0 })
      .then((res) => {
        if (!cancelled) setResult({ status, search: term, reloadKey, items: res.data || [], meta: res.meta || {}, error: null });
      })
      .catch((err) => {
        if (isAuthError(err)) router.push("/");
        if (!cancelled) setResult({ status, search: term, reloadKey, items: [], meta: {}, error: err.message });
      });
    return () => { cancelled = true; };
  }, [fetchPage, status, term, reloadKey, router]);

  const loadMore = useCallback(async () => {
    if (!result?.meta?.hasMore || loadingMore) return;
    setLoadingMore(true);
    setMoreError(null);
    try {
      const res = await fetchPage({
        status: result.status === "all" ? undefined : result.status,
        search: result.search || undefined,
        offset: result.meta.nextOffset,
      });
      setResult((prev) =>
        prev && prev.status === result.status && prev.search === result.search
          ? { ...prev, items: [...prev.items, ...(res.data || [])], meta: res.meta || {} }
          : prev
      );
    } catch (err) {
      if (isAuthError(err)) router.push("/");
      setMoreError(err.message);
    } finally {
      setLoadingMore(false);
    }
  }, [fetchPage, result, loadingMore, router]);

  const reload = useCallback(() => {
    setMoreError(null);
    setReloadKey((k) => k + 1);
  }, []);

  const current =
    result && result.status === status && result.search === term && result.reloadKey === reloadKey ? result : null;
  // Same status tab: keep showing the previous rows while a reload or new search loads
  const sameTab = result?.status === status;

  return {
    loading: !current,
    items: current?.items ?? (sameTab ? result.items : []),
    // The search term the rows on screen were loaded for ("" = none)
    search: (current ?? (sameTab ? result : null))?.search ?? "",
    hasMore: Boolean(current?.meta?.hasMore),
    error: current?.error ?? null,
    loadingMore,
    moreError,
    loadMore,
    reload,
    refreshing: !current && sameTab,
  };
}
