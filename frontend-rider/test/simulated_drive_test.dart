// Unit tests for the development-only simulated drive: straight-line
// interpolation, one step per 10 s ping, arrival exactly on the target,
// and a recorded path as long as the straight line.
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:vendra_rider/features/rider/services/simulated_drive.dart';

void main() {
  const distance = Distance();
  const store = LatLng(31.5204, 74.3587); // Lahore
  const customer = LatLng(31.4834, 74.3290); // ~5 km south-west
  const tick = Duration(seconds: 10);

  SimulatedDrive drive({bool fast = false, LatLng from = store, LatLng to = customer}) => SimulatedDrive(
        start: from,
        target: to,
        targetKind: DriveTarget.customer,
        orderId: 1,
        tick: tick,
        fast: fast,
      );

  /// Runs the drive to the end; returns every pinged point, starting point included
  List<LatLng> runToEnd(SimulatedDrive d) {
    final points = [d.position];
    var guard = 0;
    while (!d.arrived) {
      points.add(d.step());
      if (++guard > 10000) fail('drive never arrived');
    }
    return points;
  }

  double pathMeters(List<LatLng> pts) {
    var total = 0.0;
    for (var i = 1; i < pts.length; i++) {
      total += distance.as(LengthUnit.Meter, pts[i - 1], pts[i]);
    }
    return total;
  }

  test('interpolates along the straight line', () {
    final mid = SimulatedDrive.interpolate(store, customer, 0.5);
    expect(mid.latitude, closeTo((store.latitude + customer.latitude) / 2, 1e-9));
    expect(mid.longitude, closeTo((store.longitude + customer.longitude) / 2, 1e-9));
    expect(SimulatedDrive.interpolate(store, customer, 0), store);
    expect(SimulatedDrive.interpolate(store, customer, 1), customer);
  });

  test('normal speed moves ~111 m per 10 s ping (40 km/h)', () {
    final d = drive();
    expect(d.speedKmh, 40);
    expect(d.stepMeters, closeTo(111.11, 0.01));

    final before = d.position;
    final after = d.step();
    expect(distance.as(LengthUnit.Meter, before, after), closeTo(d.stepMeters, 1.5));
    expect(d.travelledMeters, closeTo(d.stepMeters, 1e-6));
    expect(d.progress, greaterThan(0));
    expect(d.arrived, isFalse);
  });

  test('arrives exactly on the target after ceil(total / step) pings', () {
    final d = drive();
    final expectedSteps = (d.totalMeters / d.stepMeters).ceil();
    expect(d.stepsLeft, expectedSteps);
    expect(d.eta, tick * expectedSteps);

    final points = runToEnd(d);
    expect(points.length - 1, expectedSteps);
    expect(points.last, customer); // inside any geofence around the customer pin
    expect(d.position, customer);
    expect(d.remainingMeters, 0);
    expect(d.progress, 1);
    expect(d.stepsLeft, 0);
    expect(d.eta, Duration.zero);

    // Extra steps after arrival stay on the target
    expect(d.step(), customer);
  });

  test('the pinged path is as long as the straight line', () {
    final straight = distance.as(LengthUnit.Meter, store, customer);
    expect(straight, inInclusiveRange(4000, 6000));

    final points = runToEnd(drive());
    final recorded = pathMeters(points);
    expect(recorded, closeTo(straight, straight * 0.005)); // within 0.5 %
  });

  test('fast-forward covers 5x the distance per ping and still ends on the target', () {
    final normal = drive();
    final fast = drive(fast: true);
    expect(fast.speedKmh, 200);
    expect(fast.stepMeters, closeTo(normal.stepMeters * 5, 1e-9));
    expect(fast.stepsLeft, (fast.totalMeters / fast.stepMeters).ceil());

    final points = runToEnd(fast);
    expect(points.last, customer);
    expect(pathMeters(points), closeTo(fast.totalMeters, fast.totalMeters * 0.005));
    expect(points.length - 1, lessThan(runToEnd(normal).length ~/ 4));
  });

  test('speed can change mid-drive', () {
    final d = drive();
    d.step();
    final afterOne = d.travelledMeters;
    d.fast = true;
    d.step();
    expect(d.travelledMeters - afterOne, closeTo(d.stepMeters, 1e-9));
    expect(d.stepMeters, closeTo(555.56, 0.01));
  });

  test('a drive to where you already are has nothing to do', () {
    final d = drive(to: store);
    expect(d.totalMeters, 0);
    expect(d.arrived, isTrue);
    expect(d.progress, 1);
    expect(d.position, store);
  });

  test('formats distance and ETA for the progress line', () {
    expect(SimulatedDrive.formatDistance(350.4), '350 m');
    expect(SimulatedDrive.formatDistance(1240), '1.24 km');
    expect(SimulatedDrive.formatEta(const Duration(seconds: 40)), '~40 s');
    expect(SimulatedDrive.formatEta(const Duration(seconds: 130)), '~3 min');
  });
}
