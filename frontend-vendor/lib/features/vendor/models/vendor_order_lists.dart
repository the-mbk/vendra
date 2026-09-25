// ══════════════════════════════════════════════════════════════
// Vendra Vendor App - The two order lists on the Orders screen
//   active   every in-progress order (?scope=active, not paged)
//   history  delivered / cancelled orders (?scope=history, paged)
// Both are newest first, like the server (created_at DESC, id DESC).
// upsert() puts a re-read order in the right list for its status.
// ══════════════════════════════════════════════════════════════

import 'package:vendra_vendor/vendra_core.dart';

class VendorOrderLists {
  static const finalStatuses = {'delivered', 'cancelled'};

  List<OrderModel> active = const [];
  List<OrderModel> history = const [];

  /// More history pages exist on the server
  bool historyHasMore = false;
  int? historyNextOffset;

  static bool isFinal(OrderModel order) => finalStatuses.contains(order.status);

  void clear() {
    active = const [];
    history = const [];
    historyHasMore = false;
    historyNextOffset = null;
  }

  /// Replaces the history with its first page
  void setHistoryFirstPage(List<OrderModel> orders, PageMeta meta) {
    history = orders;
    historyHasMore = meta.hasMore;
    historyNextOffset = meta.nextOffset;
  }

  /// Appends the next history page. An order that finished after page 1 was
  /// loaded shifts the server's pages by one, so repeats are skipped.
  void appendHistoryPage(List<OrderModel> orders, PageMeta meta) {
    final known = history.map((o) => o.id).toSet();
    history = [...history, ...orders.where((o) => !known.contains(o.id))];
    historyHasMore = meta.hasMore;
    historyNextOffset = meta.nextOffset;
  }

  void remove(int orderId) {
    active = active.where((o) => o.id != orderId).toList();
    history = history.where((o) => o.id != orderId).toList();
  }

  /// Inserts or replaces [order], moving it between active and history by status
  void upsert(OrderModel order) {
    remove(order.id);
    if (isFinal(order)) {
      final list = [...history];
      final index = list.indexWhere((o) => compareNewestFirst(order, o) < 0);
      if (index >= 0) {
        list.insert(index, order);
      } else if (!historyHasMore) {
        list.add(order);
      }
      // else: older than every loaded row — it arrives with a later page
      history = list;
    } else {
      active = [...active, order]..sort(compareNewestFirst);
    }
  }

  static int compareNewestFirst(OrderModel a, OrderModel b) {
    final da = DateTime.tryParse(a.createdAt ?? '');
    final db = DateTime.tryParse(b.createdAt ?? '');
    if (da != null && db != null && da != db) return db.compareTo(da);
    return b.id.compareTo(a.id);
  }
}
