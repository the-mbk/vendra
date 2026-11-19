// Rider note chips and the "At your door" step on the tracking timeline
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:vendra_customer/features/customer/screens/order_tracking_screen.dart';
import 'package:vendra_customer/features/customer/widgets/rider_note_field.dart';
import 'package:vendra_customer/vendra_core.dart';

OrderModel _order(String status) => OrderModel.fromJson({
      'id': 3,
      'status': status,
      'deliveryType': 'delivery',
      'customerLat': 24.8138,
      'customerLng': 67.0300,
      'totalAmount': 1000,
      'items': const [],
    });

void main() {
  test('note chips add a sentence once and respect the length limit', () {
    expect(addRiderNote('', 'Leave it at the door'), 'Leave it at the door');
    expect(addRiderNote('Gate code 402', 'Leave it at the door'), 'Gate code 402. Leave it at the door');
    expect(addRiderNote('Leave it at the door', 'leave it at the door'), 'Leave it at the door');
    final long = 'x' * 195;
    expect(addRiderNote(long, 'Hand it to the guard'), long, reason: 'would exceed $riderNoteMaxLength');
  });

  test('the rider is "at your door" only on the way and inside the geofence', () {
    const pin = LatLng(24.8138, 67.0300);
    const near = LatLng(24.8145, 67.0300); // ~80 m
    const far = LatLng(24.8250, 67.0300); // ~1.2 km
    expect(riderAtDoor(_order('on_the_way'), near, 200), isTrue);
    expect(riderAtDoor(_order('on_the_way'), far, 200), isFalse);
    expect(riderAtDoor(_order('picked'), pin, 200), isFalse);
    expect(riderAtDoor(_order('on_the_way'), null, 200), isFalse);
  });
}
