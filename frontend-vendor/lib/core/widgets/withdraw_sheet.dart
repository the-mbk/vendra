// ══════════════════════════════════════════════════════════════
// Vendra App - Withdraw to card (every role)
// amount (≥ payments.minWithdrawal, ≤ balance) → card sheet (tokenized at
// the gateway) → POST /api/withdrawals { amount, token } → result dialog.
// The wallet is debited at once; the payout lands on the card shortly
// (`in_transit` → `paid`) or bounces (`failed`) and the money comes back.
//
//   final result = await showWithdrawSheet(context, balance: user.walletBalance);
//   if (result != null) refreshWallet(result.walletBalance);
// ══════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../config/api_config.dart';
import '../../config/app_theme.dart';
import '../models/payment_model.dart';
import '../services/api_service.dart';
import '../services/app_config.dart';
import 'amount_sheet.dart';
import 'card_entry_sheet.dart';
import 'card_payment_flow.dart';

/// Runs the whole withdrawal; resolves to the result, or null if cancelled
/// or refused (the reason has already been shown to the user).
Future<WithdrawalResult?> showWithdrawSheet(BuildContext context, {required double balance}) async {
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
