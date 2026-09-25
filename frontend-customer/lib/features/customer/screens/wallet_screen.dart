// ══════════════════════════════════════════════════════════════
// Vendra Customer App - Wallet
// Balance + transaction history from GET /api/wallet:
// top-ups, escrow holds at checkout, and refunds (cancel / dispute).
// ══════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:vendra_customer/vendra_core.dart';

import '../../../config/app_routes.dart';
import '../../auth/bloc/auth_bloc.dart';
import '../../auth/bloc/auth_event.dart';
import '../bloc/wallet_bloc.dart';

class WalletScreen extends StatelessWidget {
  const WalletScreen({super.key});

  /// Same simulated deposit as the profile card
  static const double topUpAmount = 5000;

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
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
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
                  _balanceCard(context, state),
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

  Widget _balanceCard(BuildContext context, WalletState state) {
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
            'Rs. ${state.summary!.balance.toStringAsFixed(2)}',
            style: GoogleFonts.poppins(color: Colors.white, fontSize: 28, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          Text(
            'Checkout moves the order total into escrow; cancellations and upheld disputes refund it here.',
            style: GoogleFonts.poppins(color: Colors.white70, fontSize: 11),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: Colors.green.shade800,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              icon: state.toppingUp
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.add_circle_outline),
              label: Text('Top Up (Rs. ${topUpAmount.toStringAsFixed(0)})'),
              onPressed: state.toppingUp
                  ? null
                  : () => context.read<WalletBloc>().add(const WalletTopUpRequested(topUpAmount)),
            ),
          ),
        ],
      ),
    );
  }
}

class _TransactionTile extends StatelessWidget {
  final WalletTransaction tx;
  const _TransactionTile({required this.tx});

  String get _title {
    switch (tx.type) {
      case 'escrow_hold':
        return tx.orderId != null ? 'Paid into escrow · Order #${tx.orderId}' : tx.label;
      case 'escrow_refund':
        return tx.orderId != null ? 'Refund · Order #${tx.orderId}' : tx.label;
      default:
        return tx.label;
    }
  }

  IconData get _icon {
    switch (tx.type) {
      case 'deposit':
        return Icons.add_card;
      case 'escrow_hold':
        return Icons.lock_outline;
      case 'escrow_refund':
        return Icons.replay;
      default:
        return Icons.swap_vert;
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = tx.isDebit ? AppColors.stockRed : AppColors.stockGreen;
    return ListTile(
      onTap: tx.orderId != null
          ? () => Navigator.pushNamed(context, AppRoutes.orderTracking, arguments: tx.orderId)
          : null,
      leading: CircleAvatar(
        backgroundColor: color.withValues(alpha: 0.1),
        child: Icon(_icon, color: color, size: 20),
      ),
      title: Text(_title, style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w500)),
      subtitle: Text(
        [
          if (tx.description != null && tx.description!.isNotEmpty) tx.description!,
          if (tx.createdAt != null) DateFormat('d MMM yyyy, h:mm a').format(tx.createdAt!),
        ].join('\n'),
        style: GoogleFonts.poppins(fontSize: 11, color: AppColors.textSecondary),
      ),
      isThreeLine: tx.description != null && tx.description!.isNotEmpty && tx.createdAt != null,
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            '${tx.isDebit ? '−' : '+'} Rs. ${tx.amount.toStringAsFixed(0)}',
            style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w700, color: color),
          ),
          Text('Bal. ${tx.balanceAfter.toStringAsFixed(0)}',
              style: GoogleFonts.poppins(fontSize: 10, color: AppColors.textLight)),
        ],
      ),
    );
  }
}
