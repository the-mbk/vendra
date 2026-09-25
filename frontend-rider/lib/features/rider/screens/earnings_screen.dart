// ══════════════════════════════════════════════════════════════
// Vendra Rider App - Earnings, delivery history and wallet (FR04)
// ══════════════════════════════════════════════════════════════

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:vendra_rider/vendra_core.dart';

import '../bloc/earnings_bloc.dart';
import '../models/rider_models.dart';

final _dateFmt = DateFormat('d MMM yyyy, h:mm a');

class EarningsScreen extends StatelessWidget {
  const EarningsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          title: const Text('Earnings'),
          automaticallyImplyLeading: false,
          bottom: const TabBar(
            labelColor: AppColors.primary,
            indicatorColor: AppColors.primary,
            unselectedLabelColor: AppColors.textSecondary,
            tabs: [Tab(text: 'Summary'), Tab(text: 'History'), Tab(text: 'Wallet')],
          ),
        ),
        body: BlocBuilder<EarningsBloc, EarningsState>(
          builder: (context, state) {
            if (state is EarningsError) {
              return _Message(
                icon: Icons.cloud_off,
                text: state.message,
                onRetry: () => context.read<EarningsBloc>().add(const EarningsRequested()),
              );
            }
            if (state is! EarningsLoaded) {
              return const LoadingShimmer(isGrid: false, itemCount: 4);
            }
            Future<void> refresh() {
              final done = Completer<void>();
              context.read<EarningsBloc>().add(EarningsRequested(done: done));
              return done.future;
            }

            return TabBarView(
              children: [
                RefreshIndicator(onRefresh: refresh, child: _Summary(earnings: state.earnings)),
                RefreshIndicator(onRefresh: refresh, child: _History(state: state)),
                RefreshIndicator(onRefresh: refresh, child: _Wallet(wallet: state.wallet)),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _Summary extends StatelessWidget {
  final RiderEarnings earnings;
  const _Summary({required this.earnings});

  @override
  Widget build(BuildContext context) {
    final e = earnings;
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: const LinearGradient(colors: [AppColors.secondary, Color(0xFF0B6BB5)]),
            borderRadius: BorderRadius.circular(18),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Wallet balance', style: GoogleFonts.poppins(color: Colors.white70, fontSize: 13)),
              Text(rs(e.walletBalance),
                  style: GoogleFonts.poppins(color: Colors.white, fontSize: 30, fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              Text('${e.allTimeCount} deliveries · ${km(e.totalKm)} ridden',
                  style: GoogleFonts.poppins(color: Colors.white70, fontSize: 12)),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _PeriodTile(label: 'Today', amount: e.today, count: e.todayCount, icon: Icons.today),
        _PeriodTile(label: 'This week', amount: e.week, count: e.weekCount, icon: Icons.date_range),
        _PeriodTile(label: 'All time', amount: e.allTime, count: e.allTimeCount, icon: Icons.all_inclusive),
        Card(
          margin: const EdgeInsets.only(bottom: 10),
          child: ListTile(
            leading: const Icon(Icons.route, color: AppColors.secondary),
            title: Text('Total distance', style: GoogleFonts.poppins(fontWeight: FontWeight.w500)),
            trailing: Text(km(e.totalKm), style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w700)),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Payout per delivery = base fee + per-km rate × GPS-tracked distance + waiting time beyond the free minutes.',
          style: GoogleFonts.poppins(fontSize: 12, color: AppColors.textSecondary),
        ),
      ],
    );
  }
}

class _PeriodTile extends StatelessWidget {
  final String label;
  final double amount;
  final int count;
  final IconData icon;
  const _PeriodTile({required this.label, required this.amount, required this.count, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: AppColors.primary.withValues(alpha: 0.12),
          child: Icon(icon, color: AppColors.primary, size: 20),
        ),
        title: Text(label, style: GoogleFonts.poppins(fontWeight: FontWeight.w500)),
        subtitle: Text('$count deliver${count == 1 ? 'y' : 'ies'}',
            style: GoogleFonts.poppins(fontSize: 12, color: AppColors.textSecondary)),
        trailing: Text(rs(amount),
            style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.success)),
      ),
    );
  }
}

/// Delivery history, loaded a page at a time: the next page is requested when
/// the footer row scrolls into view, until the server says there are no more.
class _History extends StatelessWidget {
  final EarningsLoaded state;
  const _History({required this.state});

  @override
  Widget build(BuildContext context) {
    final orders = state.history;
    final showFooter = state.hasMoreHistory || state.historyError != null;
    if (orders.isEmpty && !showFooter) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: const [
          SizedBox(height: 80),
          _Message(icon: Icons.history, text: 'No past deliveries yet. Completed deliveries show up here.'),
        ],
      );
    }
    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      itemCount: orders.length + (showFooter ? 1 : 0),
      itemBuilder: (context, i) {
        if (i == orders.length) return _HistoryFooter(state: state);
        final o = orders[i];
        final delivered = o.isDelivered;
        final when = o.deliveredAt ?? o.assignedAt;
        return Card(
          margin: const EdgeInsets.only(bottom: 10),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text('#${o.id} · ${o.storeName ?? 'Store'}',
                          style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
                    ),
                    _StatusChip(text: o.statusText, color: delivered ? AppColors.success : AppColors.error),
                  ],
                ),
                const SizedBox(height: 4),
                Text('To ${o.deliveryAddress ?? 'customer'}',
                    style: GoogleFonts.poppins(fontSize: 12, color: AppColors.textSecondary)),
                if (when != null)
                  Text(_dateFmt.format(when), style: GoogleFonts.poppins(fontSize: 11, color: AppColors.textLight)),
                if (delivered) ...[
                  const Divider(height: 20),
                  Row(
                    children: [
                      _Metric(icon: Icons.route, text: km(o.distanceKm)),
                      const SizedBox(width: 14),
                      _Metric(
                          icon: Icons.schedule,
                          text: '${(o.waitMinutes ?? 0).toStringAsFixed(0)} min wait'),
                      const Spacer(),
                      Text(rs(o.payout),
                          style: GoogleFonts.poppins(fontWeight: FontWeight.w700, color: AppColors.success)),
                    ],
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

class _HistoryFooter extends StatelessWidget {
  final EarningsLoaded state;
  const _HistoryFooter({required this.state});

  @override
  Widget build(BuildContext context) {
    final error = state.historyError;
    if (error != null) {
      // Don't retry on our own after a failure (it would loop); let the rider tap
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Column(
          children: [
            Text(error,
                textAlign: TextAlign.center,
                style: GoogleFonts.poppins(fontSize: 12, color: AppColors.textSecondary)),
            TextButton.icon(
              onPressed: () => context.read<EarningsBloc>().add(const EarningsHistoryMoreRequested()),
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('Load more'),
            ),
          ],
        ),
      );
    }
    // Built lazily, so this runs as the footer nears the viewport
    if (!state.loadingMoreHistory && state.hasMoreHistory) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) context.read<EarningsBloc>().add(const EarningsHistoryMoreRequested());
      });
    }
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 16),
      child: Center(
        child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2.5)),
      ),
    );
  }
}

