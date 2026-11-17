// ══════════════════════════════════════════════════════════════
// Vendra App - Withdraw (every role)
// To a card (Vendra Pay, payments.payoutsTo == 'card'):
//   amount (≥ payments.minWithdrawal, ≤ balance) → card sheet (tokenized at
//   the gateway) → POST /api/withdrawals { amount, token } → result dialog.
//   The wallet is debited at once; the payout lands on the card shortly
//   (`in_transit` → `paid`) or bounces (`failed`) and the money comes back.
// To a payout account (payoutsTo == 'payoneer' | 'stripe_account'):
//   GET /api/payouts/account → set-up sheet until it's ready → amount, with
//   the converted value ("≈ $17.86 at Rs 280/USD") and a "View Payoneer
//   account" / "View Stripe account" link → POST /api/withdrawals { amount }
//   → result dialog.
//   Payoneer: a payout in USD to the user's Payoneer balance (`in_transit` →
//   `paid` within minutes, or `failed` and the money comes back); the user
//   then withdraws from Payoneer to their bank in Pakistan.
//   Stripe: a transfer in the platform's currency; Stripe then pays the bank.
//
//   final result = await showWithdrawSheet(context, balance: user.walletBalance);
//   if (result != null) refreshWallet(result.walletBalance);
// ══════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../config/api_config.dart';
import '../../config/app_theme.dart';
import '../models/app_config_model.dart';
import '../models/payment_model.dart';
import '../services/api_service.dart';
import '../services/app_config.dart';
import '../services/payout_accounts.dart';
import 'amount_sheet.dart';
import 'card_entry_sheet.dart';
import 'card_payment_flow.dart';
import 'payout_account_sheet.dart';

/// Runs the whole withdrawal; resolves to the result, or null if cancelled
/// or refused (the reason has already been shown to the user).
/// [accounts] is only used for payout accounts (replaceable in tests).
Future<WithdrawalResult?> showWithdrawSheet(
  BuildContext context, {
  required double balance,
  PayoutAccounts accounts = const PayoutAccounts(),
}) async {
  if (!AppConfig.current.payments.isAvailable) await AppConfig.ensureLoaded();
  if (!context.mounted) return null;
  final payments = AppConfig.current.payments;
  if (!payments.isAvailable) {
    await _info(context, 'Withdrawals unavailable', 'Card payouts are unavailable right now. Please try again later.');
    return null;
  }
  final min = payments.minWithdrawal;
  if (balance < min) {
    await _info(
      context,
      'Not enough to withdraw',
      'You need at least ${formatRupees(min)} in your wallet to withdraw. Your balance is ${formatRupees(balance)}.',
    );
    return null;
  }
  if (payments.paysOutToAccount) return _withdrawToAccount(context, balance, payments, accounts);

  // 1. How much
  final amount = await showAmountSheet(
    context,
    title: 'Withdraw to a card',
    subtitle: 'Available: ${formatRupees(balance)}. The money leaves your wallet now and reaches the card shortly.',
    min: min,
    max: balance,
    quickAmounts: (<double>{min, 1000, 5000, 10000, balance.floorToDouble()}.toList()..sort()),
    initial: balance.floorToDouble() >= min ? balance.floorToDouble() : null,
  );
  if (amount == null || !context.mounted) return null;

  // 2. Which card
  final token = await showCardEntrySheet(
    context,
    title: 'Card to receive the money',
    subtitle: '${formatRupees(amount)} will be sent to this card. Debit cards work best.',
    actionLabel: 'Withdraw ${formatRupees(amount)}',
    forPayout: true,
  );
  if (token == null || !context.mounted) return null;

  // 3. Send it
  WithdrawalResult? result;
  String? error;
  await CardPaymentFlow.runWithProgress(context, 'Sending your withdrawal…', () async {
    try {
      final res = await ApiService().post(ApiConfig.withdrawals, data: {'amount': amount, 'token': token.id});
      result = WithdrawalResult.fromJson(Map<String, dynamic>.from(res.data['data'] as Map));
    } catch (e) {
      error = ApiService.getErrorMessage(e);
    }
  });
  if (!context.mounted) return result;

  if (result == null) {
    await _info(context, "Couldn't withdraw", error ?? 'Please try again.');
    return null;
  }
  await _success(context, result!);
  return result;
}

