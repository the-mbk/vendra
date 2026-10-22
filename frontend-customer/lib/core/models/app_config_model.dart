// ══════════════════════════════════════════════════════════════
// Vendra App - Platform config parts (GET /api/public-config)
// Development-only switches, card gateway settings and demo accounts.
// Every default here is the production one: features off, no demo logins.
// ══════════════════════════════════════════════════════════════

import 'json_utils.dart';

/// Switches the backend turns on only in development mode
class AppFeatures {
  /// Riders may set their position by hand / simulate a drive
  final bool manualLocation;

  /// Show the sandbox test-card helper in the card sheet
  final bool testCards;

  /// Timers (dispute window, accept timeouts…) are shortened for demos
  final bool fastTimers;

  /// Show one-tap demo accounts on the login screen
  final bool demoLogin;

  const AppFeatures({
    this.manualLocation = false,
    this.testCards = false,
    this.fastTimers = false,
    this.demoLogin = false,
  });

  static const AppFeatures none = AppFeatures();

  factory AppFeatures.fromJson(Map<String, dynamic>? json) {
    if (json == null) return none;
    return AppFeatures(
      manualLocation: json['manualLocation'] == true,
      testCards: json['testCards'] == true,
      fastTimers: json['fastTimers'] == true,
      demoLogin: json['demoLogin'] == true,
    );
  }
}

/// Card gateway settings for tokenizing cards in the app
class PaymentSettings {
  final String gatewayUrl;
  final String publishableKey;
  final double minTopup;
  final double maxTopup;
  final double minWithdrawal;

  const PaymentSettings({
    this.gatewayUrl = '',
    this.publishableKey = '',
    this.minTopup = 100,
    this.maxTopup = 500000,
    this.minWithdrawal = 500,
  });

  static const PaymentSettings unavailable = PaymentSettings();

  factory PaymentSettings.fromJson(Map<String, dynamic>? json) {
    if (json == null) return unavailable;
    return PaymentSettings(
      gatewayUrl: (json['gatewayUrl'] ?? '').toString(),
      publishableKey: (json['publishableKey'] ?? '').toString(),
      minTopup: toDouble(json['minTopup'], 100),
      maxTopup: toDouble(json['maxTopup'], 500000),
      minWithdrawal: toDouble(json['minWithdrawal'], 500),
    );
  }

  /// False when the config couldn't be loaded — card actions are then disabled
  bool get isAvailable => gatewayUrl.isNotEmpty && publishableKey.isNotEmpty;
}

/// A seeded account offered on the login screen in development
class DemoAccount {
  final String role;
  final String name;
  final String email;
  final String password;
  final String? note;

  const DemoAccount({
    required this.role,
    required this.name,
    required this.email,
    required this.password,
    this.note,
  });

  factory DemoAccount.fromJson(Map<String, dynamic> json) => DemoAccount(
        role: (json['role'] ?? '').toString(),
        name: (json['name'] ?? '').toString(),
        email: (json['email'] ?? '').toString(),
        password: (json['password'] ?? '').toString(),
        note: json['note']?.toString(),
      );
}
