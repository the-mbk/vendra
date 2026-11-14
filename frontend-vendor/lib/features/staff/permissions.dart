// ══════════════════════════════════════════════════════════════
// Vendra Vendor App - Shop staff permissions (SRDS §1.3)
// GET /api/auth/me tells the app what this session may do. The store
// owner (no staff) may do everything; a PIN-signed-in staff member only
// what their role allows:
//   cashier            POS + product list (read-only)
//   packer             orders: accept / pack / ready / hand over
//   inventory_manager  products, stock, photos, ledger + view orders
// The server enforces the same rules (403 STAFF_FORBIDDEN); the app only
// hides what a role can't use.
// ══════════════════════════════════════════════════════════════

import 'package:vendra_vendor/vendra_core.dart';

/// Permission names sent by the server in `permissions`
class Perm {
  static const productsView = 'products.view';
  static const productsManage = 'products.manage';
  static const pos = 'pos';
  static const ordersView = 'orders.view';
  static const ordersFulfil = 'orders.fulfil';
  static const ledger = 'ledger';
  /// Staff, store location, receipt settings, wallet / withdrawals, disputes
  static const owner = 'owner';
}

/// The dashboard's bottom-navigation tabs
enum VendorTab { home, pos, orders, ledger, profile }

/// Tabs this session may open, in display order (always at least Home + Profile)
List<VendorTab> visibleTabs(UserModel user) => [
      VendorTab.home,
      if (user.can(Perm.pos)) VendorTab.pos,
      if (user.can(Perm.ordersView)) VendorTab.orders,
      if (user.can(Perm.ledger)) VendorTab.ledger,
      VendorTab.profile,
    ];

/// "Ali Raza · Cashier", or "Usman Ali · Owner" for the store owner
String signedInLabel(UserModel user) {
  final staff = user.staff;
  if (staff == null) return '${user.fullName} · Owner';
  return '${staff.fullName} · ${staff.roleLabel}';
}
