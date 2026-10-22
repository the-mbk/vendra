// ══════════════════════════════════════════════════════════════
// Vendra Rider App - Location Service (PR03 / FR04 / SSR02)
// While the rider is online it sends POST /api/rider/location every
// 10 s. The position comes from the device GPS (geolocator) or — only
// when the server runs in development (`features.manualLocation`) — from
// "Simulate location": a point the rider taps on a map, optionally moved
// to the store / customer by a simulated drive. Every position is sent
// with its `source` (gps | manual); a server that refuses manual
// positions (403 MANUAL_LOCATION_DISABLED) puts the app back on GPS.
// ══════════════════════════════════════════════════════════════

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vendra_rider/vendra_core.dart';

import 'simulated_drive.dart';

/// Thrown when no position can be obtained; [message] is shown to the rider.
class LocationUnavailable implements Exception {
  final String message;
  const LocationUnavailable(this.message);
  @override
  String toString() => message;
}

/// A position plus where it came from: the device GPS, or set by hand /
/// a simulated drive ([manual]).
class LocationFix {
  final LatLng point;
  final bool manual;
  const LocationFix(this.point, {required this.manual});

  /// `source` field for /api/rider/location, /status and /deliver
  String get source => manual ? 'manual' : 'gps';

  Map<String, dynamic> toJson() => {'lat': point.latitude, 'lng': point.longitude, 'source': source};
}

/// One-off message for the rider (shown as a snackbar by the app shell)
class LocationNotice {
  final String text;
  final bool isError;
  const LocationNotice(this.text, {this.isError = false});
}

class RiderLocationService extends ChangeNotifier {
  static final RiderLocationService _instance = RiderLocationService._internal();
  factory RiderLocationService() => _instance;
  RiderLocationService._internal() {
    AppConfig.notifier.addListener(_onConfigChanged);
  }

  /// A separate instance for unit tests (the app always uses the singleton)
  @visibleForTesting
  factory RiderLocationService.isolated() => RiderLocationService._internal();

  static const Duration sendInterval = Duration(seconds: 10);
  static const LatLng defaultPoint = LatLng(31.5204, 74.3587); // Lahore

  static const String manualDisabledMessage = 'Manual location is turned off on this server; using GPS';

  static const _kSimulate = 'rider_simulate_location';
  static const _kSimLat = 'rider_sim_lat';
  static const _kSimLng = 'rider_sim_lng';

  final ApiService _api = ApiService();
  final StreamController<LocationNotice> _notices = StreamController<LocationNotice>.broadcast();

  bool _loaded = false;

  /// The rider's saved choice; only honoured while the server allows manual locations
  bool _simulate = false;

  /// [simulate] as last applied (to react when the config flips it)
  bool _wasSimulating = false;
  LatLng? _simulatedPoint;
  LatLng? _gpsPoint;
  DateTime? _gpsAt;
  LatLng? _serverPoint;

  bool _tracking = false;
  bool _sending = false;
  Timer? _timer;
  StreamSubscription<Position>? _gpsSub;
  String? _error;
  DateTime? _lastSentAt;
  SimulatedDrive? _drive;

  /// Manual positions are a development-only feature of the server
  bool get manualAllowed => AppConfig.current.features.manualLocation;

  /// Simulation in effect: the rider turned it on AND the server allows it.
  /// In production this is always false, whatever was saved on the device.
  bool get simulate => _simulate && manualAllowed;
  LatLng? get simulatedPoint => _simulatedPoint;
  LatLng? get gpsPoint => _gpsPoint;

  /// Best current position: the simulated point in simulation mode, else the latest GPS fix
  LatLng? get position => simulate ? _simulatedPoint : _gpsPoint;
  bool get isTracking => _tracking;
  String? get error => _error;
  DateTime? get lastSentAt => _lastSentAt;

  /// The simulated drive in progress, if any
  SimulatedDrive? get drive => _drive;

  /// Messages for the rider (manual location refused, drive arrived…)
  Stream<LocationNotice> get notices => _notices.stream;

  /// Whether [error] is the server refusing a manual position
  static bool isManualRejected(Object error) => ApiService.getErrorCode(error) == 'MANUAL_LOCATION_DISABLED';

  /// Appended to GPS problems — only offered where simulation exists
  String get _simulateHint => manualAllowed ? ' Or turn on "Simulate location" in Location settings.' : '';

