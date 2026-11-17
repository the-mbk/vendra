// ══════════════════════════════════════════════════════════════
// Vendra App - Platform config parts (GET /api/public-config)
// Development-only switches, card gateway settings and demo accounts.
// Every default here is the production one: features off, no demo logins.
// ══════════════════════════════════════════════════════════════

import 'json_utils.dart';
import 'payment_model.dart';

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

/// Card payment settings: which gateway collects cards, and where withdrawals go
class PaymentSettings {
  /// vendrapay (cards tokenized at [gatewayUrl]) | stripe (Stripe's own card field)
  final String provider;

  /// Vendra Pay only; empty with Stripe
  final String gatewayUrl;
  final String publishableKey;

  /// card (Vendra Pay pays out to a card) | payoneer (the user's linked Payoneer
  /// account) | stripe_account (the user's Stripe payout account)
  final String payoutsTo;
  final double minTopup;
  final double maxTopup;
  final double minWithdrawal;

  const PaymentSettings({
    this.provider = 'vendrapay',
    this.gatewayUrl = '',
    this.publishableKey = '',
    this.payoutsTo = 'card',
    this.minTopup = 100,
    this.maxTopup = 500000,
    this.minWithdrawal = 500,
  });

  static const PaymentSettings unavailable = PaymentSettings();

  factory PaymentSettings.fromJson(Map<String, dynamic>? json) {
    if (json == null) return unavailable;
    final provider = (json['provider'] ?? 'vendrapay').toString().trim().toLowerCase();
    return PaymentSettings(
      provider: provider.isEmpty ? 'vendrapay' : provider,
      gatewayUrl: (json['gatewayUrl'] ?? '').toString(),
      publishableKey: (json['publishableKey'] ?? '').toString(),
      payoutsTo: const ['payoneer', 'stripe_account'].contains(json['payoutsTo']) ? json['payoutsTo'] as String : 'card',
      minTopup: toDouble(json['minTopup'], 100),
      maxTopup: toDouble(json['maxTopup'], 500000),
      minWithdrawal: toDouble(json['minWithdrawal'], 500),
    );
  }

  bool get isStripe => provider == 'stripe';

  /// Where withdrawals go: card | payoneer | stripe (the shared wording lives there)
  PayoutProvider get payoutProvider => PayoutProvider.fromPayoutsTo(payoutsTo);

  /// Withdrawals go to a payout account (Payoneer / Stripe) the user sets up once
  bool get paysOutToAccount => payoutProvider.needsAccount;

  /// Withdrawals go to the user's linked Payoneer account
  bool get paysOutToPayoneer => payoutProvider == PayoutProvider.payoneer;

  /// Withdrawals go to the user's Stripe Connect account
  bool get paysOutToStripeAccount => payoutProvider == PayoutProvider.stripe;

  /// Where withdrawals go, for wording: "a debit card" | "your Payoneer account" | "your Stripe account"
  String get payoutDestination => payoutProvider.destination;

  /// Withdraw button text: "Withdraw to card" | "Withdraw to Payoneer" | "Withdraw to Stripe"
  String get withdrawLabel => payoutProvider.withdrawLabel;

  /// False when the config couldn't be loaded — card actions are then disabled.
  /// Stripe needs only its publishable key; Vendra Pay also needs the gateway URL.
  bool get isAvailable => publishableKey.isNotEmpty && (isStripe || gatewayUrl.isNotEmpty);
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
