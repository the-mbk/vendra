"use client";

import { useState, useEffect, useRef } from "react";
import { useRouter } from "next/navigation";
import { getProducts, approveProduct, hideProduct, fileUrl, isAuthError } from "../../lib/api";
import {
  PageLoader, ErrorBox, Spinner, Th, TabButton, SearchBox, NoSearchResults,
  formatRs, formatNumber, formatDate, matchesSearch, notifyCountsChanged,
} from "../../lib/ui";

const tabs = [
  { key: "pending", label: "Pending" },
  { key: "approved", label: "Approved" },
  { key: "all", label: "All" },
];

function StockCell({ product }) {
  const items = [
    { label: "Private", value: product.privateStock, className: "text-on-surface" },
    { label: "Buffer", value: product.buffer, className: "text-amber-700" },
    { label: "Reserved", value: product.reservedQuantity, className: "text-blue-700" },
    { label: "Public", value: product.publicStock, className: "text-emerald-700" },
  ];
  return (
    <div className="grid grid-cols-2 gap-x-4 gap-y-1 min-w-[150px]">
      {items.map((i) => (
        <div key={i.label} className="flex items-baseline justify-between gap-2">
          <span className="text-[10px] font-semibold uppercase tracking-wide text-outline">{i.label}</span>
          <span className={`text-sm font-bold tabular-nums ${i.className}`}>{i.value ?? 0}</span>
        </div>
      ))}
    </div>
  );
}

/** Small product photo; neutral placeholder when there is none or it fails to load */
function ProductThumb({ imageUrl, name }) {
  const src = fileUrl(imageUrl);
  const [failedSrc, setFailedSrc] = useState(null);

  if (!src || failedSrc === src) {
    return (
      <div
        className="w-12 h-12 rounded-lg bg-surface-container-low border border-outline-variant/30 flex items-center justify-center shrink-0"
        title="No photo"
      >
        <span className="material-symbols-outlined text-[22px] text-outline-variant">image</span>
      </div>
    );
  }

  return (
    // eslint-disable-next-line @next/next/no-img-element -- product photos are served by the API host
    <img
      src={src}
      alt={name}
      loading="lazy"
      onError={() => setFailedSrc(src)}
      className="w-12 h-12 rounded-lg object-cover border border-outline-variant/30 bg-surface-container-low shrink-0"
    />
  );
}

function ApprovalBadge({ approved }) {
  return (
    <span
      className={`inline-flex items-center gap-1 px-2.5 py-1 rounded-full text-xs font-semibold whitespace-nowrap ${
        approved ? "bg-emerald-100 text-emerald-700" : "bg-amber-100 text-amber-700"
      }`}
    >
      <span className={`w-1.5 h-1.5 rounded-full ${approved ? "bg-emerald-500" : "bg-amber-500"}`} />
      {approved ? "Live" : "Pending"}
    </span>
  );
}

