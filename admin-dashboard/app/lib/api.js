// ══════════════════════════════════════════════════════════════
// Vendra Admin Dashboard - API Helper
// Handles all communication with the Express backend
// ══════════════════════════════════════════════════════════════

const API_BASE = process.env.NEXT_PUBLIC_API_URL || "http://localhost:3000/api";

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

  const data = await res.json();

  if (!res.ok) {
    throw new Error(data.message || "API request failed");
  }

  return data;
}

// ── Auth ──
export async function login(email, password) {
  return apiFetch("/auth/login", {
    method: "POST",
    body: JSON.stringify({ email, password }),
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