class _Wallet extends StatelessWidget {
  final WalletSummary wallet;
  const _Wallet({required this.wallet});

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: ListTile(
            leading: const Icon(Icons.account_balance_wallet, color: AppColors.secondary),
            title: Text('Balance', style: GoogleFonts.poppins(fontWeight: FontWeight.w500)),
            trailing: Text(rs(wallet.balance),
                style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
          ),
        ),
        const SizedBox(height: 12),
        Text('Transactions', style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        if (wallet.transactions.isEmpty)
          const _Message(icon: Icons.receipt_long, text: 'No wallet transactions yet.'),
        for (final t in wallet.transactions)
          Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: ListTile(
              leading: CircleAvatar(
                backgroundColor: (t.isDebit ? AppColors.error : AppColors.success).withValues(alpha: 0.12),
                child: Icon(t.isDebit ? Icons.arrow_upward : Icons.arrow_downward,
                    size: 18, color: t.isDebit ? AppColors.error : AppColors.success),
              ),
              title: Text(t.label, style: GoogleFonts.poppins(fontWeight: FontWeight.w500, fontSize: 14)),
              subtitle: Text(
                [
                  if (t.description != null && t.description!.isNotEmpty) t.description!,
                  if (t.createdAt != null) _dateFmt.format(t.createdAt!),
                ].join('\n'),
                style: GoogleFonts.poppins(fontSize: 11, color: AppColors.textSecondary),
              ),
              isThreeLine: t.description != null && t.description!.isNotEmpty && t.createdAt != null,
              trailing: Text(
                '${t.isDebit ? '−' : '+'}${rs(t.amount.abs())}',
                style: GoogleFonts.poppins(
                    fontWeight: FontWeight.w700, color: t.isDebit ? AppColors.error : AppColors.success),
              ),
            ),
          ),
      ],
    );
  }
}

class _StatusChip extends StatelessWidget {
  final String text;
  final Color color;
  const _StatusChip({required this.text, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
      child: Text(text, style: GoogleFonts.poppins(fontSize: 11, fontWeight: FontWeight.w600, color: color)),
    );
  }
}

class _Metric extends StatelessWidget {
  final IconData icon;
  final String text;
  const _Metric({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 15, color: AppColors.textSecondary),
        const SizedBox(width: 4),
        Text(text, style: GoogleFonts.poppins(fontSize: 12, color: AppColors.textSecondary)),
      ],
    );
  }
}

class _Message extends StatelessWidget {
  final IconData icon;
  final String text;
  final VoidCallback? onRetry;
  const _Message({required this.icon, required this.text, this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: AppColors.textLight),
            const SizedBox(height: 12),
            Text(text, textAlign: TextAlign.center, style: GoogleFonts.poppins(color: AppColors.textSecondary)),
            if (onRetry != null) ...[
              const SizedBox(height: 16),
              VendraButton(text: 'Retry', width: 160, onPressed: onRetry),
            ],
          ],
        ),
      ),
    );
  }
}
