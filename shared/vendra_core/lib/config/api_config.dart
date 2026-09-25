// ══════════════════════════════════════════════════════════════
// Vendra App - API Configuration
// Centralized API endpoints and base URL management
// ══════════════════════════════════════════════════════════════

class ApiConfig {
  // ──────────────────────────────────────
  // Base URL Configuration
  // ──────────────────────────────────────
  static const String baseUrl = 'http://localhost:3000';

  // ──────────────────────────────────────
  // Auth Endpoints
  // ──────────────────────────────────────
  static const String signup = '/api/auth/signup';
  static const String login = '/api/auth/login';
  static const String me = '/api/auth/me';

  // ──────────────────────────────────────
  // Vendor Product Endpoints
  // ──────────────────────────────────────
  static const String vendorProducts = '/api/vendor/products';
  static String vendorProduct(int id) => '/api/vendor/products/$id';

  // ──────────────────────────────────────
  // Vendor Order Endpoints
  // ──────────────────────────────────────
  static const String vendorOrders = '/api/vendor/orders';
  static String approveOrder(int id) => '/api/vendor/orders/$id/approve';
  static String rejectOrder(int id) => '/api/vendor/orders/$id/reject';
  static String prepareOrder(int id) => '/api/vendor/orders/$id/prepare';
  static String readyForPickupOrder(int id) => '/api/vendor/orders/$id/ready-for-pickup';
  static String deliverOrder(int id) => '/api/vendor/orders/$id/deliver';

  // ──────────────────────────────────────
  // Vendor Location
  // ──────────────────────────────────────
  static const String vendorLocation = '/api/vendor/location';

  // ──────────────────────────────────────
  // Vendor Inventory Ledger
  // ──────────────────────────────────────
  static const String inventoryLedger = '/api/vendor/inventory/ledger';

  // ──────────────────────────────────────
  // Customer Endpoints
  // ──────────────────────────────────────
  static const String products = '/api/products';
  static String vendorDetails(int id) => '/api/vendors/$id';
  static const String checkout = '/api/customer/checkout';
  static const String customerOrders = '/api/customer/orders';
  static String cancelOrder(int id) => '/api/customer/orders/$id/cancel';
  static String customerMarkPickedUp(int id) => '/api/customer/orders/$id/picked-up';
  static String customerConfirmReceived(int id) => '/api/customer/orders/$id/confirm-received';
  static const String walletTopup = '/api/customer/wallet/topup';
}
