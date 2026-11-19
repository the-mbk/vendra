// The store's view of the rider: coming, waiting at the counter, or past the store wait limit
import 'package:flutter_test/flutter_test.dart';
import 'package:vendra_vendor/features/vendor/widgets/rider_at_store_card.dart';
import 'package:vendra_vendor/vendra_core.dart';

OrderModel _order({DateTime? arrived}) => OrderModel.fromJson({
      'id': 12,
      'status': 'ready_for_pickup',
      'delivery_type': 'delivery',
      'total_amount': 1000,
      'rider_user_id': 7,
      'rider_name': 'Bilal H.',
      if (arrived != null) 'rider_arrived_at': arrived.toIso8601String(),
      'items': const [],
    });

void main() {
  final now = DateTime(2026, 11, 18, 22, 30);

  test('reads the check-in time the server sends', () {
    final o = _order(arrived: now);
    expect(o.riderArrivedAt, isNotNull);
    expect(o.rider?.name, 'Bilal H.');
  });

  test('coming → waiting → over the limit', () {
    expect(riderAtStoreState(_order(), 15, now), RiderAtStore.onTheWay);
    expect(riderAtStoreState(_order(arrived: now.subtract(const Duration(minutes: 4))), 15, now), RiderAtStore.waiting);
    expect(riderAtStoreState(_order(arrived: now.subtract(const Duration(minutes: 16))), 15, now), RiderAtStore.overLimit);
    expect(riderAtStoreState(_order(arrived: now.subtract(const Duration(hours: 2))), 0, now), RiderAtStore.waiting,
        reason: 'no limit configured');
  });
}
