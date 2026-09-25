"use client";

import { useEffect, useState } from "react";
import { useRouter, usePathname } from "next/navigation";
import { clearToken, getDashboardStats, SESSION_EXPIRED_EVENT } from "../lib/api";
import { COUNTS_EVENT } from "../lib/ui";

const navSections = [
  {
    title: "Overview",
    items: [{ label: "Dashboard", icon: "grid_view", href: "/dashboard" }],
  },
  {
    title: "Management",
    items: [
      { label: "Vendors", icon: "storefront", href: "/dashboard/vendors", badge: "pendingVendors" },
      { label: "Products", icon: "inventory_2", href: "/dashboard/products", badge: "pendingProducts" },
      { label: "Riders", icon: "two_wheeler", href: "/dashboard/riders" },
      { label: "Users", icon: "group", href: "/dashboard/users" },
    ],
  },
  {
    title: "Operations",
    items: [
      { label: "Orders", icon: "receipt_long", href: "/dashboard/orders" },
      { label: "Disputes", icon: "gavel", href: "/dashboard/disputes", badge: "openDisputes", urgent: true },
      { label: "Finance", icon: "account_balance", href: "/dashboard/finance" },
    ],
  },
  {
    title: "System",
    items: [{ label: "Policies", icon: "tune", href: "/dashboard/policies" }],
  },
];

const navItems = navSections.flatMap((s) => s.items);

function isActivePath(pathname, href) {
  if (href === "/dashboard") return pathname === href;
  return pathname === href || pathname.startsWith(`${href}/`);
}

function pageTitle(pathname) {
  if (/^\/dashboard\/disputes\/[^/]+/.test(pathname)) return "Dispute Review";
  return navItems.find((i) => isActivePath(pathname, i.href))?.label || "Dashboard";
}

