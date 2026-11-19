// Task hoarding guard: the rider sees when they must reach the store by
import 'package:flutter_test/flutter_test.dart';
import 'package:vendra_rider/features/rider/models/rider_models.dart';
import 'package:vendra_rider/features/rider/widgets/pickup_deadline_card.dart';

RiderOrder _order(Map<String, dynamic> extra) => RiderOrder.fromJson({'id': 9, 'status': 'ready_for_pickup', 'itemCount': 1, ...extra});

void main() {
  final accepted = DateTime.utc(2026, 11, 18, 9, 0);

  test('the deadline runs from acceptance while heading to the store', () {
    final o = _order({'assignedAt': accepted.toIso8601String()});
    expect(pickupDeadline(o, 20)!.isAtSameMomentAs(accepted.add(const Duration(minutes: 20))), isTrue);
  });

  test('no deadline once at the store, after pickup, or with the policy off', () {
    final arrived = _order({'assignedAt': accepted.toIso8601String(), 'arrivedAt': accepted.add(const Duration(minutes: 5)).toIso8601String()});
    expect(pickupDeadline(arrived, 20), isNull);
    final picked = _order({'status': 'picked', 'assignedAt': accepted.toIso8601String()});
    expect(pickupDeadline(picked, 20), isNull);
    expect(pickupDeadline(_order({'assignedAt': accepted.toIso8601String()}), 0), isNull);
    expect(pickupDeadline(_order({}), 20), isNull);
  });

  test('after checking in, the store wait limit counts down and never goes negative', () {
    final arrived = DateTime(2026, 11, 18, 22, 0);
    expect(storeWaitLeft(arrived, 15, arrived.add(const Duration(minutes: 4))), const Duration(minutes: 11));
    expect(storeWaitLeft(arrived, 15, arrived.add(const Duration(minutes: 20))), Duration.zero);
    expect(storeWaitLeft(arrived, 0, arrived), isNull, reason: 'no limit set');
  });
}
