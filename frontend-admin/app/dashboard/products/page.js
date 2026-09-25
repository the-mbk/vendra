"use client";

import { useState, useEffect } from "react";
import { useRouter } from "next/navigation";
import { getProducts, approveProduct, hideProduct, fileUrl, isAuthError } from "../../lib/api";
import { PageLoader, ErrorBox, Spinner, Th, TabButton, formatRs, formatDate, notifyCountsChanged } from "../../lib/ui";

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
    <div className="grid grid-cols-4 gap-3 min-w-[240px]">
      {items.map((i) => (
        <div key={i.label}>
          <p className="text-[10px] font-semibold uppercase tracking-wide text-outline">{i.label}</p>
          <p className={`text-sm font-bold ${i.className}`}>{i.value ?? 0}</p>
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

export default function ProductsPage() {
  const [tab, setTab] = useState("pending");
  const [products, setProducts] = useState([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(null);
  const [reloadKey, setReloadKey] = useState(0);
  const [actionLoading, setActionLoading] = useState(null);
  const [confirmHideId, setConfirmHideId] = useState(null);
  const [message, setMessage] = useState(null); // { type: "success" | "error", text }
  const router = useRouter();

  useEffect(() => {
    const token = localStorage.getItem("vendra_admin_token");
    if (!token) { router.push("/"); return; }

    let cancelled = false;
    async function fetchProducts() {
      try {
        const res = await getProducts(tab);
        if (cancelled) return;
        setProducts(res.data);
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

  function changeTab(next) {
    if (next === tab) return;
    setTab(next);
    setLoading(true);
    setConfirmHideId(null);
  }

  async function handleApprove(product) {
    setActionLoading(product.id);
    setMessage(null);
    try {
      const res = await approveProduct(product.id);
      setMessage({ type: "success", text: res.message || `"${product.name}" is now live for customers.` });
      setReloadKey((k) => k + 1);
      notifyCountsChanged();
    } catch (err) {
      setMessage({ type: "error", text: `Failed to approve "${product.name}": ${err.message}` });
    } finally {
      setActionLoading(null);
    }
  }

  async function handleHide(product) {
    setActionLoading(product.id);
    setConfirmHideId(null);
    setMessage(null);
    try {
      const res = await hideProduct(product.id);
      setMessage({ type: "success", text: res.message || `"${product.name}" is hidden and back in the pending queue.` });
      setReloadKey((k) => k + 1);
      notifyCountsChanged();
    } catch (err) {
      setMessage({ type: "error", text: `Failed to hide "${product.name}": ${err.message}` });
    } finally {
      setActionLoading(null);
    }
  }

  const pendingCount = tab === "pending" ? products.length : products.filter((p) => !p.isApproved).length;

  return (
    <div>
      {/* Header */}
      <div className="flex items-center justify-between mb-6">
        <div>
          <h1 className="text-2xl font-bold text-on-surface">Catalog Approval</h1>
          <p className="text-on-surface-variant text-sm mt-1">
            New vendor products stay hidden from customers until an admin approves them.
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

      {/* Filter Tabs */}
      <div className="flex gap-2 mb-6">
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
        <div className="bg-white rounded-2xl border border-outline-variant/20 shadow-sm overflow-hidden">
          <div className="overflow-x-auto">
            <table className="w-full">
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
                {products.map((product) => (
                  <tr key={product.id} className="hover:bg-surface-container-low/30 transition-colors align-top">
                    <td className="px-5 py-4 max-w-[340px]">
                      <div className="flex items-start gap-3">
                        <ProductThumb imageUrl={product.imageUrl} name={product.name} />
                        <div className="min-w-0">
                          <p className="text-sm font-semibold text-on-surface">{product.name}</p>
                          {product.description && (
                            <p className="text-xs text-outline mt-0.5 line-clamp-2">{product.description}</p>
                          )}
                          <p className="text-[11px] text-outline mt-1">
                            {product.barcode ? <>Barcode <code className="font-mono">{product.barcode}</code> • </> : null}
                            Added {formatDate(product.createdAt)}
                          </p>
                        </div>
                      </div>
                    </td>
                    <td className="px-5 py-4 text-sm text-on-surface whitespace-nowrap">{product.storeName}</td>
                    <td className="px-5 py-4">
                      <span className="text-xs font-medium bg-surface-container-low text-on-surface-variant px-2 py-1 rounded-lg whitespace-nowrap">
                        {product.categoryName || "Uncategorised"}
                      </span>
                    </td>
                    <td className="px-5 py-4 text-sm font-semibold text-on-surface whitespace-nowrap">{formatRs(product.price)}</td>
                    <td className="px-5 py-4"><StockCell product={product} /></td>
                    <td className="px-5 py-4"><ApprovalBadge approved={product.isApproved} /></td>
                    <td className="px-5 py-4 text-right whitespace-nowrap">
                      {actionLoading === product.id ? (
                        <Spinner className="w-5 h-5 inline-block" />
                      ) : !product.isApproved ? (
                        <button
                          onClick={() => handleApprove(product)}
                          className="text-xs font-semibold px-3 py-1.5 rounded-lg bg-emerald-50 text-emerald-700 hover:bg-emerald-100 transition-colors"
                        >
                          ✓ Approve
                        </button>
                      ) : confirmHideId === product.id ? (
                        <div className="inline-flex items-center gap-2">
                          <span className="text-xs text-on-surface-variant">Hide from customers?</span>
                          <button
                            onClick={() => handleHide(product)}
                            className="text-xs font-semibold px-3 py-1.5 rounded-lg bg-red-600 text-white hover:bg-red-700 transition-colors"
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
                    </td>
                  </tr>
                ))}

                {products.length === 0 && (
                  <tr>
                    <td colSpan={7} className="text-center py-12 text-on-surface-variant">
                      <span className="material-symbols-outlined text-[48px] text-outline-variant block mb-2">
                        {tab === "pending" ? "task_alt" : "search_off"}
                      </span>
                      {tab === "pending" ? "No products are waiting for approval." : "No products found for this filter."}
                    </td>
                  </tr>
                )}
              </tbody>
            </table>
          </div>
        </div>
      )}
    </div>
  );
}
