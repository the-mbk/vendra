// ══════════════════════════════════════════════════════════════
// Vendra Customer App - Route Configuration
// Named routes for navigation
// ══════════════════════════════════════════════════════════════

class AppRoutes {
  static const String splash = '/';
  static const String login = '/login';
  static const String signup = '/signup';

  static const String customerHome = '/customer/home';
  static const String productDetail = '/customer/product';
  static const String cart = '/customer/cart';
  static const String orderConfirmation = '/customer/order-confirmation';
  static const String customerOrders = '/customer/orders';
  /// Argument: an [OrderModel] or just the order id (e.g. from a notification)
  static const String orderTracking = '/customer/order-tracking';
  static const String storeDetail = '/customer/store';
  static const String wallet = '/customer/wallet';
  static const String myDisputes = '/customer/disputes';
}
