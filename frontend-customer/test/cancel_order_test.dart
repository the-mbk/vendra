// Cancelling: free while pending, a policy fee once the store accepted, not after packing
import 'package:flutter_test/flutter_test.dart';
import 'package:vendra_customer/features/customer/widgets/cancel_order.dart';
import 'package:vendra_customer/vendra_core.dart';

OrderModel _order(String status) => OrderModel.fromJson({
      'id': 12,
      'status': status,
      'subtotal': 4998,
      'deliveryFee': 150,
      'totalAmount': 5148,
      'items': const [],
    });

void main() {
  test('a pending order cancels free with everything refunded', () {
    final q = cancelQuote(_order('pending'), 10)!;
    expect(q.storeFee, 0);
    expect(q.refund, 5148);
  });

  test('an accepted order costs the policy share of the items only', () {
    final q = cancelQuote(_order('confirmed'), 10)!;
    expect(q.storeFee, 499.8);
    expect(q.refund, closeTo(4648.2, 0.001));
  });

  test('packed and later orders cannot be cancelled', () {
    for (final s in ['packed', 'ready_for_pickup', 'picked', 'on_the_way', 'delivered', 'cancelled']) {
      expect(cancelQuote(_order(s), 10), isNull, reason: s);
    }
  });
}
