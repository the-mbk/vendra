// ══════════════════════════════════════════════════════════════
// Vendra App - Platform config (GET /api/public-config?role=<app role>)
// Loaded in main() before the UI starts, then read anywhere through
// AppConfig.current. Admin policies (delivery fee rates, dispute window,
// geofence…) come from here, so the apps never hard-code them.
// startLiveUpdates() keeps it current: it reloads when an admin changes a
// policy (Socket.IO "config:update"), when the app returns to the foreground,
// and every 10 minutes. Widgets listen to AppConfig.notifier to redraw.
//
// If the backend can't be reached the app runs on safe defaults: treated as
// production (no dev features, no demo logins, card payments unavailable).
// Call AppConfig.ensureLoaded() before using a server value to retry.
// With payments.provider == 'stripe', each load also sets Stripe up with the
// publishable key (StripePayments.configure; only when the key changes).
//
//   void main() async {
//     WidgetsFlutterBinding.ensureInitialized();
//     await AppConfig.load(role: 'vendor');
//     AppConfig.startLiveUpdates();
//     runApp(...);
//   }
// ══════════════════════════════════════════════════════════════

import 'dart:async';

import 'package:flutter/widgets.dart';

import '../../config/api_config.dart';
import '../models/app_config_model.dart';
import '../models/json_utils.dart';
import 'api_service.dart';
import 'realtime_service.dart';
import 'stripe_payments.dart';

class AppConfig {
  /// development | production
  final String mode;
  final AppFeatures features;
  final PaymentSettings payments;

  /// Demo logins for this app's role (empty in production)
  final List<DemoAccount> demoAccounts;

  /// Delivery fee = deliveryFee (base) + deliveryFeePerKm × km, rounded to Rs 10.
  /// The exact fee for a cart comes from POST /api/customer/checkout/quote.
  final double deliveryFee;
  final double deliveryFeePerKm;

  /// Stores farther than this from the pin offer self pickup only (0 = no limit)
  final double maxDeliveryKm;
  final int disputeWindowMinutes;
  final int geofenceMeters;
  final double taskRadiusKm;
  final int defaultBuffer;
  final int vendorAcceptTimeoutMinutes;
  final int riderAssignTimeoutMinutes;

  /// A rider must reach the store this long after accepting, or the delivery goes back to other riders
  final int riderPickupTimeoutMinutes;

  /// At the store: collect the order within this long of checking in, or the delivery goes back to other riders
  final int riderStoreWaitMaxMinutes;

  /// Rider waiting pay (FR04): minutes at the store that are free, then Rs per minute
  final double riderFreeWaitMinutes;
  final double riderPerWaitMin;

  /// Share of the items a customer forfeits to the store when cancelling after the store accepted
  final double cancelPenaltyPct;

  /// Stores are told to restock a product at this many free shelf units or fewer
  final int lowStockUnits;

  /// False while running on the built-in defaults (backend unreachable)
  final bool fromServer;

  const AppConfig({
    this.mode = 'production',
    this.features = AppFeatures.none,
    this.payments = PaymentSettings.unavailable,
    this.demoAccounts = const [],
    this.deliveryFee = 0,
    this.deliveryFeePerKm = 0,
    this.maxDeliveryKm = 0,
    this.disputeWindowMinutes = 0,
    this.geofenceMeters = 200,
    this.taskRadiusKm = 5,
    this.defaultBuffer = 5,
    this.vendorAcceptTimeoutMinutes = 0,
    this.riderAssignTimeoutMinutes = 0,
    this.riderPickupTimeoutMinutes = 0,
    this.riderStoreWaitMaxMinutes = 0,
    this.riderFreeWaitMinutes = 0,
    this.riderPerWaitMin = 0,
    this.cancelPenaltyPct = 0,
    this.lowStockUnits = 5,
    this.fromServer = false,
  });

  /// Production-safe values used until (or unless) the server answers
  static const AppConfig fallback = AppConfig();

