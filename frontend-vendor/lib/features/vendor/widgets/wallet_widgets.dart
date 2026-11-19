// ══════════════════════════════════════════════════════════════
// Vendra Vendor App - Wallet pieces
// - startWithdrawal: the shared "withdraw to card" flow, keeping the
//   wallet chip (AuthBloc) in sync with the balance the API returned.
//   Used by the wallet screen, the home wallet card and the profile.
// - isWalletNotification: notifications that mean the balance changed
// - WalletTransactionTile: one money row in plain language ("Order #12 paid out",
//   signed amount, balance after); tap it for the commission breakdown
//   and the payment / payout reference to copy
// ══════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:vendra_vendor/vendra_core.dart';

import '../../auth/bloc/auth_bloc.dart';
import '../../auth/bloc/auth_event.dart';
import '../models/ledger_lines.dart';

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

class WalletTransactionTile extends StatefulWidget {
  final WalletTransaction tx;

  /// Inside a grouped day card the row draws no card of its own
  final bool grouped;
  const WalletTransactionTile({super.key, required this.tx, this.grouped = false});

  @override
  State<WalletTransactionTile> createState() => _WalletTransactionTileState();
}

class _WalletTransactionTileState extends State<WalletTransactionTile> {
  bool _open = false;

  WalletTransaction get tx => widget.tx;

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
    final line = describeVendorMoney(tx);
    final amountColor = line.isIn ? AppColors.success : AppColors.error;
    final desc = tx.description?.trim() ?? '';
    final hasMore = line.breakdown != null || tx.reference != null || (desc.isNotEmpty && desc != line.detail);

    final row = InkWell(
      onTap: hasMore ? () => setState(() => _open = !_open) : null,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: line.color.withValues(alpha: AppColors.isDark ? 0.20 : 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(line.icon, color: line.color, size: 21),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(line.title,
                          style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                      if (line.detail.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(line.detail,
                              maxLines: _open ? null : 2,
                              overflow: _open ? null : TextOverflow.ellipsis,
                              style: GoogleFonts.poppins(fontSize: 13, height: 1.35, color: AppColors.textSecondary)),
                        ),
                      if (tx.createdAt != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 3),
                          child: Text(DateFormat('h:mm a').format(tx.createdAt!.toLocal()),
                              style: GoogleFonts.poppins(fontSize: 12, color: AppColors.textSecondary)),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(tx.amountText,
                        style: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w700, color: amountColor)),
                    Text('Balance ${formatRupees(tx.balanceAfter)}',
                        style: GoogleFonts.poppins(fontSize: 11.5, color: AppColors.textSecondary)),
                    if (hasMore)
                      Icon(_open ? Icons.expand_less : Icons.expand_more, size: 20, color: AppColors.textSecondary),
                  ],
                ),
              ],
            ),
            if (_open) _details(context, line, desc),
          ],
        ),
      ),
    );

    if (widget.grouped) return Material(color: Colors.transparent, child: row);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.hairline),
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(color: Colors.transparent, child: row),
    );
  }

  Widget _details(BuildContext context, MoneyLine line, String desc) {
    final b = line.breakdown;
    final label = GoogleFonts.poppins(fontSize: 13, color: AppColors.textSecondary);
    Widget pair(String k, String v, {bool strong = false, Color? color}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(children: [
            Expanded(child: Text(k, style: label)),
            Text(v,
                style: GoogleFonts.poppins(
                    fontSize: 13,
                    fontWeight: strong ? FontWeight.w700 : FontWeight.w500,
                    color: color ?? AppColors.textPrimary)),
          ]),
        );

    return Container(
      margin: const EdgeInsets.only(top: 12, left: 52),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: AppColors.surfaceMuted, borderRadius: BorderRadius.circular(10)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (b != null) ...[
            pair('Items sold', b.items),
            pair('Vendra commission (${b.percent}%)', '− ${b.commission}', color: AppColors.error),
            Divider(height: 14, color: AppColors.hairline),
            pair('You received', b.net, strong: true, color: AppColors.success),
          ] else if (desc.isNotEmpty)
            Text(desc, style: GoogleFonts.poppins(fontSize: 13, height: 1.4, color: AppColors.textPrimary)),
          if (tx.reference != null)
            InkWell(
              onTap: () => _copyReference(context),
              borderRadius: BorderRadius.circular(4),
              child: Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(
                        'Ref. ${tx.reference}',
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.robotoMono(fontSize: 12, color: AppColors.textSecondary),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Icon(Icons.copy, size: 14, color: AppColors.textSecondary),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
