// VendorOrderLists: a re-read order lands in the right list for its status,
// and history pages don't repeat orders that moved in after page 1.
import 'package:flutter_test/flutter_test.dart';
import 'package:vendra_vendor/features/vendor/models/product_photo.dart';
import 'package:vendra_vendor/features/vendor/models/vendor_order_lists.dart';
import 'package:vendra_vendor/vendra_core.dart';

OrderModel _order(int id, String status, String createdAt) =>
    OrderModel.fromJson({'id': id, 'status': status, 'total_amount': '100.00', 'created_at': createdAt});

void main() {
  test('an active order that is delivered moves to the top of history', () {
    final lists = VendorOrderLists()
      ..active = [_order(3, 'packed', '2026-09-25T12:00:00Z'), _order(2, 'pending', '2026-09-25T11:00:00Z')];
    lists.setHistoryFirstPage([_order(1, 'delivered', '2026-09-24T10:00:00Z')],
        const PageMeta(hasMore: false));

    lists.upsert(_order(3, 'delivered', '2026-09-25T12:00:00Z'));

    expect(lists.active.map((o) => o.id), [2]);
    expect(lists.history.map((o) => o.id), [3, 1]);
  });

  test('a new order is added to active, newest first; updates replace in place', () {
    final lists = VendorOrderLists()..active = [_order(2, 'pending', '2026-09-25T11:00:00Z')];
    lists.upsert(_order(5, 'pending', '2026-09-25T13:00:00Z'));
    lists.upsert(_order(2, 'confirmed', '2026-09-25T11:00:00Z'));

    expect(lists.active.map((o) => o.id), [5, 2]);
    expect(lists.active.last.status, 'confirmed');
  });

  test('a finished order older than every loaded row waits for its page while more exist', () {
    final lists = VendorOrderLists();
    lists.setHistoryFirstPage([_order(9, 'delivered', '2026-09-25T10:00:00Z')],
        const PageMeta(hasMore: true, nextOffset: 1));

    lists.upsert(_order(4, 'cancelled', '2026-09-20T10:00:00Z'));
    expect(lists.history.map((o) => o.id), [9]);

    lists.appendHistoryPage([_order(9, 'delivered', '2026-09-25T10:00:00Z'), _order(4, 'cancelled', '2026-09-20T10:00:00Z')],
        const PageMeta(hasMore: false));
    expect(lists.history.map((o) => o.id), [9, 4]);
    expect(lists.historyHasMore, isFalse);
  });

  test('product photos always get an image content type', () {
    expect(ProductPhoto.mimeFor('shelf.PNG'), 'image/png');
    expect(ProductPhoto.mimeFor('IMG_0001.HEIC'), 'image/heic');
    expect(ProductPhoto.mimeFor('blob', 'image/webp'), 'image/webp');
    expect(ProductPhoto.mimeFor('scan', 'application/octet-stream'), 'image/jpeg');
  });
}
