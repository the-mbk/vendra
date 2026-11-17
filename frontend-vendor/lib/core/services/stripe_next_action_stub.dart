// ══════════════════════════════════════════════════════════════
// Vendra App - Stripe 3-D Secure, mobile (see stripe_payments.dart)
// Android/iOS run the bank's check with the native Stripe SDK. The web build
// imports stripe_next_action_web.dart instead.
// ══════════════════════════════════════════════════════════════

import 'package:flutter_stripe/flutter_stripe.dart';

/// Runs the PaymentIntent's next action; resolves to its new Stripe status
Future<String?> runStripeNextAction(String publishableKey, String clientSecret) async {
  final intent = await Stripe.instance.handleNextAction(clientSecret);
  return intent.status.name;
}
