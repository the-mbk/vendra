// ══════════════════════════════════════════════════════════════
// Vendra App - Route Configuration
// Named routes for navigation
// ══════════════════════════════════════════════════════════════

class AppRoutes {
  static const String splash = '/';
  static const String login = '/login';
  static const String signup = '/signup';

  // Customer routes
  static const String customerHome = '/customer/home';
  static const String productDetail = '/customer/product';
  static const String cart = '/customer/cart';
  static const String orderConfirmation = '/customer/order-confirmation';
  static const String customerOrders = '/customer/orders';
  static const String orderTracking = '/customer/order-tracking';
  static const String storeDetail = '/customer/store';

  // Vendor routes
  static const String vendorDashboard = '/vendor/dashboard';
  static const String vendorPendingApproval = '/vendor/pending-approval';
  static const String addProduct = '/vendor/add-product';
  static const String editProduct = '/vendor/edit-product';
  static const String vendorOrders = '/vendor/orders';
  static const String stockLedger = '/vendor/ledger';

  // Placeholder routes
  static const String riderPlaceholder = '/rider';
  static const String adminPlaceholder = '/admin';
  static const String underDevelopment = '/under-development';
}
