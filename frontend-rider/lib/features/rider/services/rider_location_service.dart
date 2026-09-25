// ══════════════════════════════════════════════════════════════
// Vendra Rider App - Location Service (PR03 / FR04 / SSR02)
// While the rider is online it sends POST /api/rider/location every
// 10 s. The position comes from the device GPS (geolocator) or, in
// "Simulate location" mode, from a point the rider taps on a map —
// GPS can't be tested indoors or on web/desktop.
// ══════════════════════════════════════════════════════════════

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vendra_rider/vendra_core.dart';

/// Thrown when no position can be obtained; [message] is shown to the rider.
class LocationUnavailable implements Exception {
  final String message;
  const LocationUnavailable(this.message);
  @override
  String toString() => message;
}

class RiderLocationService extends ChangeNotifier {
  static final RiderLocationService _instance = RiderLocationService._internal();
  factory RiderLocationService() => _instance;
  RiderLocationService._internal();

  static const Duration sendInterval = Duration(seconds: 10);
  static const LatLng defaultPoint = LatLng(31.5204, 74.3587); // Lahore

  static const _kSimulate = 'rider_simulate_location';
  static const _kSimLat = 'rider_sim_lat';
  static const _kSimLng = 'rider_sim_lng';

  final ApiService _api = ApiService();

  bool _loaded = false;
  bool _simulate = false;
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

  bool get simulate => _simulate;
  LatLng? get simulatedPoint => _simulatedPoint;
  LatLng? get gpsPoint => _gpsPoint;

  /// Best current position: the simulated point in simulation mode, else the latest GPS fix
  LatLng? get position => _simulate ? _simulatedPoint : _gpsPoint;
  bool get isTracking => _tracking;
  String? get error => _error;
  DateTime? get lastSentAt => _lastSentAt;

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
    notifyListeners();
  }

  /// Last location the server knows (from /api/rider/profile) — used as the
  /// starting point when simulation is first switched on.
  void rememberServerPosition(double? lat, double? lng) {
    if (lat != null && lng != null) _serverPoint = LatLng(lat, lng);
  }

  Future<void> setSimulate(bool on) async {
    await init();
    _simulate = on;
    _error = null;
    if (on) {
      _simulatedPoint ??= _gpsPoint ?? _serverPoint ?? defaultPoint;
      await _stopGps();
    }
    await _save();
    notifyListeners();
    if (_tracking) unawaited(_beginTracking());
  }

  Future<void> setSimulatedPoint(LatLng point) async {
    _simulatedPoint = point;
    await _save();
    notifyListeners();
    if (_tracking && _simulate) unawaited(sendNow());
  }

  /// Current position for a one-off action (going online, confirming delivery).
  /// Set [fresh] to force a new GPS reading instead of the cached fix.
  Future<LatLng> currentPosition({bool fresh = false}) async {
    await init();
    if (_simulate) {
      return _simulatedPoint ??= _serverPoint ?? defaultPoint;
    }
    final cached = _gpsPoint;
    if (!fresh &&
        cached != null &&
        _gpsAt != null &&
        DateTime.now().difference(_gpsAt!) < const Duration(seconds: 15)) {
      return cached;
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
      return _gpsPoint!;
    } on TimeoutException {
      throw const LocationUnavailable(
          'Could not get a GPS fix. Move outdoors, or turn on "Simulate location" in Location settings.');
    } on LocationServiceDisabledException {
      throw const LocationUnavailable('Location services are turned off. Turn on GPS, or use "Simulate location".');
    } catch (e) {
      throw LocationUnavailable('Location error: $e. You can use "Simulate location" instead.');
    }
  }

  /// Starts sending the position every 10 s (call when the rider goes online).
  void start() {
    if (_tracking) return;
    _tracking = true;
    _timer?.cancel();
    _timer = Timer.periodic(sendInterval, (_) => sendNow());
    notifyListeners();
    unawaited(_beginTracking());
  }

  /// GPS stream first (it may prompt for permission), then an immediate send —
  /// sequential because geolocator rejects overlapping permission requests.
  Future<void> _beginTracking() async {
    if (!_simulate) await _startGps();
    await sendNow();
  }

  /// Stops tracking (offline / logout).
  void stop() {
    _tracking = false;
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
      final p = await currentPosition();
      await _api.post(ApiConfig.riderLocation, data: {'lat': p.latitude, 'lng': p.longitude});
      _lastSentAt = DateTime.now();
      _error = null;
    } on LocationUnavailable catch (e) {
      _error = e.message;
    } catch (e) {
      _error = 'Could not send location: ${ApiService.getErrorMessage(e)}';
    } finally {
      _sending = false;
      notifyListeners();
    }
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
    if (_tracking && !_simulate) {
      await _stopGps();
      await _startGps();
      await sendNow();
    } else {
      try {
        await currentPosition(fresh: true);
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
      throw const LocationUnavailable('Location services are turned off. Turn on GPS, or use "Simulate location".');
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
      throw const LocationUnavailable(
          'Location permission is blocked. Enable it in the app settings, or use "Simulate location".');
    }
  }

  Future<void> _startGps() async {
    if (_gpsSub != null || _simulate) return;
    try {
      await _ensurePermission();
    } on LocationUnavailable catch (e) {
      _error = e.message;
      notifyListeners();
      return;
    }
    if (_simulate || !_tracking) return;
    _gpsSub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, distanceFilter: 5),
    ).listen(
      (p) {
        _setGps(p);
        notifyListeners();
      },
      onError: (Object e) {
        _error = e is LocationServiceDisabledException
            ? 'Location services are turned off. Turn on GPS, or use "Simulate location".'
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