/// Withdrawal to the user's payout account — Payoneer or Stripe (no card involved)
Future<WithdrawalResult?> _withdrawToAccount(
  BuildContext context,
  double balance,
  PaymentSettings payments,
  PayoutAccounts accounts,
) async {
  // 1. The payout account must be ready
  PayoutAccountStatus? status;
  String? error;
  await CardPaymentFlow.runWithProgress(context, 'Checking your payout account…', () async {
    try {
      status = await accounts.fetch();
    } catch (e) {
      error = PayoutAccounts.errorMessage(e);
    }
  });
  if (!context.mounted) return null;
  if (status == null) {
    await _info(context, "Couldn't check your payout account", error ?? 'Please try again.');
    return null;
  }
  if (!status!.isReady) {
    status = await showPayoutAccountSheet(context, status: status!, accounts: accounts);
    if (status == null || !context.mounted) return null;
  }
  final account = status!;
  final provider = account.payoutProvider;
  final currency = account.currency?.toUpperCase();
  final inCurrency = currency != null ? ' in $currency' : '';
  final then = account.isPayoneer
      ? 'from Payoneer you can withdraw it to your bank in Pakistan'
      : 'Stripe then pays it into your bank';

  // 2. How much (with the converted amount the account will receive)
  final min = payments.minWithdrawal;
  final amount = await showAmountSheet(
    context,
    title: provider.withdrawLabel,
    subtitle: 'Available: ${formatRupees(balance)}. The money leaves your wallet now and goes to '
        '${provider.destination}$inCurrency; $then.',
    min: min,
    max: balance,
    quickAmounts: (<double>{min, 1000, 5000, 10000, balance.floorToDouble()}.toList()..sort()),
    initial: balance.floorToDouble() >= min ? balance.floorToDouble() : null,
    actionLabel: 'Withdraw',
    note: account.conversionText,
    footer: PayoutDashboardLink(accounts: accounts, provider: provider),
  );
  if (amount == null || !context.mounted) return null;

  // 3. Send it
  WithdrawalResult? result;
  String? code;
  await CardPaymentFlow.runWithProgress(context, 'Sending your withdrawal…', () async {
    try {
      result = await accounts.withdraw(amount);
    } catch (e) {
      error = PayoutAccounts.errorMessage(e);
      code = ApiService.getErrorCode(e);
    }
  });
  if (!context.mounted) return result;

  if (result == null) {
    await _info(context, "Couldn't withdraw", error ?? 'Please try again.');
    // The account changed since it was checked: show where it stands now
    if (context.mounted && (code == 'PAYOUT_ACCOUNT_REQUIRED' || code == 'PAYOUT_ACCOUNT_PENDING')) {
      try {
        final fresh = await accounts.fetch();
        if (context.mounted && !fresh.isReady) await showPayoutAccountSheet(context, status: fresh, accounts: accounts);
      } catch (_) {
        // the message above already explains it
      }
    }
    return null;
  }
  await _accountSuccess(context, result!, account);
  return result;
}

Future<void> _accountSuccess(BuildContext context, WithdrawalResult result, PayoutAccountStatus account) {
  final w = result.withdrawal;
  final payoneer = account.isPayoneer;
  // What the account received; before the payout is made, the estimate
  final converted = w.convertedLabel != null ? 'received as ${w.convertedLabel}' : account.conversionText(w.amount);
  final title = payoneer
      ? (w.isPaid ? 'Sent to your Payoneer balance' : 'On its way to Payoneer')
      : (w.isPaid ? 'Sent to your Stripe account' : 'On its way to your Stripe account');
  final next = payoneer
      ? 'It usually reaches your Payoneer balance within a few minutes; from there you can withdraw it to your '
          'bank in Pakistan. See it under "View Payoneer account". '
          'If the payment fails, the money comes straight back to your wallet.'
      : 'Stripe pays it into your bank on its usual schedule; see it under "View Stripe account". '
          'If the transfer fails, the money comes straight back to your wallet.';
  return showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      icon: const Icon(Icons.north_east_rounded, color: AppColors.success, size: 36),
      title: Text(title,
          textAlign: TextAlign.center, style: GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 17)),
      content: Text(
        '${formatRupees(w.amount)} has left your wallet${converted != null ? ' ($converted)' : ''}. $next'
        '${result.walletBalance != null ? '\n\nWallet balance: ${formatRupees(result.walletBalance!)}' : ''}',
        textAlign: TextAlign.center,
        style: GoogleFonts.poppins(fontSize: 13, color: AppColors.textSecondary),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Done'))],
    ),
  );
}

Future<void> _info(BuildContext context, String title, String message) {
  return showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Text(title, style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
      content: Text(message, style: GoogleFonts.poppins(fontSize: 13, color: AppColors.textSecondary)),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK'))],
    ),
  );
}

Future<void> _success(BuildContext context, WithdrawalResult result) {
  final w = result.withdrawal;
  return showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      icon: const Icon(Icons.north_east_rounded, color: AppColors.success, size: 36),
      title: Text('On its way to ${w.cardLabel}',
          textAlign: TextAlign.center, style: GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 17)),
      content: Text(
        '${formatRupees(w.amount)} has left your wallet and should reach the card shortly. '
        "If the card can't receive it, the money comes straight back to your wallet."
        '${result.walletBalance != null ? '\n\nWallet balance: ${formatRupees(result.walletBalance!)}' : ''}',
        textAlign: TextAlign.center,
        style: GoogleFonts.poppins(fontSize: 13, color: AppColors.textSecondary),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Done'))],
    ),
  );
}