export default function DashboardLayout({ children }) {
  const router = useRouter();
  const pathname = usePathname();
  const [counts, setCounts] = useState({});

  // Badge counts: refreshed on navigation and after admin actions
  useEffect(() => {
    let cancelled = false;

    async function loadCounts() {
      try {
        const res = await getDashboardStats();
        if (cancelled) return;
        setCounts({
          openDisputes: Number(res.data?.openDisputes) || 0,
          pendingProducts: Number(res.data?.pendingProducts) || 0,
          pendingVendors: Number(res.data?.vendors?.pending) || 0,
        });
      } catch {
        // Badges are optional; pages handle auth errors themselves
      }
    }

    loadCounts();
    window.addEventListener(COUNTS_EVENT, loadCounts);
    return () => {
      cancelled = true;
      window.removeEventListener(COUNTS_EVENT, loadCounts);
    };
  }, [pathname]);

  // Any API call that reports an expired/invalid token (see lib/api.js) sends the
  // admin back to the login page, which explains why.
  useEffect(() => {
    function onSessionExpired() {
      router.replace("/");
    }
    window.addEventListener(SESSION_EXPIRED_EVENT, onSessionExpired);
    return () => window.removeEventListener(SESSION_EXPIRED_EVENT, onSessionExpired);
  }, [router]);

  function handleLogout() {
    clearToken();
    router.push("/");
  }

  return (
    <div className="flex min-h-screen bg-background">
      {/* Sidebar */}
      <aside className="w-[260px] bg-white border-r border-outline-variant/30 flex flex-col fixed h-screen">
        {/* Logo */}
        <div className="p-5 border-b border-outline-variant/20">
          <div className="flex items-center gap-3">
            <div className="w-10 h-10 bg-primary rounded-xl flex items-center justify-center shrink-0">
              <svg className="w-6 h-6 text-white" fill="none" viewBox="0 0 24 24" stroke="currentColor" strokeWidth={2}>
                <path strokeLinecap="round" strokeLinejoin="round" d="M13 10V3L4 14h7v7l9-11h-7z" />
              </svg>
            </div>
            <div>
              <h1 className="text-lg font-bold text-primary leading-tight">Vendra</h1>
              <p className="text-[11px] text-outline font-medium">Admin Panel</p>
            </div>
          </div>
        </div>

        {/* Navigation */}
        <nav className="flex-1 min-h-0 py-4 px-3 overflow-y-auto">
          {navSections.map((section) => (
            <div key={section.title} className="mb-4">
              <p className="text-[11px] font-semibold text-outline uppercase tracking-wider px-3 mb-2">{section.title}</p>
              {section.items.map((item) => {
                const isActive = isActivePath(pathname, item.href);
                const count = item.badge ? counts[item.badge] || 0 : 0;
                return (
                  <button
                    key={item.href}
                    onClick={() => router.push(item.href)}
                    className={`w-full flex items-center gap-3 px-3 py-2.5 rounded-xl mb-1 text-sm font-medium transition-all ${
                      isActive
                        ? "bg-primary text-white shadow-md shadow-primary/20"
                        : "text-on-surface-variant hover:bg-surface-container-low hover:text-on-surface"
                    }`}
                  >
                    <span className="material-symbols-outlined text-[20px]">{item.icon}</span>
                    <span className="flex-1 text-left">{item.label}</span>
                    {count > 0 && (
                      <span
                        className={`min-w-[20px] h-5 px-1.5 rounded-full text-[11px] font-bold flex items-center justify-center ${
                          isActive
                            ? "bg-white/20 text-white"
                            : item.urgent
                              ? "bg-error text-white"
                              : "bg-amber-100 text-amber-700"
                        }`}
                      >
                        {count}
                      </span>
                    )}
                  </button>
                );
              })}
            </div>
          ))}
        </nav>

        {/* Admin Info & Logout */}
        <div className="p-4 border-t border-outline-variant/20">
          <div className="flex items-center gap-3 mb-3">
            <div className="w-9 h-9 bg-primary/10 rounded-full flex items-center justify-center">
              <span className="text-primary font-bold text-sm">VA</span>
            </div>
            <div className="flex-1 min-w-0">
              <p className="text-sm font-semibold text-on-surface truncate">Vendra Admin</p>
              <p className="text-[11px] text-outline truncate">admin@vendra.pk</p>
            </div>
          </div>
          <button
            onClick={handleLogout}
            className="w-full flex items-center justify-center gap-2 px-3 py-2 rounded-xl text-sm font-medium text-error border border-error/20 hover:bg-red-50 transition-colors"
          >
            <span className="material-symbols-outlined text-[18px]">logout</span>
            Logout
          </button>
        </div>
      </aside>

      {/* Main content */}
      <main className="flex-1 ml-[260px]">
        {/* Top header */}
        <header className="h-16 bg-white/80 backdrop-blur-md border-b border-outline-variant/20 flex items-center justify-between px-8 sticky top-0 z-10">
          <div>
            <h2 className="text-lg font-bold text-on-surface">
              {pageTitle(pathname)}
            </h2>
          </div>
          <div className="flex items-center gap-3">
            {counts.openDisputes > 0 && (
              <button
                onClick={() => router.push("/dashboard/disputes")}
                className="flex items-center gap-1.5 px-3 py-1.5 rounded-full bg-red-50 text-red-700 text-xs font-semibold hover:bg-red-100 transition-colors"
              >
                <span className="material-symbols-outlined text-[16px]">warning</span>
                {counts.openDisputes} open dispute{counts.openDisputes > 1 ? "s" : ""}
              </button>
            )}
            <button className="w-9 h-9 rounded-xl bg-surface-container-low flex items-center justify-center hover:bg-surface-container transition-colors">
              <span className="material-symbols-outlined text-on-surface-variant text-[20px]">notifications</span>
            </button>
          </div>
        </header>

        {/* Page content */}
        <div className="p-8">{children}</div>
      </main>
    </div>
  );
}
