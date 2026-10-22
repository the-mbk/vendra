// ══════════════════════════════════════════════════════════════
// Vendra Customer App - Wallet actions
// "Add money" (card top-up) and "Withdraw" as single calls for the wallet
// screen and the profile card. Both run the shared card flows and keep the
// balance pill (AuthBloc) in sync with what the API returned.
// ══════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:vendra_customer/vendra_core.dart';

import '../../auth/bloc/auth_bloc.dart';
import '../../auth/bloc/auth_event.dart';

/// Result of a wallet action, ready for a snackbar
class WalletActionResult {
  final bool success;
  final String message;
  const WalletActionResult({required this.success, required this.message});
}

void _syncBalance(BuildContext context, double? balance) {
  if (balance != null && context.mounted) {
    context.read<AuthBloc>().add(AuthWalletBalanceUpdated(walletBalance: balance));
  }
}

/// Amount → card → one-time password if asked → POST /api/payments/topup.
/// Null when the user backed out before paying.
Future<WalletActionResult?> startCardTopUp(BuildContext context, {double? suggestedAmount}) async {
  if (!AppConfig.current.payments.isAvailable) await AppConfig.ensureLoaded();
  if (!context.mounted) return null;
  final payments = AppConfig.current.payments;
  if (!payments.isAvailable) {
    return const WalletActionResult(
      success: false,
      message: 'Card payments are unavailable right now. Please try again later.',
    );
  }

  final amount = await showAmountSheet(
    context,
    title: 'Add money',
    subtitle: 'Pay by card — the money is in your wallet as soon as the payment goes through.',
    min: payments.minTopup,
    max: payments.maxTopup,
    quickAmounts: const [1000, 2500, 5000, 10000],
    initial: suggestedAmount?.ceilToDouble().clamp(payments.minTopup, payments.maxTopup),
    actionLabel: 'Continue to card',
  );
  if (amount == null || !context.mounted) return null;

  final outcome = await CardPaymentFlow.run(
    context,
    title: 'Add ${formatRupees(amount)}',
    subtitle: 'Top up your Vendra wallet by card.',
    actionLabel: 'Pay ${formatRupees(amount)}',
    submit: (token) => ApiService().post(ApiConfig.paymentsTopup, data: {'amount': amount, 'token': token}),
  );
  if (!context.mounted) return null;
  _syncBalance(context, outcome.walletBalance);

  if (outcome.succeeded) {
    return WalletActionResult(
      success: true,
      message: '${formatRupees(outcome.payment!.amount)} added from ${outcome.payment!.cardLabel}',
    );
  }
  if (outcome.cancelled && outcome.payment == null) return null;
  return WalletActionResult(success: false, message: outcome.message);
}

/// Amount → card → POST /api/withdrawals (the shared sheet shows the result).
/// Returns true when a withdrawal was sent.
Future<bool> startWithdrawal(BuildContext context, {required double balance}) async {
  final result = await showWithdrawSheet(context, balance: balance);
  if (result == null || !context.mounted) return false;
  _syncBalance(context, result.walletBalance);
  return true;
}
