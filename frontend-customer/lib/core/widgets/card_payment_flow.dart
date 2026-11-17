// ══════════════════════════════════════════════════════════════
// Vendra App - "Pay with card" flow
// One call runs the whole card payment so screens stay small:
//   card sheet (tokenize at gateway) → API call with the token →
//   one-time password if `requires_action` → POST /api/payments/:id/refresh
//   → final PaymentResult { payment, order, walletBalance }
// With payments.provider == 'stripe' the card sheet is Stripe's card field
// (the token is a PaymentMethod, pm_…) and `requires_action` runs Stripe's
// 3-D Secure (nextAction.type == 'stripe_sdk') instead of the OTP dialog.
//
//   final outcome = await CardPaymentFlow.run(
//     context,
//     actionLabel: 'Pay Rs. 500',
//     submit: (token) => ApiService().post(ApiConfig.paymentsTopup, data: {'amount': 500, 'token': token}),
//   );
//   if (outcome.succeeded) ... else if (!outcome.cancelled) show(outcome.message);
// ══════════════════════════════════════════════════════════════

import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../config/api_config.dart';
import '../models/json_utils.dart';
import '../models/payment_model.dart';
import '../services/api_service.dart';
import '../services/app_config.dart';
import '../services/card_gateway.dart';
import '../services/stripe_payments.dart';
import 'card_entry_sheet.dart';
import 'otp_dialog.dart';
import 'stripe_card_sheet.dart';

/// How a card payment ended
class CardPaymentOutcome {
  /// The payment as the API last reported it (also set for a declined card)
  final PaymentResult? result;

  /// Set when the request itself failed (validation, stock, network…)
  final String? errorMessage;
  final String? errorCode;
  final Map<String, dynamic>? errorData;

  /// The user closed the card sheet, the OTP dialog or Stripe's 3-D Secure page
  final bool cancelled;

  const CardPaymentOutcome({
    this.result,
    this.errorMessage,
    this.errorCode,
    this.errorData,
    this.cancelled = false,
  });

  PaymentModel? get payment => result?.payment;
  bool get succeeded => payment?.isSucceeded == true;

  /// The wallet balance the API reported with the result, if any
  double? get walletBalance => result?.walletBalance ?? toDoubleOrNull(errorData?['walletBalance']);

  /// Readable outcome for a snackbar
  String get message {
    if (errorMessage != null) return errorMessage!;
    final p = payment;
    if (p == null) return cancelled ? 'Payment cancelled.' : 'Payment failed.';
    if (p.isSucceeded) return 'Paid Rs. ${p.amount.toStringAsFixed(0)} with ${p.cardLabel}.';
    if (p.requiresAction) return 'Payment not confirmed — you were not charged.';
    if (p.isProcessing) return 'Your payment is still processing. Check your wallet in a moment.';
    return p.failureMessage ?? 'The payment was declined.';
  }
}

class CardPaymentFlow {
  CardPaymentFlow._();

