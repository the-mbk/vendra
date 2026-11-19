// ══════════════════════════════════════════════════════════════
// Vendra Customer App - Cancel an order (SRDS Customer.cancelOrder)
// POST /api/customer/orders/:id/cancel
//   pending    the store hasn't accepted yet: free, everything refunded
//   confirmed  accepted, not packed: the store keeps cancelPenaltyPct % of
//              the items for the work started (admin policy); the rest is
//              refunded to the wallet
// Once packed it can't be cancelled; "Report an issue" is the way then.
// The amounts are shown before the customer confirms.
// ══════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:vendra_customer/vendra_core.dart';

import '../../auth/bloc/auth_bloc.dart';
import '../../auth/bloc/auth_event.dart';
import '../bloc/order_bloc.dart';
import 'order_status_widgets.dart';

/// What cancelling now would cost and return
class CancelQuote {
  final double storeFee;
  final double refund;
  const CancelQuote(this.storeFee, this.refund);
}

/// null when the order can no longer be cancelled
CancelQuote? cancelQuote(OrderModel order, double penaltyPct) {
  if (order.status == 'pending') return CancelQuote(0, order.totalAmount);
  if (order.status != 'confirmed') return null;
  final fee = (order.subtotal * penaltyPct).roundToDouble() / 100; // to the paisa, as on the server
  return CancelQuote(fee, order.totalAmount - fee);
}

class CancelOrderSection extends StatefulWidget {
  final OrderModel order;

  /// Called after a successful cancellation (reload the order)
  final VoidCallback onCancelled;

  const CancelOrderSection({super.key, required this.order, required this.onCancelled});

  @override
  State<CancelOrderSection> createState() => _CancelOrderSectionState();
}

class _CancelOrderSectionState extends State<CancelOrderSection> {
  bool _busy = false;

  String _explain(CancelQuote q, double pct) => q.storeFee > 0
      ? 'The store has accepted it and started work, so ${formatRupees(q.storeFee)} '
          '(${pct.toStringAsFixed(pct % 1 == 0 ? 0 : 1)}% of the items) goes to the store. '
          '${formatRupees(q.refund)} comes back to your wallet.'
      : 'The store hasn\'t accepted it yet, so cancelling is free. '
          '${formatRupees(q.refund)} comes back to your wallet.';

  Future<void> _cancel(CancelQuote quote, double pct) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Cancel order #${widget.order.id}?'),
        content: Text(_explain(quote, pct)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Keep order')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Cancel order'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final res = await ApiService().post(ApiConfig.cancelOrder(widget.order.id));
      if (!mounted) return;
      final balance = (res.data['data'] as Map?)?['walletBalance'];
      if (balance != null) context.read<AuthBloc>().add(AuthWalletBalanceUpdated(walletBalance: toDouble(balance)));
      context.read<OrderBloc>().add(RefreshCustomerOrder(widget.order.id));
      messenger.showSnackBar(SnackBar(content: Text(res.data['message'] as String? ?? 'Order cancelled.'), backgroundColor: AppColors.success));
      widget.onCancelled();
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(ApiService.getErrorMessage(e)), backgroundColor: AppColors.error));
      // Packed meanwhile: reload so the button goes away
      if (ApiService.getErrorCode(e) == 'TOO_LATE_TO_CANCEL') widget.onCancelled();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final pct = AppConfig.current.cancelPenaltyPct;
    final quote = cancelQuote(widget.order, pct);
    if (quote == null) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(14),
      decoration: cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Changed your mind?', style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
          const SizedBox(height: 4),
          Text(_explain(quote, pct), style: GoogleFonts.poppins(fontSize: 12, color: AppColors.textSecondary)),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.error,
              side: const BorderSide(color: AppColors.error),
              padding: const EdgeInsets.symmetric(vertical: 12),
            ),
            onPressed: _busy ? null : () => _cancel(quote, pct),
            icon: _busy
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.cancel_outlined),
            label: const Text('Cancel order'),
          ),
        ],
      ),
    );
  }
}
