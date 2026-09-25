// ══════════════════════════════════════════════════════════════
// Vendra Admin Dashboard - API Helper
// Handles all communication with the Express backend
// ══════════════════════════════════════════════════════════════

const API_BASE = process.env.NEXT_PUBLIC_API_URL || "http://localhost:3000/api";

// Server root without the trailing /api — used for uploaded files (e.g. /uploads/x.jpg)
const FILE_BASE = API_BASE.replace(/\/+$/, "").replace(/\/api$/, "");

/**
 * Turn a server file path (e.g. "/uploads/x.jpg") into a full URL.
 * Absolute URLs are returned unchanged.
 */
export function fileUrl(path) {
  if (!path) return "";
  if (/^https?:\/\//i.test(path)) return path;
  return `${FILE_BASE}${path.startsWith("/") ? "" : "/"}${path}`;
}

/**
 * Get auth token from localStorage
 */
function getToken() {
  if (typeof window === "undefined") return null;
  return localStorage.getItem("vendra_admin_token");
}

/**
 * Save auth token
 */
export function saveToken(token) {
  localStorage.setItem("vendra_admin_token", token);
}

/**
 * Clear auth
 */
export function clearToken() {
  localStorage.removeItem("vendra_admin_token");
}

// ── Session expiry ──
// A 401 with one of these codes means the stored token is no longer usable.
const SESSION_EXPIRED_CODES = ["TOKEN_EXPIRED", "INVALID_TOKEN"];
const SESSION_EXPIRED_KEY = "vendra_admin_session_expired";

/** Fired on window when an API call reports an expired/invalid session */
export const SESSION_EXPIRED_EVENT = "vendra:session-expired";

export const SESSION_EXPIRED_MESSAGE = "Your session has expired. Please sign in again.";

function handleSessionExpired() {
  if (typeof window === "undefined") return;
  clearToken();
  try {
    sessionStorage.setItem(SESSION_EXPIRED_KEY, "1");
  } catch {
    // Storage unavailable: the redirect still happens, just without the message
  }
  window.dispatchEvent(new Event(SESSION_EXPIRED_EVENT));
}

/** True when the last session ended because the token expired (shown on the login page) */
export function wasSessionExpired() {
  try {
    return sessionStorage.getItem(SESSION_EXPIRED_KEY) === "1";
  } catch {
    return false;
  }
}

export function clearSessionExpired() {
  try {
    sessionStorage.removeItem(SESSION_EXPIRED_KEY);
  } catch {
    // ignore
  }
}

/**
 * Generic fetch wrapper with auth headers
 */
async function apiFetch(endpoint, options = {}) {
  const token = getToken();
  const headers = {
    "Content-Type": "application/json",
    ...(token && { Authorization: `Bearer ${token}` }),
    ...options.headers,
  };

  const res = await fetch(`${API_BASE}${endpoint}`, {
    ...options,
    headers,
  });

  let data = {};
  try {
    data = await res.json();
  } catch {
    data = {};
  }

  if (!res.ok) {
    const error = new Error(data.message || "API request failed");
    error.status = res.status;
    error.code = data.code;
    if (res.status === 401 && SESSION_EXPIRED_CODES.includes(data.code) && endpoint !== "/auth/login") {
      error.sessionExpired = true;
      handleSessionExpired();
    }
    throw error;
  }

  return data;
}

// ── Auth ──
export async function login(email, password) {
  return apiFetch("/auth/login", {
    method: "POST",
    body: JSON.stringify({ email, password, role: "admin" }),
  });
}

// ── Admin endpoints ──
export async function getDashboardStats() {
  return apiFetch("/admin/stats");
}

export async function getVendors() {
  return apiFetch("/admin/vendors");
}

export async function approveVendor(vendorId) {
  return apiFetch(`/admin/vendors/${vendorId}/approve`, { method: "PUT" });
}

export async function disapproveVendor(vendorId) {
  return apiFetch(`/admin/vendors/${vendorId}/disapprove`, { method: "PUT" });
}

export async function getOrders() {
  return apiFetch("/admin/orders");
}

export async function getUsers() {
  return apiFetch("/admin/users");
}

/** Issues a temporary password (returned once as data.temporaryPassword). Not allowed for admins. */
export async function resetUserPassword(userId) {
  return apiFetch(`/admin/users/${userId}/reset-password`, { method: "PUT" });
}

// ── Catalog approval (FR06) ──
export async function getProducts(status = "pending") {
  return apiFetch(`/admin/products?status=${encodeURIComponent(status)}`);
}

export async function approveProduct(productId) {
  return apiFetch(`/admin/products/${productId}/approve`, { method: "PUT" });
}

export async function hideProduct(productId) {
  return apiFetch(`/admin/products/${productId}/hide`, { method: "PUT" });
}

// ── Policy engine ──
export async function getPolicies() {
  return apiFetch("/admin/policies");
}

export async function updatePolicies(values) {
  return apiFetch("/admin/policies", {
    method: "PUT",
    body: JSON.stringify({ values }),
  });
}

// ── Disputes (FR08) ──
export async function getDisputes(status) {
  return apiFetch(`/admin/disputes${status ? `?status=${encodeURIComponent(status)}` : ""}`);
}

// Always fetched fresh: evidence URLs are signed links that expire after about an hour
export async function getDispute(disputeId) {
  return apiFetch(`/disputes/${disputeId}`, { cache: "no-store" });
}

export async function resolveDispute(disputeId, resolution, note) {
  return apiFetch(`/admin/disputes/${disputeId}/resolve`, {
    method: "PUT",
    body: JSON.stringify({ resolution, ...(note ? { note } : {}) }),
  });
}

// ── Riders (FR04) & Finance (FR03) ──
export async function getRiders() {
  return apiFetch("/admin/riders");
}

export async function getFinance() {
  return apiFetch("/admin/finance");
}

/**
 * True when the error means the session is missing/invalid or not an admin.
 * Expired/invalid tokens (401 TOKEN_EXPIRED / INVALID_TOKEN) have already been
 * cleared by apiFetch, and the dashboard layout redirects to the login page,
 * which shows SESSION_EXPIRED_MESSAGE.
 */
export function isAuthError(err) {
  return err?.status === 401 || err?.status === 403 || err?.sessionExpired === true;
}
