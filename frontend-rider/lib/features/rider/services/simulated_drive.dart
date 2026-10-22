// ══════════════════════════════════════════════════════════════
// Vendra Rider App - Simulated drive (development only)
// Moves the simulated position along a straight line to a target (the
// store before pickup, the customer pin after) one step per location
// ping, so the backend records a real trip distance for the payout.
// Pure maths — RiderLocationService owns the timer and the sending.
// ══════════════════════════════════════════════════════════════

import 'dart:math' as math;

import 'package:latlong2/latlong.dart';

/// Where a simulated drive is heading
enum DriveTarget { store, customer }

class SimulatedDrive {
  /// Normal demo speed (city traffic)
  static const double normalKmh = 40;

  /// Fast-forward multiplier for demos
  static const int fastMultiplier = 5;

  static const Distance _distance = Distance();

  final LatLng start;
  final LatLng target;
  final DriveTarget targetKind;
  final int orderId;

  /// Real time between two steps (the location send interval)
  final Duration tick;

  /// Straight-line length of the whole drive
  final double totalMeters;

  /// Fast-forward (×[fastMultiplier]); can be switched mid-drive
  bool fast;
  double _travelledMeters = 0;

  SimulatedDrive({
    required this.start,
    required this.target,
    required this.targetKind,
    required this.orderId,
    required this.tick,
    this.fast = false,
  }) : totalMeters = _distance.as(LengthUnit.Meter, start, target);

  /// Simulated speed: 40 km/h, or 200 km/h on fast-forward
  double get speedKmh => normalKmh * (fast ? fastMultiplier : 1);

  /// Distance covered by one step (one ping)
  double get stepMeters => speedKmh * 1000 / 3600 * tick.inMilliseconds / 1000;

  double get travelledMeters => _travelledMeters;
  double get remainingMeters => math.max(0, totalMeters - _travelledMeters);
  bool get arrived => remainingMeters <= 0;

  /// 0…1
  double get progress => totalMeters <= 0 ? 1 : (_travelledMeters / totalMeters).clamp(0.0, 1.0);

  /// Current point on the line (exactly [target] once arrived)
  LatLng get position => arrived ? target : interpolate(start, target, progress);

  /// Steps (pings) still to go
  int get stepsLeft => arrived ? 0 : (remainingMeters / stepMeters).ceil();

  /// Real time until arrival at the current speed
  Duration get eta => tick * stepsLeft;

  /// Advances one step and returns the new position. The last step lands
  /// exactly on [target] (so the delivery geofence passes).
  LatLng step() {
    _travelledMeters = math.min(totalMeters, _travelledMeters + stepMeters);
    return position;
  }

  /// Point at fraction [t] (0…1) of the straight line [a]→[b]. Linear in
  /// lat/lng — accurate enough over city distances.
  static LatLng interpolate(LatLng a, LatLng b, double t) => LatLng(
        a.latitude + (b.latitude - a.latitude) * t,
        a.longitude + (b.longitude - a.longitude) * t,
      );

  /// "1.24 km" / "350 m"
  static String formatDistance(double meters) =>
      meters >= 1000 ? '${(meters / 1000).toStringAsFixed(2)} km' : '${meters.round()} m';

  /// "~3 min" / "~40 s"
  static String formatEta(Duration d) =>
      d.inSeconds >= 60 ? '~${(d.inSeconds / 60).ceil()} min' : '~${d.inSeconds} s';
}