function ProductDetailModal({ product, onClose, onApprove, onHide, actionLoading }) {
  const [confirmHide, setConfirmHide] = useState(false);
  useEffect(() => {
    function onKey(e) {
      if (e.key === "Escape") onClose();
    }
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [onClose]);

  const src = fileUrl(product.imageUrl);

  return (
    <div
      className="fixed inset-0 z-50 bg-black/50 flex items-center justify-center p-4 sm:p-6"
      onClick={onClose}
    >
      <div
        role="dialog"
        aria-modal="true"
        className="bg-surface-container-lowest rounded-2xl shadow-2xl w-full max-w-2xl max-h-[90vh] overflow-y-auto"
        onClick={(e) => e.stopPropagation()}
      >
        {/* Header */}
        <div className="flex items-start justify-between px-6 py-5 border-b border-outline-variant/20 sticky top-0 bg-surface-container-lowest z-10">
          <div className="flex items-center gap-3">
            <div className="w-11 h-11 bg-primary/10 rounded-xl flex items-center justify-center shrink-0">
              <span className="material-symbols-outlined text-primary text-[24px]">inventory_2</span>
            </div>
            <div>
              <div className="flex items-center gap-2">
                <h3 className="text-lg font-bold text-on-surface">Product #{product.id}</h3>
                <ApprovalBadge approved={product.isApproved} />
              </div>
              <p className="text-xs text-outline">{product.storeName}</p>
            </div>
          </div>
          <button
            onClick={onClose}
            aria-label="Close"
            className="material-symbols-outlined text-[22px] p-1.5 rounded-lg text-outline hover:text-on-surface hover:bg-surface-container-low transition-colors"
          >
            close
          </button>
        </div>

        {/* Content */}
        <div className="p-6 space-y-6">
          {/* Main Visual & Info Row */}
          <div className="flex flex-col sm:flex-row gap-5">
            {/* Image Preview */}
            <div className="w-full sm:w-44 h-44 rounded-xl border border-outline-variant/30 bg-surface-container-low overflow-hidden flex items-center justify-center shrink-0">
              {src ? (
                // eslint-disable-next-line @next/next/no-img-element
                <img src={src} alt={product.name} className="w-full h-full object-contain" />
              ) : (
                <div className="text-center text-outline">
                  <span className="material-symbols-outlined text-[40px]">image</span>
                  <p className="text-xs mt-1">No photo</p>
                </div>
              )}
            </div>

            {/* Title & Metadata */}
            <div className="flex-1 min-w-0 space-y-3">
              <div>
                <span className="text-xs font-semibold px-2 py-0.5 rounded-md bg-surface-container-low text-on-surface-variant">
                  {product.categoryName || "Uncategorised"}
                </span>
                <h2 className="text-lg font-bold text-on-surface mt-1">{product.name}</h2>
                <p className="text-xs text-outline">Listed on {formatDate(product.createdAt, true)}</p>
              </div>

              <div className="grid grid-cols-2 gap-2 text-xs">
                <div className="p-2.5 rounded-lg bg-surface-container-low/60 border border-outline-variant/20">
                  <p className="text-outline uppercase text-[10px] font-bold">Price</p>
                  <p className="text-sm font-bold text-primary mt-0.5">{formatRs(product.price)}</p>
                </div>
                <div className="p-2.5 rounded-lg bg-surface-container-low/60 border border-outline-variant/20">
                  <p className="text-outline uppercase text-[10px] font-bold">Weight</p>
                  <p className="text-sm font-semibold text-on-surface mt-0.5">
                    {product.weightGrams ? `${formatNumber(product.weightGrams)} g` : "Not listed"}
                  </p>
                </div>
                <div className="p-2.5 rounded-lg bg-surface-container-low/60 border border-outline-variant/20 col-span-2">
                  <p className="text-outline uppercase text-[10px] font-bold">Barcode</p>
                  <code className="text-xs font-mono font-semibold text-on-surface block mt-0.5">
                    {product.barcode || "No barcode registered"}
                  </code>
                </div>
              </div>
            </div>
          </div>

          {/* Description */}
          {product.description && (
            <div className="p-4 rounded-xl border border-outline-variant/20 bg-surface-container-low/30">
              <p className="text-xs font-bold uppercase tracking-wider text-outline mb-1">Product Description</p>
              <p className="text-sm text-on-surface leading-relaxed whitespace-pre-line">{product.description}</p>
            </div>
          )}

          {/* 4-Pillar Inventory Health */}
          <div className="rounded-xl border border-outline-variant/20 overflow-hidden">
            <div className="px-4 py-2 bg-surface-container-low/60 border-b border-outline-variant/20">
              <p className="text-xs font-bold uppercase tracking-wider text-outline">4-Pillar Real-Time Stock Audit</p>
            </div>
            <div className="grid grid-cols-2 sm:grid-cols-4 divide-y sm:divide-y-0 sm:divide-x divide-outline-variant/20 text-center p-3">
              <div className="p-2">
                <p className="text-[10px] font-bold uppercase text-outline">Private Shelf</p>
                <p className="text-xl font-bold text-on-surface mt-0.5">{product.privateStock ?? 0}</p>
                <p className="text-[10px] text-outline mt-0.5">Physical store stock</p>
              </div>
              <div className="p-2">
                <p className="text-[10px] font-bold uppercase text-amber-700">Walk-in Buffer</p>
                <p className="text-xl font-bold text-amber-700 mt-0.5">{product.buffer ?? 0}</p>
                <p className="text-[10px] text-outline mt-0.5">Held for counter sales</p>
              </div>
              <div className="p-2">
                <p className="text-[10px] font-bold uppercase text-blue-700">Online Reserved</p>
                <p className="text-xl font-bold text-blue-700 mt-0.5">{product.reservedQuantity ?? 0}</p>
                <p className="text-[10px] text-outline mt-0.5">Locked in open orders</p>
              </div>
              <div className="p-2">
                <p className="text-[10px] font-bold uppercase text-emerald-700">Public Live</p>
                <p className="text-xl font-bold text-emerald-700 mt-0.5">{product.publicStock ?? 0}</p>
                <p className="text-[10px] text-outline mt-0.5">Shelf − buffer − reserved</p>
              </div>
            </div>
          </div>

          {/* Quick Actions Footer */}
          <div className="flex items-center justify-between pt-2 border-t border-outline-variant/20">
            <button
              onClick={onClose}
              className="px-4 py-2 rounded-xl text-sm font-semibold border border-outline-variant/40 hover:bg-surface-container-low text-on-surface-variant transition-colors"
            >
              Close
            </button>
            {!product.isApproved ? (
              <button
                onClick={() => { onClose(); onApprove(product); }}
                disabled={actionLoading === product.id}
                className="px-5 py-2 rounded-xl text-sm font-semibold bg-emerald-600 text-white hover:bg-emerald-700 transition-colors flex items-center gap-1.5"
              >
                <span className="material-symbols-outlined text-[18px]">check_circle</span>
                Approve & Publish Live
              </button>
            ) : confirmHide ? (
              <div className="flex items-center gap-2">
                <span className="text-xs text-on-surface-variant">Confirm hiding?</span>
                <button
                  onClick={() => { onClose(); onHide(product); }}
                  disabled={actionLoading === product.id}
                  className="px-4 py-2 rounded-xl text-sm font-semibold bg-red-600 text-white hover:bg-red-700 transition-colors"
                >
                  Yes, Hide
                </button>
                <button
                  onClick={() => setConfirmHide(false)}
                  className="px-3 py-2 rounded-xl text-sm font-semibold bg-surface-container-low text-on-surface-variant hover:bg-surface-container transition-colors"
                >
                  Cancel
                </button>
              </div>
            ) : (
              <button
                onClick={() => setConfirmHide(true)}
                className="px-4 py-2 rounded-xl text-sm font-semibold bg-red-50 text-red-700 hover:bg-red-100 transition-colors flex items-center gap-1.5"
              >
                <span className="material-symbols-outlined text-[18px]">visibility_off</span>
                Hide Product
              </button>
            )}
          </div>
        </div>
      </div>
    </div>
  );
}

export default function ProductsPage() {
  const [tab, setTab] = useState("pending");
  const [products, setProducts] = useState([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(null);
  const [reloadKey, setReloadKey] = useState(0);
  const [actionLoading, setActionLoading] = useState(null);
  const [confirmHideId, setConfirmHideId] = useState(null);
  const [selectedProduct, setSelectedProduct] = useState(null);
  const [message, setMessage] = useState(null); // { type: "success" | "error", text }
  const [search, setSearch] = useState("");
  const router = useRouter();
  // Opened from a store's details (?store=Name): the first load starts filtered to that store
  const storeFilterApplied = useRef(false);

  useEffect(() => {
    const token = localStorage.getItem("vendra_admin_token");
    if (!token) { router.push("/"); return; }

    let cancelled = false;
    async function fetchProducts() {
      try {
        const res = await getProducts(tab);
        if (cancelled) return;
        setProducts(res.data);
        if (!storeFilterApplied.current) {
          storeFilterApplied.current = true;
          const store = new URLSearchParams(window.location.search).get("store");
          if (store) setSearch(store);
        }
        setError(null);
      } catch (err) {
        if (isAuthError(err)) router.push("/");
        if (!cancelled) setError(err.message);
      } finally {
        if (!cancelled) setLoading(false);
      }
    }
    fetchProducts();
    return () => { cancelled = true; };
  }, [router, tab, reloadKey]);

  async function handleApprove(product) {
    setActionLoading(product.id);
    try {
      const res = await approveProduct(product.id);
      setMessage({ type: "success", text: res.message || `"${product.name}" is now live in the catalogue.` });
      setReloadKey((k) => k + 1);
      notifyCountsChanged();
    } catch (err) {
      setMessage({ type: "error", text: err.message || "Failed to approve product" });
    } finally {
      setActionLoading(null);
    }
  }

  async function handleHide(product) {
    setActionLoading(product.id);
    try {
      const res = await hideProduct(product.id);
      setMessage({ type: "success", text: res.message || `"${product.name}" has been hidden from customers.` });
      setConfirmHideId(null);
      setReloadKey((k) => k + 1);
      notifyCountsChanged();
    } catch (err) {
      setMessage({ type: "error", text: err.message || "Failed to hide product" });
    } finally {
      setActionLoading(null);
    }
  }

  function changeTab(next) {
    setTab(next);
    setConfirmHideId(null);
    setMessage(null);
  }

  const filteredProducts = products.filter((p) =>
    matchesSearch(search, p.name, p.storeName, p.categoryName, p.barcode, p.description)
  );

  const pendingCount = products.filter((p) => !p.isApproved).length;

  return (
    <div>
      {/* Header */}
      <div className="flex items-center justify-between mb-6">
        <div>
          <h1 className="text-2xl font-bold text-on-surface">Product Catalog</h1>
          <p className="text-on-surface-variant text-sm mt-1">
            {products.length} products • {pendingCount} pending approval
          </p>
        </div>
      </div>

      {/* Stock legend */}
      <div className="bg-surface-container-low/60 border border-outline-variant/30 rounded-xl p-4 mb-6 flex items-start gap-3">
        <span className="material-symbols-outlined text-primary text-[22px]">info</span>
        <p className="text-xs text-on-surface-variant leading-relaxed">
          <span className="font-semibold text-on-surface">Private</span> is the vendor&apos;s real shelf stock.{" "}
          <span className="font-semibold text-amber-700">Buffer</span> units are kept back for walk-in customers,{" "}
          <span className="font-semibold text-blue-700">Reserved</span> units are locked by open online orders, and{" "}
          <span className="font-semibold text-emerald-700">Public</span> = private − buffer − reserved is what customers can buy online.
        </p>
      </div>

      {/* Filter Tabs + Search */}
      <div className="flex flex-wrap items-center justify-between gap-3 mb-6">
        <div className="flex gap-2">
          {tabs.map((t) => (
            <TabButton
              key={t.key}
              active={tab === t.key}
              onClick={() => changeTab(t.key)}
              count={t.key === "pending" && tab === "pending" ? pendingCount : 0}
            >
              {t.label}
            </TabButton>
          ))}
        </div>
        <SearchBox
          value={search}
          onChange={setSearch}
          placeholder="Search product, store, barcode or category"
          count={loading || error ? undefined : filteredProducts.length}
          total={loading || error ? undefined : products.length}
        />
      </div>

      {message && (
        <div
          className={`rounded-xl px-4 py-3 mb-4 text-sm flex items-center gap-2 border ${
            message.type === "success"
              ? "bg-emerald-50 border-emerald-200 text-emerald-800"
              : "bg-red-50 border-red-200 text-red-700"
          }`}
        >
          <span className="material-symbols-outlined text-[18px]">
            {message.type === "success" ? "check_circle" : "error"}
          </span>
          <span className="flex-1">{message.text}</span>
          <button onClick={() => setMessage(null)} className="material-symbols-outlined text-[18px] opacity-60 hover:opacity-100">
            close
          </button>
        </div>
      )}

      {loading ? (
        <PageLoader label="Loading products..." />
      ) : error ? (
        <ErrorBox title="Error loading products" message={error} />
      ) : (
        <div className="bg-surface-container-lowest rounded-2xl border border-outline-variant/20 shadow-sm overflow-hidden">
          <div className="overflow-x-auto">
            <table className="w-full sticky-actions">
              <thead>
                <tr className="bg-surface-container-low/50 border-b border-outline-variant/20">
                  <Th>Product</Th>
                  <Th>Store</Th>
                  <Th>Category</Th>
                  <Th>Price</Th>
                  <Th>Stock</Th>
                  <Th>Status</Th>
                  <Th align="right">Actions</Th>
                </tr>
              </thead>
              <tbody className="divide-y divide-outline-variant/10">
                {filteredProducts.map((product) => (
                  <tr key={product.id} className="hover:bg-surface-container-low/30 transition-colors align-top">
                    <td className="px-4 py-3.5 min-w-[240px] max-w-[320px]">
                      <button
                        onClick={() => setSelectedProduct(product)}
                        className="flex items-start gap-3 text-left group w-full"
                      >
                        <ProductThumb imageUrl={product.imageUrl} name={product.name} />
                        <div className="min-w-0">
                          <p className="text-sm font-semibold text-on-surface group-hover:text-primary transition-colors line-clamp-2" title={product.name}>
                            {product.name}
                          </p>
                          {product.description && (
                            <p className="text-xs text-outline mt-0.5 line-clamp-1" title={product.description}>{product.description}</p>
                          )}
                          <p className="text-[11px] text-outline mt-1 whitespace-nowrap">
                            {product.barcode ? <>Barcode <code className="font-mono">{product.barcode}</code> • </> : null}
                            Added {formatDate(product.createdAt)}
                          </p>
                        </div>
                      </button>
                    </td>
                    <td className="px-4 py-3.5 text-sm text-on-surface min-w-[130px] max-w-[170px]">{product.storeName}</td>
                    <td className="px-4 py-3.5">
                      <span className="text-xs font-medium bg-surface-container-low text-on-surface-variant px-2 py-1 rounded-lg whitespace-nowrap">
                        {product.categoryName || "Uncategorised"}
                      </span>
                    </td>
                    <td className="px-4 py-3.5 text-sm font-semibold text-on-surface whitespace-nowrap">{formatRs(product.price)}</td>
                    <td className="px-4 py-3.5"><StockCell product={product} /></td>
                    <td className="px-4 py-3.5"><ApprovalBadge approved={product.isApproved} /></td>
                    <td className="px-4 py-3.5 text-right whitespace-nowrap">
                      <div className="flex items-center justify-end gap-1.5">
                        <button
                          onClick={() => setSelectedProduct(product)}
                          className="text-xs font-semibold px-2.5 py-1.5 rounded-lg border border-outline-variant/40 hover:bg-surface-container-low text-on-surface-variant transition-colors inline-flex items-center gap-1"
                        >
                          <span className="material-symbols-outlined text-[15px]">info</span>
                          Details
                        </button>
                        {actionLoading === product.id ? (
                          <Spinner className="w-5 h-5 inline-block" />
                        ) : !product.isApproved ? (
                          <button
                            onClick={() => handleApprove(product)}
                            className="text-xs font-semibold px-3 py-1.5 rounded-lg bg-emerald-50 text-emerald-700 hover:bg-emerald-100 transition-colors"
                          >
                            Approve
                          </button>
                        ) : confirmHideId === product.id ? (
                          <div className="inline-flex items-center gap-2">
                            <span className="text-xs text-on-surface-variant">Hide?</span>
                            <button
                              onClick={() => handleHide(product)}
                              className="text-xs font-semibold px-3 py-1.5 rounded-lg bg-red-600 text-white hover:bg-red-700 dark:hover:bg-red-500 transition-colors"
                            >
                              Yes, hide
                            </button>
                            <button
                              onClick={() => setConfirmHideId(null)}
                              className="text-xs font-semibold px-3 py-1.5 rounded-lg bg-surface-container-low text-on-surface-variant hover:bg-surface-container transition-colors"
                            >
                              Cancel
                            </button>
                          </div>
                        ) : (
                          <button
                            onClick={() => setConfirmHideId(product.id)}
                            className="text-xs font-semibold px-3 py-1.5 rounded-lg bg-red-50 text-red-700 hover:bg-red-100 transition-colors"
                          >
                            Hide
                          </button>
                        )}
                      </div>
                    </td>
                  </tr>
                ))}

                {filteredProducts.length === 0 && (
                  <tr>
                    <td colSpan={7} className="text-center py-12 text-on-surface-variant">
                      {products.length > 0 ? (
                        <NoSearchResults query={search} onClear={() => setSearch("")} />
                      ) : (
                        <>
                          <span className="material-symbols-outlined text-[48px] text-outline-variant block mb-2">
                            {tab === "pending" ? "task_alt" : "search_off"}
                          </span>
                          {tab === "pending" ? "No products are waiting for approval." : "No products found for this filter."}
                        </>
                      )}
                    </td>
                  </tr>
                )}
              </tbody>
            </table>
          </div>
        </div>
      )}

      {/* Product Inspection Modal */}
      {selectedProduct && (
        <ProductDetailModal
          product={selectedProduct}
          onClose={() => setSelectedProduct(null)}
          onApprove={handleApprove}
          onHide={handleHide}
          actionLoading={actionLoading}
        />
      )}
    </div>
  );
}
