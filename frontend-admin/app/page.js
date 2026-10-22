"use client";

import { useState, useSyncExternalStore } from "react";
import { useRouter } from "next/navigation";
import { login, saveToken, wasSessionExpired, clearSessionExpired, SESSION_EXPIRED_MESSAGE } from "./lib/api";
import { usePublicConfig } from "./lib/hooks";

// The "session expired" flag lives in sessionStorage; read it without a hydration mismatch
const noopSubscribe = () => () => {};

export default function LoginPage() {
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [error, setError] = useState("");
  const [loading, setLoading] = useState(false);
  const [noticeDismissed, setNoticeDismissed] = useState(false);
  const sessionExpired = useSyncExternalStore(noopSubscribe, wasSessionExpired, () => false);
  const router = useRouter();
  const publicConfig = usePublicConfig();
  // Demo sign-in is only offered when the backend runs in development mode
  const demoAccounts = publicConfig?.features?.demoLogin
    ? (publicConfig.demoAccounts || []).filter((a) => a.role === "admin")
    : [];

  function handleSubmit(e) {
    e.preventDefault();
    signIn(email, password);
  }

  function handleDemoLogin(account) {
    setEmail(account.email);
    setPassword(account.password);
    signIn(account.email, account.password);
  }

  async function signIn(signInEmail, signInPassword) {
    setError("");
    setLoading(true);
    setNoticeDismissed(true);
    clearSessionExpired();

    try {
      const res = await login(signInEmail, signInPassword);

      if (res.success && res.data.user.role === "admin") {
        saveToken(res.data.token);
        router.push("/dashboard");
      } else if (res.success && res.data.user.role !== "admin") {
        setError("Access denied. Admin credentials required.");
      } else {
        setError(res.message || "Login failed");
      }
    } catch (err) {
      setError(err.message || "Login failed. Check your credentials.");
    } finally {
      setLoading(false);
    }
  }

  return (
    <div className="min-h-screen bg-background flex items-center justify-center p-4">
      <div className="w-full max-w-md">
        {/* Logo */}
        <div className="text-center mb-8">
          <div className="inline-flex items-center gap-3 mb-2">
            <div className="w-12 h-12 bg-primary rounded-xl flex items-center justify-center">
              <svg className="w-7 h-7 text-white" fill="none" viewBox="0 0 24 24" stroke="currentColor" strokeWidth={2}>
                <path strokeLinecap="round" strokeLinejoin="round" d="M13 10V3L4 14h7v7l9-11h-7z" />
              </svg>
            </div>
            <h1 className="text-3xl font-bold text-primary tracking-tight">Vendra</h1>
          </div>
          <p className="text-on-surface-variant text-sm">Admin Control Panel</p>
        </div>

        {/* Login Card */}
        <div className="bg-white rounded-2xl shadow-lg shadow-primary/5 p-8 border border-outline-variant/30">
          <h2 className="text-xl font-bold text-on-surface mb-1">Welcome back</h2>
          <p className="text-on-surface-variant text-sm mb-6">Sign in to your admin account</p>

          {sessionExpired && !noticeDismissed && !error && (
            <div className="bg-amber-50 border border-amber-200 text-amber-800 px-4 py-3 rounded-xl mb-4 text-sm flex items-center gap-2">
              <span className="material-symbols-outlined text-[18px] shrink-0">schedule</span>
              {SESSION_EXPIRED_MESSAGE}
            </div>
          )}

          {error && (
            <div className="bg-red-50 border border-red-200 text-red-700 px-4 py-3 rounded-xl mb-4 text-sm flex items-center gap-2">
              <svg className="w-4 h-4 shrink-0" fill="none" viewBox="0 0 24 24" stroke="currentColor" strokeWidth={2}>
                <path strokeLinecap="round" strokeLinejoin="round" d="M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-2.5L13.732 4c-.77-.833-1.732-.833-2.5 0L4.268 16.5c-.77.833.192 2.5 1.732 2.5z" />
              </svg>
              {error}
            </div>
          )}

          <form onSubmit={handleSubmit} className="space-y-4">
            <div>
              <label className="block text-sm font-semibold text-on-surface mb-1.5">Email</label>
              <input
                type="email"
                value={email}
                onChange={(e) => setEmail(e.target.value)}
                placeholder="admin@vendra.pk"
                required
                className="w-full px-4 py-3 bg-surface-container-low border border-outline-variant/50 rounded-xl text-on-surface placeholder:text-outline focus:outline-none focus:ring-2 focus:ring-primary/30 focus:border-primary transition-all"
              />
            </div>

            <div>
              <label className="block text-sm font-semibold text-on-surface mb-1.5">Password</label>
              <input
                type="password"
                value={password}
                onChange={(e) => setPassword(e.target.value)}
                placeholder="••••••••"
                required
                className="w-full px-4 py-3 bg-surface-container-low border border-outline-variant/50 rounded-xl text-on-surface placeholder:text-outline focus:outline-none focus:ring-2 focus:ring-primary/30 focus:border-primary transition-all"
              />
            </div>

            <button
              type="submit"
              disabled={loading}
              className="w-full py-3 bg-primary text-white font-semibold rounded-xl hover:bg-primary-container transition-colors disabled:opacity-50 disabled:cursor-not-allowed flex items-center justify-center gap-2"
            >
              {loading ? (
                <>
                  <svg className="animate-spin w-5 h-5" fill="none" viewBox="0 0 24 24"><circle className="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" strokeWidth="4" /><path className="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4z" /></svg>
                  Signing in...
                </>
              ) : (
                "Sign In"
              )}
            </button>
          </form>

          {demoAccounts.length > 0 && (
            <div className="mt-6 pt-4 border-t border-outline-variant/30">
              <div className="flex items-center gap-2 mb-2">
                <span className="text-[10px] font-semibold uppercase tracking-wide px-1.5 py-0.5 rounded-md bg-amber-100 text-amber-800">
                  Development
                </span>
                <p className="text-xs text-outline">Demo accounts: click to sign in</p>
              </div>
              <div className="space-y-2">
                {demoAccounts.map((account) => (
                  <button
                    key={account.email}
                    type="button"
                    disabled={loading}
                    onClick={() => handleDemoLogin(account)}
                    className="w-full flex items-center gap-3 px-3 py-2.5 rounded-xl border border-outline-variant/40 bg-surface-container-low/50 hover:bg-surface-container-low hover:border-primary/40 transition-colors text-left disabled:opacity-50"
                  >
                    <div className="w-8 h-8 rounded-full bg-primary/10 flex items-center justify-center shrink-0">
                      <span className="material-symbols-outlined text-primary text-[18px]">admin_panel_settings</span>
                    </div>
                    <div className="flex-1 min-w-0">
                      <p className="text-sm font-semibold text-on-surface truncate">{account.name}</p>
                      <p className="text-xs text-outline truncate">
                        {account.email}
                        {account.note ? ` · ${account.note}` : ""}
                      </p>
                    </div>
                    <span className="material-symbols-outlined text-outline text-[18px]">login</span>
                  </button>
                ))}
              </div>
            </div>
          )}
        </div>

        <p className="text-center text-xs text-outline mt-6">
          Vendra Multi-Vendor Digital Marketplace © 2026
        </p>
      </div>
    </div>
  );
}
