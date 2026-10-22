// ══════════════════════════════════════════════════════════════
// Vendra Vendor App - Wallet pieces
// - startWithdrawal: the shared "withdraw to card" flow, keeping the
//   wallet chip (AuthBloc) in sync with the balance the API returned.
//   Used by the wallet screen, the home wallet card and the profile.
// - isWalletNotification: notifications that mean the balance changed
// - WalletTransactionTile: one ledger row (readable title, signed amount,
//   payment / payout reference that can be copied)
// ══════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:vendra_vendor/vendra_core.dart';

import '../../auth/bloc/auth_bloc.dart';
import '../../auth/bloc/auth_event.dart';

/// Notification types sent to a vendor when the wallet balance changes
/// (escrow released to the store, a payout arrived or bounced back)
const Set<String> vendorWalletNotificationTypes = {
  'escrow_released',
  'withdrawal_paid',
  'withdrawal_failed',
  'withdrawal_reversal',
};

bool isWalletNotification(String type) => vendorWalletNotificationTypes.contains(type);

/// Amount → card → POST /api/withdrawals. The shared sheet shows the outcome;
/// this keeps AuthBloc's balance in sync. Null if cancelled or refused.
Future<WithdrawalResult?> startWithdrawal(BuildContext context, {required double balance}) async {
  final result = await showWithdrawSheet(context, balance: balance);
  if (result == null || !context.mounted) return result;
  final newBalance = result.walletBalance;
  if (newBalance != null) {
    context.read<AuthBloc>().add(AuthWalletBalanceUpdated(walletBalance: newBalance));
  } else {
    context.read<AuthBloc>().add(RefreshUserRequested());
  }
  return result;
}

class WalletTransactionTile extends StatelessWidget {
  final WalletTransaction tx;
  const WalletTransactionTile({super.key, required this.tx});

  static final _money = NumberFormat('#,##0.##');

  void _copyReference(BuildContext context) {
    Clipboard.setData(ClipboardData(text: tx.reference!));
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text('Copied ${tx.reference}'),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ));
  }

  @override
  Widget build(BuildContext context) {
    final color = tx.isDebit ? AppColors.stockRed : AppColors.stockGreen;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 6)],
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(color: color.withValues(alpha: 0.1), shape: BoxShape.circle),
            child: Icon(tx.icon, color: color, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(tx.title,
                    style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                if (tx.description != null && tx.description!.isNotEmpty)
                  Text(tx.description!, style: GoogleFonts.poppins(fontSize: 12, color: AppColors.textSecondary)),
                if (tx.createdAt != null)
                  Text(DateFormat('MMM dd, hh:mm a').format(tx.createdAt!),
                      style: GoogleFonts.poppins(fontSize: 11, color: AppColors.textLight)),
                if (tx.reference != null)
                  InkWell(
                    onTap: () => _copyReference(context),
                    borderRadius: BorderRadius.circular(4),
                    child: Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Flexible(
                            child: Text(
                              'Ref. ${tx.reference}',
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.robotoMono(fontSize: 10, color: AppColors.textLight),
                            ),
                          ),
                          const SizedBox(width: 4),
                          const Icon(Icons.copy, size: 11, color: AppColors.textLight),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(tx.amountText, style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w700, color: color)),
              Text('Bal: Rs. ${_money.format(tx.balanceAfter)}',
                  style: GoogleFonts.poppins(fontSize: 11, color: AppColors.textLight)),
            ],
          ),
        ],
      ),
    );
  }
}
