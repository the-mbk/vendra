"use client";

import { useRouter, usePathname } from "next/navigation";
import { clearToken } from "../lib/api";

const navItems = [
  { label: "Dashboard", icon: "grid_view", href: "/dashboard" },
  { label: "Vendors", icon: "storefront", href: "/dashboard/vendors" },
  { label: "Orders", icon: "receipt_long", href: "/dashboard/orders" },
  { label: "Users", icon: "group", href: "/dashboard/users" },
];

export default function DashboardLayout({ children }) {
  const router = useRouter();
  const pathname = usePathname();

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
        <nav className="flex-1 py-4 px-3">
          <p className="text-[11px] font-semibold text-outline uppercase tracking-wider px-3 mb-3">Main Menu</p>
          {navItems.map((item) => {
            const isActive = pathname === item.href;
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
                {item.label}
              </button>
            );
          })}
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
              {navItems.find((i) => i.href === pathname)?.label || "Dashboard"}
            </h2>
          </div>
          <div className="flex items-center gap-3">
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