  /// Loads the saved simulation settings (once).
  Future<void> init() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      _simulate = prefs.getBool(_kSimulate) ?? false;
      final lat = prefs.getDouble(_kSimLat);
      final lng = prefs.getDouble(_kSimLng);
      if (lat != null && lng != null) _simulatedPoint = LatLng(lat, lng);
    } catch (e) {
      debugPrint('Location prefs load failed: $e');
    }
    _wasSimulating = simulate;
    notifyListeners();
  }

  /// Last location the server knows (from /api/rider/profile) — used as the
  /// starting point when simulation is first switched on.
  void rememberServerPosition(double? lat, double? lng) {
    if (lat != null && lng != null) _serverPoint = LatLng(lat, lng);
  }

  /// Turns simulation on/off. Turning it on is ignored when the server
  /// doesn't allow manual locations.
  Future<void> setSimulate(bool on) async {
    await init();
    if (on && !manualAllowed) return;
    _simulate = on;
    _error = null;
    if (on) {
      _simulatedPoint ??= _gpsPoint ?? _serverPoint ?? defaultPoint;
    } else {
      _drive = null;
    }
    _wasSimulating = simulate;
    await _save();
    notifyListeners();
    if (_tracking) unawaited(_beginTracking());
  }

  /// The rider placed themselves on the map (stops any simulated drive).
  Future<void> setSimulatedPoint(LatLng point) async {
    _drive = null;
    _simulatedPoint = point;
    await _save();
    notifyListeners();
    if (_tracking && simulate) unawaited(sendNow());
  }

  /// Current position for a one-off action (going online, confirming delivery),
  /// with its source. Set [fresh] to force a new GPS reading instead of the cached fix.
  Future<LocationFix> currentFix({bool fresh = false}) async {
    await init();
    if (simulate) {
      return LocationFix(_simulatedPoint ??= _serverPoint ?? defaultPoint, manual: true);
    }
    final cached = _gpsPoint;
    if (!fresh &&
        cached != null &&
        _gpsAt != null &&
        DateTime.now().difference(_gpsAt!) < const Duration(seconds: 15)) {
      return LocationFix(cached, manual: false);
    }
    await _ensurePermission();
    try {
      final p = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 20),
        ),
      );
      _setGps(p);
      return LocationFix(_gpsPoint!, manual: false);
    } on TimeoutException {
      throw LocationUnavailable('Could not get a GPS fix. Move outdoors and try again.$_simulateHint');
    } on LocationServiceDisabledException {
      throw LocationUnavailable('Location services are turned off. Turn on GPS.$_simulateHint');
    } catch (e) {
      throw LocationUnavailable('Location error: $e.$_simulateHint');
    }
  }

  /// Starts sending the position every 10 s (call when the rider goes online).
  void start() {
    if (_tracking) return;
    _tracking = true;
    _restartTimer();
    notifyListeners();
    unawaited(_beginTracking());
  }

  /// GPS stream first (it may prompt for permission), then an immediate send —
  /// sequential because geolocator rejects overlapping permission requests.
  Future<void> _beginTracking() async {
    if (simulate) {
      await _stopGps();
    } else {
      await _startGps();
    }
    await sendNow();
  }

  /// Stops tracking (offline / logout). Ends any simulated drive.
  void stop() {
    _tracking = false;
    _drive = null;
    _timer?.cancel();
    _timer = null;
    unawaited(_stopGps());
    notifyListeners();
  }

  /// Sends one location update right away.
  Future<void> sendNow() async {
    if (_sending) return;
    _sending = true;
    try {
      final fix = await currentFix();
      await _api.post(ApiConfig.riderLocation, data: fix.toJson());
      _lastSentAt = DateTime.now();
      _error = null;
    } on LocationUnavailable catch (e) {
      _error = e.message;
    } catch (e) {
      if (!handleManualRejected(e)) _error = 'Could not send location: ${ApiService.getErrorMessage(e)}';
    } finally {
      _sending = false;
      notifyListeners();
    }
  }

  /// Call with the error of any request that carried a position. Returns true
  /// when the server refused a manual position (403 MANUAL_LOCATION_DISABLED):
  /// simulation is switched off, GPS takes over and the rider is told.
  bool handleManualRejected(Object error) {
    if (!isManualRejected(error)) return false;
    _simulate = false;
    _wasSimulating = false;
    _drive = null;
    _error = null;
    unawaited(_save());
    _notices.add(const LocationNotice(manualDisabledMessage, isError: true));
    notifyListeners();
    if (_tracking) unawaited(_beginTracking());
    // Our copy of the config is stale — re-read it so the simulate options disappear
    unawaited(AppConfig.refresh());
    return true;
  }

  // ── Simulated drive (development only) ─────────────────────

  /// Why a drive can't start right now, or null if it can
  String? get driveBlocker {
    if (!manualAllowed) return 'Manual location is turned off on this server.';
    if (!simulate) return 'Turn on "Simulate location" to simulate the drive.';
    if (!_tracking) return 'Go online first — the drive is recorded through your location updates.';
    return null;
  }

  /// Drives the simulated point in a straight line to [target], one step per
  /// location update (every 10 s). Returns false if it couldn't start.
  bool startDrive({
    required LatLng target,
    required DriveTarget targetKind,
    required int orderId,
    bool fast = false,
  }) {
    if (driveBlocker != null) return false;
    final from = _simulatedPoint ??= _serverPoint ?? defaultPoint;
    final drive = SimulatedDrive(
      start: from,
      target: target,
      targetKind: targetKind,
      orderId: orderId,
      tick: sendInterval,
      fast: fast,
    );
    if (drive.arrived) return false;
    _drive = drive;
    // Steps line up with the pings: the first one a full interval from now
    _restartTimer();
    notifyListeners();
    unawaited(sendNow()); // record the starting point
    return true;
  }

  void setDriveFast(bool fast) {
    final d = _drive;
    if (d == null || d.fast == fast) return;
    d.fast = fast;
    notifyListeners();
  }

  void stopDrive() {
    if (_drive == null) return;
    _drive = null;
    notifyListeners();
  }

  void _restartTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(sendInterval, (_) => _onTick());
  }

  void _onTick() {
    _advanceDrive();
    unawaited(sendNow());
  }

  /// Moves one step along the drive (just before the ping that reports it)
  void _advanceDrive() {
    final d = _drive;
    if (d == null) return;
    if (!simulate || !_tracking) {
      _drive = null;
      notifyListeners();
      return;
    }
    _simulatedPoint = d.step();
    unawaited(_save());
    if (d.arrived) {
      _drive = null;
      _notices.add(LocationNotice(d.targetKind == DriveTarget.store
          ? 'Simulated drive arrived at the store'
          : 'Simulated drive arrived at the customer — you can confirm delivery'));
    }
    notifyListeners();
  }

  /// The server config changed (loaded late, refreshed, or switched mode)
  void _onConfigChanged() {
    final sim = simulate;
    if (sim == _wasSimulating) return;
    _wasSimulating = sim;
    if (!sim) _drive = null;
    _error = null;
    notifyListeners();
    if (_tracking) unawaited(_beginTracking());
  }

  /// Opens the OS app settings (for a permanently denied permission).
  Future<void> openSettings() async {
    try {
      await Geolocator.openAppSettings();
    } catch (_) {}
  }

  /// Re-checks permission / GPS after the rider fixed it.
  Future<void> retryGps() async {
    _error = null;
    notifyListeners();
    if (_tracking && !simulate) {
      await _stopGps();
      await _startGps();
      await sendNow();
    } else {
      try {
        await currentFix(fresh: true);
      } on LocationUnavailable catch (e) {
        _error = e.message;
      }
      notifyListeners();
    }
  }

  // ── internals ──────────────────────────────────────────────

  Future<void> _ensurePermission() async {
    bool enabled;
    try {
      enabled = await Geolocator.isLocationServiceEnabled();
    } catch (_) {
      enabled = true; // some platforms can't report it; let the request decide
    }
    if (!enabled) {
      throw LocationUnavailable('Location services are turned off. Turn on GPS.$_simulateHint');
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied) {
      throw const LocationUnavailable(
          'Location permission denied. Vendra needs your location to find nearby deliveries and verify drop-offs.');
    }
    if (permission == LocationPermission.deniedForever) {
      throw LocationUnavailable('Location permission is blocked. Enable it in the app settings.$_simulateHint');
    }
  }

  Future<void> _startGps() async {
    if (_gpsSub != null || simulate) return;
    try {
      await _ensurePermission();
    } on LocationUnavailable catch (e) {
      _error = e.message;
      notifyListeners();
      return;
    }
    if (simulate || !_tracking || _gpsSub != null) return;
    _gpsSub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, distanceFilter: 5),
    ).listen(
      (p) {
        _setGps(p);
        notifyListeners();
      },
      onError: (Object e) {
        _error = e is LocationServiceDisabledException
            ? 'Location services are turned off. Turn on GPS.$_simulateHint'
            : 'GPS error: $e';
        notifyListeners();
      },
    );
  }

  Future<void> _stopGps() async {
    final sub = _gpsSub;
    _gpsSub = null;
    await sub?.cancel();
  }

  void _setGps(Position p) {
    _gpsPoint = LatLng(p.latitude, p.longitude);
    _gpsAt = DateTime.now();
  }

  Future<void> _save() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_kSimulate, _simulate);
      final p = _simulatedPoint;
      if (p != null) {
        await prefs.setDouble(_kSimLat, p.latitude);
        await prefs.setDouble(_kSimLng, p.longitude);
      }
    } catch (e) {
      debugPrint('Location prefs save failed: $e');
    }
  }
}