  factory AppConfig.fromJson(Map<String, dynamic> json) => AppConfig(
        mode: json['mode'] == 'development' ? 'development' : 'production',
        features: AppFeatures.fromJson(_map(json['features'])),
        payments: PaymentSettings.fromJson(_map(json['payments'])),
        demoAccounts: (json['demoAccounts'] as List<dynamic>? ?? const [])
            .whereType<Map>()
            .map((a) => DemoAccount.fromJson(Map<String, dynamic>.from(a)))
            .toList(),
        deliveryFee: toDouble(json['deliveryFee']),
        deliveryFeePerKm: toDouble(json['deliveryFeePerKm']),
        maxDeliveryKm: toDouble(json['maxDeliveryKm']),
        disputeWindowMinutes: toInt(json['disputeWindowMinutes']),
        geofenceMeters: toInt(json['geofenceMeters'], 200),
        taskRadiusKm: toDouble(json['taskRadiusKm'], 5),
        defaultBuffer: toInt(json['defaultBuffer'], 5),
        vendorAcceptTimeoutMinutes: toInt(json['vendorAcceptTimeoutMinutes']),
        riderAssignTimeoutMinutes: toInt(json['riderAssignTimeoutMinutes']),
        riderPickupTimeoutMinutes: toInt(json['riderPickupTimeoutMinutes']),
        riderStoreWaitMaxMinutes: toInt(json['riderStoreWaitMaxMinutes']),
        riderFreeWaitMinutes: toDouble(json['riderFreeWaitMinutes']),
        riderPerWaitMin: toDouble(json['riderPerWaitMin']),
        cancelPenaltyPct: toDouble(json['cancelPenaltyPct']),
        lowStockUnits: toInt(json['lowStockUnits'], 5),
        fromServer: true,
      );

  static Map<String, dynamic>? _map(dynamic v) => v is Map ? Map<String, dynamic>.from(v) : null;

  bool get isDevelopment => mode == 'development';

  /// Whether a store [km] away from the customer's pin delivers there
  bool deliversAt(double km) => maxDeliveryKm <= 0 || km <= maxDeliveryKm;

  /// Demo accounts for one role (the server already narrows by ?role=)
  List<DemoAccount> demoAccountsFor(String role) =>
      demoAccounts.where((a) => a.role == role).toList(growable: false);

  // ──────────────────────────────────────
  // Loading
  // ──────────────────────────────────────

  static String? _role;
  static Future<AppConfig>? _inFlight;

  /// The current config; listen to rebuild when a later retry succeeds
  static final ValueNotifier<AppConfig> notifier = ValueNotifier(fallback);

  static AppConfig get current => notifier.value;

  /// The role passed to [load] (customer | vendor | rider)
  static String? get role => _role;

  /// Fetches the config for this app's [role]. Never throws: on failure (or
  /// after [timeout]) it keeps the current values, so startup can't hang.
  static Future<AppConfig> load({required String role, Duration timeout = const Duration(seconds: 6)}) {
    _role = role;
    return _inFlight ??= _fetch(timeout).whenComplete(() => _inFlight = null);
  }

  /// Retries the fetch if the startup load failed; returns the current config
  static Future<AppConfig> ensureLoaded({Duration timeout = const Duration(seconds: 6)}) async {
    if (current.fromServer || _role == null) return current;
    return load(role: _role!, timeout: timeout);
  }

  /// Re-reads the config (e.g. after an admin changed a policy)
  static Future<AppConfig> refresh() => _role == null ? Future.value(current) : load(role: _role!);

  static Future<AppConfig> _fetch(Duration timeout) async {
    try {
      final res = await ApiService()
          .get(ApiConfig.publicConfig, queryParams: {'role': _role})
          .timeout(timeout);
      final data = res.data is Map ? (res.data as Map)['data'] : null;
      if (data is Map) notifier.value = AppConfig.fromJson(Map<String, dynamic>.from(data));
    } catch (e) {
      debugPrint('AppConfig: could not load /api/public-config ($e) — using production defaults');
    }
    // Stripe's card field needs the publishable key (no-op for Vendra Pay). Not
    // awaited: the card sheet waits for it (StripePayments.ensureReady) if needed.
    unawaited(StripePayments.configure(current.payments).catchError((Object e) {
      debugPrint('AppConfig: could not set up Stripe ($e)');
    }));
    return current;
  }

  static StreamSubscription<void>? _liveUpdates;
  static Timer? _liveTimer;

  /// Keeps the config current while the app runs (see the header). Safe to call twice.
  static void startLiveUpdates({Duration every = const Duration(minutes: 10)}) {
    if (_liveUpdates != null || _liveTimer != null) return;
    _liveUpdates = RealtimeService().configUpdates.listen((_) => refresh());
    _liveTimer = Timer.periodic(every, (_) => refresh());
    WidgetsBinding.instance.addObserver(_ResumeObserver());
  }

  /// For tests: replace the current config
  @visibleForTesting
  static void debugSet(AppConfig config) => notifier.value = config;
}

/// Re-reads the config when the app comes back to the foreground
class _ResumeObserver extends WidgetsBindingObserver {
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) AppConfig.refresh();
  }
}
