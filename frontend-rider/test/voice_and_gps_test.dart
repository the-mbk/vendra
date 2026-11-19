// Voice cues say the one line that fits where the delivery stands;
// location updates every 10 s on a delivery (PR 03), every 30 s when idle.
import 'package:flutter_test/flutter_test.dart';
import 'package:vendra_rider/features/rider/models/rider_models.dart';
import 'package:vendra_rider/features/rider/services/rider_location_service.dart';
import 'package:vendra_rider/features/rider/services/voice_cues.dart';

RiderOrder _order(Map<String, dynamic> extra) => RiderOrder.fromJson({
      'id': 7,
      'status': 'ready_for_pickup',
      'itemCount': 1,
      'storeName': 'Karachi Electronics Hub',
      'otpRequired': true,
      ...extra,
    });

void main() {
  test('heading to the store: where to go, then "arrived" inside the geofence', () {
    final o = _order({});
    expect(voiceCueFor(o, metersToStore: 900, geofenceMeters: 200)!.text, 'New delivery. Head to Karachi Electronics Hub.');
    final at = voiceCueFor(o, metersToStore: 150, geofenceMeters: 200)!;
    expect(at.key, 'store-7');
    expect(at.text, contains('arrived at Karachi Electronics Hub'));
  });

  test('after pickup: head to the customer, then ask for the code at the door', () {
    final o = _order({'status': 'on_the_way'});
    expect(voiceCueFor(o, metersToCustomer: 2000, geofenceMeters: 200)!.key, 'picked-7');
    expect(voiceCueFor(o, metersToCustomer: 80, geofenceMeters: 200)!.text, contains('four digit code'));
  });

  test('done and cancelled deliveries', () {
    expect(voiceCueFor(_order({'status': 'delivered'}), geofenceMeters: 200)!.key, 'done-7');
    expect(voiceCueFor(_order({'status': 'cancelled'}), geofenceMeters: 200), isNull);
  });

  test('location rhythm: 10 s on a delivery or a drive, 30 s idle', () {
    expect(RiderLocationService.intervalFor(onDelivery: true, driving: false), const Duration(seconds: 10));
    expect(RiderLocationService.intervalFor(onDelivery: false, driving: true), const Duration(seconds: 10));
    expect(RiderLocationService.intervalFor(onDelivery: false, driving: false), const Duration(seconds: 30));
  });
}
