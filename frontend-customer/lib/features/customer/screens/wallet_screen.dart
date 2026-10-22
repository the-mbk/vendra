// ══════════════════════════════════════════════════════════════
// Vendra Customer App - Wallet
// Balance + transaction history from GET /api/wallet: card top-ups,
// escrow holds at checkout, refunds (cancel / dispute) and withdrawals.
// - Add money: amount → card → one-time password if the bank asks
// - Withdraw: send wallet money back to a card (history below)
// - Card payment / payout references (pi_… / po_…) can be copied
// ══════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:vendra_customer/vendra_core.dart';

import '../../../config/app_routes.dart';
import '../../auth/bloc/auth_bloc.dart';
import '../../auth/bloc/auth_event.dart';
import '../bloc/wallet_bloc.dart';
import '../widgets/wallet_actions.dart';

class WalletScreen extends StatelessWidget {
  const WalletScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => WalletBloc()..add(const FetchWallet()),
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(title: Text('My Wallet', style: GoogleFonts.poppins(fontWeight: FontWeight.w600))),
        body: BlocConsumer<WalletBloc, WalletState>(
          listenWhen: (prev, curr) =>
              curr.feedback != null || prev.summary?.balance != curr.summary?.balance,
          listener: (context, state) {
            final balance = state.summary?.balance;
            if (balance != null) {
              // Keep the balance pill in the home app bar in sync
              context.read<AuthBloc>().add(AuthWalletBalanceUpdated(walletBalance: balance));
            }
            if (state.feedback != null) {
              ScaffoldMessenger.of(context)
                ..hideCurrentSnackBar()
                ..showSnackBar(SnackBar(
                  content: Text(state.feedback!),
                  backgroundColor: state.feedbackIsError ? AppColors.error : AppColors.stockGreen,
                  behavior: SnackBarBehavior.floating,
                ));
            }
          },
          builder: (context, state) {
            final summary = state.summary;
            if (state.loading && summary == null) {
              return const Center(child: CircularProgressIndicator(color: AppColors.primary));
            }
            if (summary == null) {
              return Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(state.error ?? 'Could not load wallet', style: GoogleFonts.poppins(color: AppColors.textSecondary)),
                    TextButton(
                      onPressed: () => context.read<WalletBloc>().add(const FetchWallet()),
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              );
            }

            return RefreshIndicator(
              color: AppColors.primary,
              onRefresh: () async => context.read<WalletBloc>().add(const FetchWallet(silent: true)),
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _balanceCard(context, summary.balance),
                  const SizedBox(height: 20),
                  Text('Withdrawals', style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  WithdrawalHistoryList(refreshKey: state.revision, pageSize: 5),
                  const SizedBox(height: 20),
                  Text('Transactions', style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  if (summary.transactions.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 32),
                      child: Text('No transactions yet.',
                          textAlign: TextAlign.center, style: GoogleFonts.poppins(color: AppColors.textSecondary)),
                    )
                  else
                    Container(
                      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
                      child: Column(
                        children: [
                          for (var i = 0; i < summary.transactions.length; i++) ...[
                            if (i > 0) const Divider(height: 1, indent: 64),
                            _TransactionTile(tx: summary.transactions[i]),
                          ],
                        ],
                      ),
                    ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Future<void> _addMoney(BuildContext context) async {
    final bloc = context.read<WalletBloc>();
    final result = await startCardTopUp(context);
    if (result == null) return;
    bloc.add(WalletChanged(feedback: result.message, isError: !result.success));
  }

  Future<void> _withdraw(BuildContext context, double balance) async {
    final bloc = context.read<WalletBloc>();
    // The shared sheet already showed the outcome; just reload
    if (await startWithdrawal(context, balance: balance)) bloc.add(const WalletChanged());
  }

  Widget _balanceCard(BuildContext context, double balance) {
    final buttonShape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(10));
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF2E7D32), Color(0xFF1B5E20)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Available balance', style: GoogleFonts.poppins(color: Colors.green.shade100, fontSize: 14)),
          const SizedBox(height: 6),
          Text(
            formatRupees(balance),
            style: GoogleFonts.poppins(color: Colors.white, fontSize: 28, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          Text(
            'Checkout moves the order total into escrow; cancellations and upheld disputes refund it here.',
            style: GoogleFonts.poppins(color: Colors.white70, fontSize: 11),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: Colors.green.shade800,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: buttonShape,
                  ),
                  icon: const Icon(Icons.add_card),
                  label: const Text('Add money'),
                  onPressed: () => _addMoney(context),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: const BorderSide(color: Colors.white),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: buttonShape,
                  ),
                  icon: const Icon(Icons.north_east),
                  label: const Text('Withdraw'),
                  onPressed: () => _withdraw(context, balance),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TransactionTile extends StatelessWidget {
  final WalletTransaction tx;
  const _TransactionTile({required this.tx});

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
    final details = [
      if (tx.description != null && tx.description!.isNotEmpty) tx.description!,
      if (tx.createdAt != null) DateFormat('d MMM yyyy, h:mm a').format(tx.createdAt!),
    ];
    return ListTile(
      onTap: tx.orderId != null
          ? () => Navigator.pushNamed(context, AppRoutes.orderTracking, arguments: tx.orderId)
          : null,
      leading: CircleAvatar(
        backgroundColor: color.withValues(alpha: 0.1),
        child: Icon(tx.icon, color: color, size: 20),
      ),
      title: Text(tx.title, style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w500)),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (details.isNotEmpty)
            Text(details.join('\n'), style: GoogleFonts.poppins(fontSize: 11, color: AppColors.textSecondary)),
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
      isThreeLine: details.length + (tx.reference != null ? 1 : 0) > 1,
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            tx.amountText,
            style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w700, color: color),
          ),
          Text('Bal. ${formatRupees(tx.balanceAfter)}',
              style: GoogleFonts.poppins(fontSize: 10, color: AppColors.textLight)),
        ],
      ),
    );
  }
}
