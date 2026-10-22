// Unit tests for manual-location gating: simulation only in development
// (features.manualLocation), every position tagged with its source, and a
// 403 MANUAL_LOCATION_DISABLED putting the app back on GPS.
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vendra_rider/features/rider/services/rider_location_service.dart';
import 'package:vendra_rider/features/rider/services/simulated_drive.dart';
import 'package:vendra_rider/vendra_core.dart';

const _development = AppConfig(mode: 'development', features: AppFeatures(manualLocation: true));
const _production = AppConfig.fallback;

DioException _apiError(int status, String code) {
  final options = RequestOptions(path: ApiConfig.riderLocation);
  return DioException(
    requestOptions: options,
    response: Response<dynamic>(
      requestOptions: options,
      statusCode: status,
      data: {'success': false, 'message': 'Manual locations are turned off.', 'code': code},
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    // A device where the rider had turned simulation on earlier
    SharedPreferences.setMockInitialValues({
      'rider_simulate_location': true,
      'rider_sim_lat': 31.5,
      'rider_sim_lng': 74.3,
    });
  });

  tearDown(() => AppConfig.debugSet(_production));

  test('positions carry their source', () {
    const p = LatLng(31.5, 74.3);
    expect(const LocationFix(p, manual: false).toJson(), {'lat': 31.5, 'lng': 74.3, 'source': 'gps'});
    expect(const LocationFix(p, manual: true).toJson(), {'lat': 31.5, 'lng': 74.3, 'source': 'manual'});
  });

  test('development: a saved simulated point is used and sent as manual', () async {
    AppConfig.debugSet(_development);
    final service = RiderLocationService.isolated();
    await service.init();

    expect(service.manualAllowed, isTrue);
    expect(service.simulate, isTrue);
    final fix = await service.currentFix();
    expect(fix.manual, isTrue);
    expect(fix.toJson(), {'lat': 31.5, 'lng': 74.3, 'source': 'manual'});
  });

  test('production: the saved simulate preference is ignored and cannot be turned on', () async {
    AppConfig.debugSet(_production);
    final service = RiderLocationService.isolated();
    await service.init();

    expect(service.manualAllowed, isFalse);
    expect(service.simulate, isFalse);
    expect(service.position, isNull); // only a GPS fix would count

    await service.setSimulate(true);
    expect(service.simulate, isFalse);

    expect(service.driveBlocker, contains('turned off'));
    expect(
      service.startDrive(target: const LatLng(31.48, 74.33), targetKind: DriveTarget.customer, orderId: 1),
      isFalse,
    );
    expect(service.drive, isNull);
  });

  test('switching the server to production at runtime turns simulation off', () async {
    AppConfig.debugSet(_development);
    final service = RiderLocationService.isolated();
    await service.init();
    expect(service.simulate, isTrue);

    AppConfig.debugSet(_production);
    expect(service.simulate, isFalse);
    expect(service.drive, isNull);
  });

  test('a drive needs simulation and an online rider', () async {
    AppConfig.debugSet(_development);
    final service = RiderLocationService.isolated();
    await service.init();

    // Simulating but offline (not tracking)
    expect(service.driveBlocker, contains('Go online'));
    expect(
      service.startDrive(target: const LatLng(31.48, 74.33), targetKind: DriveTarget.customer, orderId: 1),
      isFalse,
    );

    await service.setSimulate(false);
    expect(service.driveBlocker, contains('Simulate location'));
  });

  test('403 MANUAL_LOCATION_DISABLED switches back to GPS and tells the rider', () async {
    AppConfig.debugSet(_development);
    final service = RiderLocationService.isolated();
    await service.init();
    final notices = <LocationNotice>[];
    final sub = service.notices.listen(notices.add);

    expect(service.handleManualRejected(_apiError(400, 'VALIDATION_ERROR')), isFalse);
    expect(service.simulate, isTrue);

    expect(service.handleManualRejected(_apiError(403, 'MANUAL_LOCATION_DISABLED')), isTrue);
    expect(service.simulate, isFalse);
    expect(service.drive, isNull);

    await Future<void>.delayed(Duration.zero);
    expect(notices.single.text, RiderLocationService.manualDisabledMessage);
    expect(notices.single.isError, isTrue);

    // The GPS choice is saved, so it sticks after a restart
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('rider_simulate_location'), isFalse);
    await sub.cancel();
  });
}
