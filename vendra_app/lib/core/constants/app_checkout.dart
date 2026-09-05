// ══════════════════════════════════════════════════════════════
// Checkout totals — keep in sync with backend STANDARD_DELIVERY_FEE
// ══════════════════════════════════════════════════════════════

class AppCheckout {
  AppCheckout._();

  /// Must match `STANDARD_DELIVERY_FEE` in backend customer.controller.js
  static const double deliveryFee = 150;
}
