// ══════════════════════════════════════════════════════════════
// Vendra App - Stripe card payments (payments.provider == 'stripe')
// Stripe's own card field collects the card and turns it into a
// PaymentMethod (pm_…) on Stripe's servers; only that id goes to the Vendra
// API, as `token` — card numbers never reach Vendra.
//   configure()          once the public config has loaded (AppConfig does it)
//   createPaymentMethod  from the card field that is on screen (StripeCardSheet)
//   handleNextAction     the bank's 3-D Secure check for a `requires_action`
//                        payment (nextAction.type == 'stripe_sdk')
// Works on the web (Stripe.js, via flutter_stripe_web) and on Android/iOS
// (native SDK). Desktop builds have no Stripe SDK: card payments are refused
// there with [unsupportedMessage].
// ══════════════════════════════════════════════════════════════

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_stripe/flutter_stripe.dart';

import '../models/app_config_model.dart';
import '../models/payment_model.dart';
import 'app_config.dart';
import 'card_gateway.dart';
import 'stripe_next_action_stub.dart' if (dart.library.js_interop) 'stripe_next_action_web.dart' as next_action;

class StripePayments {
  StripePayments._();

  static const String unsupportedMessage =
      "Card payments aren't supported on this platform. Please use the web or Android app.";

  /// A Stripe test card shown under the card field while `features.testCards` is on
  static const List<({String number, String label})> testCards = [
    (number: '4242 4242 4242 4242', label: 'Succeeds'),
    (number: '4000 0025 0000 3155', label: 'Asks for 3-D Secure'),
    (number: '4000 0000 0000 9995', label: 'Declined (insufficient funds)'),
  ];

  /// Stripe has an SDK for the web, Android and iOS only
  static bool get isSupportedPlatform =>
      kIsWeb || defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS;

  /// Whether [settings] call for Stripe's SDK at all
  static bool shouldInitialise(PaymentSettings settings) => settings.isStripe && settings.publishableKey.isNotEmpty;

  static String? _key;
  static Future<void>? _ready;

  /// The publishable key Stripe was set up with, if any
  static String? get publishableKey => _key;

  /// Sets Stripe up with the config's publishable key. Does nothing for Vendra
  /// Pay, without a key, or on a platform without Stripe; again only when the key
  /// changes. Safe to call on every config load.
  static Future<void> configure(PaymentSettings settings) {
    if (!shouldInitialise(settings) || !isSupportedPlatform) return Future.value();
    if (_key == settings.publishableKey && _ready != null) return _ready!;
    _key = settings.publishableKey;
    return _ready = _apply(settings.publishableKey);
  }

  static Future<void> _apply(String key) async {
    try {
      Stripe.publishableKey = key;
      await Stripe.instance.applySettings(); // on the web: loads Stripe.js
    } catch (e) {
      _key = null;
      _ready = null;
      rethrow;
    }
  }

  /// Makes sure Stripe is set up before its card field is shown.
  /// Throws [CardGatewayException] when it can't be.
  static Future<void> ensureReady([PaymentSettings? settings]) async {
    final s = settings ?? AppConfig.current.payments;
    if (!isSupportedPlatform) throw const CardGatewayException(unsupportedMessage, code: 'unsupported_platform');
    if (!shouldInitialise(s)) {
      throw const CardGatewayException('Card payments are unavailable right now. Please try again later.',
          code: 'not_configured');
    }
    try {
      await configure(s);
    } catch (e) {
      throw const CardGatewayException("Couldn't load the card form. Check your connection and try again.",
          code: 'network');
    }
  }

  /// Turns the card in the on-screen card field into a PaymentMethod (pm_…)
  static Future<CardToken> createPaymentMethod() async {
    try {
      final pm = await Stripe.instance.createPaymentMethod(
        params: const PaymentMethodParams.card(paymentMethodData: PaymentMethodData()),
      );
      return CardToken(
        id: pm.id,
        card: CardInfo(brand: normaliseBrand(pm.card.brand), last4: pm.card.last4 ?? ''),
      );
    } catch (e) {
      throw toException(e);
    }
  }

  /// Runs the bank's 3-D Secure check for a payment that came back
  /// `requires_action`; resolves to Stripe's new intent status. Afterwards the
  /// CALLER refreshes the payment (POST /api/payments/:id/refresh).
  /// A cancelled or failed check throws [CardGatewayException].
  static Future<String?> handleNextAction(String clientSecret) async {
    final key = _key ?? AppConfig.current.payments.publishableKey;
    try {
      return await next_action.runStripeNextAction(key, clientSecret);
    } catch (e) {
      throw toException(e);
    }
  }

  /// Stripe's brand names → the gateway's (visa, mastercard, amex…):
  /// the native SDKs say "Visa", "MasterCard", "AmericanExpress"
  static String normaliseBrand(String? brand) {
    final b = (brand ?? '').toLowerCase().replaceAll(RegExp('[^a-z]'), '');
    switch (b) {
      case '':
        return 'unknown';
      case 'americanexpress':
        return 'amex';
      case 'dinersclub':
        return 'diners';
      default:
        return b;
    }
  }

  /// Maps any Stripe failure to a readable [CardGatewayException].
  /// `canceled` means the user closed Stripe's sheet or 3-D Secure page.
  static CardGatewayException toException(Object error) {
    if (error is CardGatewayException) return error;
    if (error is StripeException) {
      final e = error.error;
      final cancelled = e.code == FailureCode.Canceled;
      return CardGatewayException(
        cancelled
            ? 'The card check was cancelled.'
            : _text(e.localizedMessage) ?? _text(e.message) ?? 'The card was refused.',
        code: cancelled ? 'canceled' : e.stripeErrorCode ?? e.code.name.toLowerCase(),
      );
    }
    if (error is StripeConfigException) {
      return const CardGatewayException('Card payments are unavailable right now. Please try again later.',
          code: 'not_configured');
    }
    if (error is StripeError) {
      return CardGatewayException(_text(error.message) ?? 'The card was refused.', code: '${error.code}');
    }
    // Stripe.js errors on the web are plain `{ type, code, message }` objects
    try {
      final dynamic e = error;
      final message = _text(e.message?.toString());
      if (message != null) return CardGatewayException(message, code: e.code?.toString());
    } catch (_) {
      // no message field
    }
    return const CardGatewayException('Something went wrong with the card. Please try again.');
  }

  static String? _text(String? s) => s == null || s.trim().isEmpty ? null : s.trim();
}