  /// Runs card entry → [submit] → 3-D Secure → refresh. [submit] posts the API
  /// request with the single-use card token (e.g. top-up or card checkout).
  static Future<CardPaymentOutcome> run(
    BuildContext context, {
    required Future<Response<dynamic>> Function(String token) submit,
    String title = 'Pay by card',
    String? subtitle,
    String actionLabel = 'Pay',
  }) async {
    if (!AppConfig.current.payments.isAvailable) await AppConfig.ensureLoaded();
    final settings = AppConfig.current.payments;
    if (!settings.isAvailable) {
      return const CardPaymentOutcome(errorMessage: 'Card payments are unavailable right now. Please try again later.');
    }
    if (!context.mounted) return const CardPaymentOutcome(cancelled: true);

    // The card: Stripe's card field, or the Vendra Pay sheet (tokenized at the gateway)
    final gateway = CardGateway();
    final CardToken? token;
    if (settings.isStripe) {
      try {
        await runWithProgress(context, 'Loading the card form…', () => StripePayments.ensureReady(settings));
      } on CardGatewayException catch (e) {
        return CardPaymentOutcome(errorMessage: e.message, errorCode: e.code);
      }
      if (!context.mounted) return const CardPaymentOutcome(cancelled: true);
      token = await showStripeCardSheet(context, title: title, subtitle: subtitle, actionLabel: actionLabel);
    } else {
      token = await showCardEntrySheet(
        context,
        title: title,
        subtitle: subtitle,
        actionLabel: actionLabel,
        gateway: gateway,
      );
    }
    if (token == null || !context.mounted) return const CardPaymentOutcome(cancelled: true);

    // 1. The API charges the card
    var outcome = await runWithProgress(context, 'Processing payment…', () => _call(() => submit(token!.id)));
    var payment = outcome.payment;
    if (payment == null || !context.mounted) return outcome;

    // 2a. Stripe's 3-D Secure: Stripe's SDK shows the bank's check, then the API re-reads the payment
    if (payment.needsStripeAction) {
      final finished = await runWithProgress(
        context,
        'Waiting for your bank…',
        () => runStripeAction(payment!.nextAction?.clientSecret),
      );
      if (!context.mounted) return outcome;
      final refreshed = await runWithProgress(context, 'Confirming payment…', () => refresh(payment!.id));
      if (refreshed.result != null) outcome = refreshed;
      if (!finished && outcome.payment?.requiresAction == true) {
        return CardPaymentOutcome(result: outcome.result, cancelled: true);
      }
      payment = outcome.payment;
    }
    if (!context.mounted) return outcome;

    // 2b. Vendra Pay's 3-D Secure: the code goes to the gateway, then the API re-reads the payment
    if (payment != null && payment.needsOtp) {
      final answered = await showOtpDialog(context, payment: payment, gateway: gateway);
      if (!context.mounted) return outcome;
      final refreshed = await runWithProgress(context, 'Confirming payment…', () => refresh(payment!.id));
      if (refreshed.result != null) outcome = refreshed;
      if (!answered && outcome.payment?.requiresAction == true) {
        return CardPaymentOutcome(result: outcome.result, cancelled: true);
      }
      payment = outcome.payment;
    }

    // 3. Rare: the gateway hadn't finished yet — look once more
    if (payment != null && payment.isProcessing && context.mounted) {
      await Future<void>.delayed(const Duration(seconds: 2));
      if (context.mounted) {
        final again = await runWithProgress(context, 'Confirming payment…', () => refresh(payment!.id));
        if (again.result != null) outcome = again;
      }
    }
    return outcome;
  }

  /// Runs Stripe's 3-D Secure for [clientSecret]. True once Stripe reached an
  /// answer (approved or failed — refresh the payment to learn which); false
  /// if the user closed the check or it couldn't start (the payment stays
  /// unconfirmed and is not charged).
  static Future<bool> runStripeAction(
    String? clientSecret, {
    @visibleForTesting Future<String?> Function(String clientSecret)? handleNextAction,
  }) async {
    if (clientSecret == null || clientSecret.isEmpty) return false;
    try {
      await (handleNextAction ?? StripePayments.handleNextAction)(clientSecret);
      return true;
    } on CardGatewayException catch (e) {
      // A failed check is still an answer; the refresh reports it as declined
      return !(e.isCancelled || e.code == 'network');
    } catch (_) {
      return false;
    }
  }

  /// POST /api/payments/:id/refresh → `{ payment, order, walletBalance }`
  static Future<CardPaymentOutcome> refresh(int paymentId) =>
      _call(() => ApiService().post(ApiConfig.paymentRefresh(paymentId)));

  /// A declined card is a 402 whose body still carries `{ payment, … }`
  static Future<CardPaymentOutcome> _call(Future<Response<dynamic>> Function() request) async {
    try {
      final res = await request();
      final result = PaymentResult.fromBody(res.data);
      if (result != null) return CardPaymentOutcome(result: result);
      final body = res.data;
      return CardPaymentOutcome(
        errorMessage: body is Map ? body['message']?.toString() ?? 'Payment failed.' : 'Payment failed.',
      );
    } on DioException catch (e) {
      final result = PaymentResult.fromBody(e.response?.data);
      if (result != null) return CardPaymentOutcome(result: result);
      final data = ApiService.getErrorData(e);
      return CardPaymentOutcome(
        errorMessage: ApiService.getErrorMessage(e),
        errorCode: data?['code']?.toString(),
        errorData: data,
      );
    } catch (e) {
      return CardPaymentOutcome(errorMessage: e.toString());
    }
  }

  /// Shows a blocking "please wait" dialog while [task] runs
  static Future<T> runWithProgress<T>(BuildContext context, String message, Future<T> Function() task) async {
    final navigator = Navigator.of(context, rootNavigator: true);
    var open = true;
    unawaited(showDialog<void>(
      context: context,
      useRootNavigator: true,
      barrierDismissible: false,
      builder: (_) => PopScope(canPop: false, child: _ProgressDialog(message: message)),
    ).whenComplete(() => open = false));
    try {
      return await task();
    } finally {
      if (open) navigator.pop();
    }
  }
}

class _ProgressDialog extends StatelessWidget {
  final String message;
  const _ProgressDialog({required this.message});

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5)),
            const SizedBox(width: 16),
            Flexible(child: Text(message, style: GoogleFonts.poppins(fontSize: 14))),
          ],
        ),
      ),
    );
  }
}

