// ══════════════════════════════════════════════════════════════
// Vendra App - API Configuration
// Centralized API endpoints and base URL management
// ══════════════════════════════════════════════════════════════

class ApiConfig {
  // ──────────────────────────────────────
  // Base URL Configuration
  // ──────────────────────────────────────
  // Set per build: flutter run --dart-define=API_BASE_URL=https://api.example.com
  static const String baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://localhost:3000',
  );

  /// Socket.IO runs on the same host and port as the REST API
  static const String socketUrl = baseUrl;

  /// Absolute URL for a server file path such as `/uploads/abc.jpg`
  static String fileUrl(String path) => path.startsWith('http') ? path : '$baseUrl$path';

  // ──────────────────────────────────────
  // Auth Endpoints
  // ──────────────────────────────────────
  static const String signup = '/api/auth/signup';
  static const String login = '/api/auth/login';
  static const String me = '/api/auth/me';
  static const String changePassword = '/api/auth/change-password';

  // ──────────────────────────────────────
  // Vendor Product Endpoints
  // ──────────────────────────────────────
  static const String vendorProducts = '/api/vendor/products';
  static String vendorProduct(int id) => '/api/vendor/products/$id';
  static String vendorProductImage(int id) => '/api/vendor/products/$id/image';
  static String vendorProductByBarcode(String code) =>
      '/api/vendor/products/barcode/${Uri.encodeComponent(code)}';

  // ──────────────────────────────────────
  // Vendor Walk-in POS
  // ──────────────────────────────────────
  static const String posSales = '/api/vendor/pos/sales';

  // ──────────────────────────────────────
  // Vendor Order Endpoints
  // ──────────────────────────────────────
  static const String vendorOrders = '/api/vendor/orders'; // ?scope=active|history|all&limit=&offset=
  static String vendorOrder(int id) => '/api/vendor/orders/$id';
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
  static const String publicConfig = '/api/public-config';
  static const String categories = '/api/categories';
  static const String products = '/api/products'; // paged: ?limit=&offset=
  static String vendorDetails(int id) => '/api/vendors/$id';
  static const String checkout = '/api/customer/checkout';
  static const String customerOrders = '/api/customer/orders'; // paged
  static String customerOrder(int id) => '/api/customer/orders/$id';
  static String orderTracking(int id) => '/api/customer/orders/$id/tracking';
  static String cancelOrder(int id) => '/api/customer/orders/$id/cancel';
  static String customerMarkPickedUp(int id) => '/api/customer/orders/$id/picked-up';
  static String customerConfirmReceived(int id) => '/api/customer/orders/$id/confirm-received';
  static const String walletTopup = '/api/customer/wallet/topup';

  // ──────────────────────────────────────
  // Rider Endpoints
  // ──────────────────────────────────────
  static const String riderProfile = '/api/rider/profile';
  static const String riderStatus = '/api/rider/status';
  static const String riderLocation = '/api/rider/location';
  static const String riderTasks = '/api/rider/tasks';
  static String acceptTask(int id) => '/api/rider/tasks/$id/accept';
  static const String riderOrders = '/api/rider/orders'; // ?scope=active|history (history paged)
  static String riderArrived(int id) => '/api/rider/orders/$id/arrived';
  static String riderPicked(int id) => '/api/rider/orders/$id/picked';
  static String riderOnTheWay(int id) => '/api/rider/orders/$id/on-the-way';
  static String riderDeliver(int id) => '/api/rider/orders/$id/deliver';
  static const String riderEarnings = '/api/rider/earnings';

  // ──────────────────────────────────────
  // Account Endpoints (every role)
  // ──────────────────────────────────────
  static const String notifications = '/api/notifications';
  static const String notificationsReadAll = '/api/notifications/read-all';
  static String notificationRead(int id) => '/api/notifications/$id/read';
  static const String wallet = '/api/wallet';
  static const String disputes = '/api/disputes';
  static const String myDisputes = '/api/disputes/mine';
  static String dispute(int id) => '/api/disputes/$id';
}
