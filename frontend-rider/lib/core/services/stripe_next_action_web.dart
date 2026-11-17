// ══════════════════════════════════════════════════════════════
// Vendra App - Stripe 3-D Secure, web (see stripe_payments.dart)
// Calls Stripe.js `stripe.handleNextAction({ clientSecret })` directly.
// flutter_stripe_web's handleNextAction uses `handleCardAction`, which only
// accepts manually confirmed intents; the backend confirms automatically
// (confirm: true, use_stripe_sdk: true), which handleNextAction expects.
// Stripe.js shows the bank's check in its own overlay above the app.
// ══════════════════════════════════════════════════════════════

import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'card_gateway.dart';

JSObject? _stripe;
String? _stripeKey;

/// Runs the PaymentIntent's next action; resolves to its new Stripe status.
/// Throws [CardGatewayException] when Stripe reports an error (e.g. the check failed).
Future<String?> runStripeNextAction(String publishableKey, String clientSecret) async {
  if (_stripe == null || _stripeKey != publishableKey) {
    if (!globalContext.has('Stripe')) {
      throw const CardGatewayException('Stripe has not loaded. Check your connection and try again.', code: 'network');
    }
    _stripe = globalContext.callMethod<JSObject>('Stripe'.toJS, publishableKey.toJS);
    _stripeKey = publishableKey;
  }
  final options = JSObject()..setProperty('clientSecret'.toJS, clientSecret.toJS);
  final result = await _stripe!.callMethod<JSPromise<JSObject>>('handleNextAction'.toJS, options).toDart;

  final error = result.getProperty<JSObject?>('error'.toJS);
  if (error != null) {
    throw CardGatewayException(
      error.getProperty<JSString?>('message'.toJS)?.toDart ?? 'Your bank could not confirm the payment.',
      code: error.getProperty<JSString?>('code'.toJS)?.toDart ?? 'authentication_failed',
    );
  }
  final intent = result.getProperty<JSObject?>('paymentIntent'.toJS);
  return intent?.getProperty<JSString?>('status'.toJS)?.toDart;
}
