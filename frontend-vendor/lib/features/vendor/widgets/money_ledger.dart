// ══════════════════════════════════════════════════════════════
// Vendra Vendor App - Money ledger (FR03)
// GET /api/wallet + GET /api/vendor/revenue, read like a passbook:
// - header: available balance (Withdraw), money on hold in escrow with
//   when the next payment is released, and the last 30 days (received,
//   Vendra commission paid, withdrawn)
// - "How payouts work" in three steps
// - filter All / Money in / Money out, rows grouped by day, each row in
//   plain language ("Order #12 paid out") with the commission breakdown
//   one tap away
// - withdrawal history
// Used by the Wallet screen and the Money side of the Ledger tab.
// ══════════════════════════════════════════════════════════════

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:vendra_vendor/vendra_core.dart';

import '../../auth/bloc/auth_bloc.dart';
import '../../auth/bloc/auth_event.dart';
import '../models/ledger_lines.dart';
import 'wallet_widgets.dart';

/// Escrow still held for this store (from /api/vendor/revenue)
class EscrowHold {
  final double amount;
  final int orders;

  /// The earliest delivered order's release time; null while none is delivered yet
  final DateTime? nextReleaseAt;
  const EscrowHold({required this.amount, required this.orders, this.nextReleaseAt});

  factory EscrowHold.fromJson(Map<String, dynamic> json) => EscrowHold(
        amount: toDouble(json['amount']),
        orders: toInt(json['orders']),
        nextReleaseAt: toDate(json['nextReleaseAt']),
      );
}

class MoneyLedgerView extends StatefulWidget {
  const MoneyLedgerView({super.key});

  @override
  State<MoneyLedgerView> createState() => _MoneyLedgerViewState();
}

class _MoneyLedgerViewState extends State<MoneyLedgerView> {
  WalletSummary? _wallet;
  EscrowHold? _escrow;
  bool _loading = true;
  String? _error;
  MoneyFilter _filter = MoneyFilter.all;
  StreamSubscription<OrderUpdateEvent>? _sub;
  StreamSubscription<NotificationModel>? _notifSub;

  /// Bumped after each withdrawal so the withdrawal history reloads
  int _revision = 0;

  @override
  void initState() {
    super.initState();
    _load();
    // An escrow release lands in the wallet while this screen is open
    _sub = RealtimeService().orderUpdates.listen((e) {
      if (e.escrowStatus == 'released') _load(silent: true);
    });
    // Payout arrived (reference filled in) or bounced (money returned)
    _notifSub = RealtimeService().notifications.listen((n) {
      if (isWalletNotification(n.type)) _load(silent: true);
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    _notifSub?.cancel();
    super.dispose();
  }

  Future<EscrowHold?> _loadEscrow() async {
    try {
      final res = await ApiService().get(ApiConfig.vendorRevenue);
      final data = Map<String, dynamic>.from(res.data['data'] as Map);
      return EscrowHold.fromJson(Map<String, dynamic>.from(data['inEscrow'] as Map));
    } catch (_) {
      return null; // staff without the owner role: the hold card is simply left out
    }
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent) setState(() { _loading = true; _error = null; });
    try {
      final escrow = _loadEscrow();
      final res = await ApiService().get(ApiConfig.wallet, queryParams: {'limit': 100});
      final wallet = WalletSummary.fromJson(Map<String, dynamic>.from(res.data['data'] as Map));
      final hold = await escrow;
      if (!mounted) return;
      setState(() { _wallet = wallet; _escrow = hold; _loading = false; _error = null; });
      // Keep the dashboard chip / profile in sync
      context.read<AuthBloc>().add(AuthWalletBalanceUpdated(walletBalance: wallet.balance));
    } catch (e) {
      if (!mounted) return;
      setState(() { _loading = false; if (!silent) _error = ApiService.getErrorMessage(e); });
    }
  }

  Future<void> _withdraw(double balance) async {
    final result = await startWithdrawal(context, balance: balance);
    if (result == null || !mounted) return;
    final wallet = _wallet;
    final newBalance = result.walletBalance;
    setState(() {
      // Show the new balance at once; the reload below brings the ledger row
      if (wallet != null && newBalance != null) {
        _wallet = WalletSummary(balance: newBalance, transactions: wallet.transactions);
      }
      _revision++;
    });
    await _load(silent: true);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator(color: AppColors.primary));
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.cloud_off_outlined, size: 48, color: AppColors.textLight),
              const SizedBox(height: 12),
              Text(_error!, textAlign: TextAlign.center, style: GoogleFonts.poppins(color: AppColors.textSecondary)),
              const SizedBox(height: 12),
              OutlinedButton(onPressed: _load, child: const Text('Retry')),
            ],
          ),
        ),
      );
    }

    final wallet = _wallet!;
    final shown = wallet.transactions.where((t) => describeVendorMoney(t).matches(_filter)).toList();
    final groups = groupByLedgerDay(shown, (t) => t.createdAt);

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          _BalanceHeader(
            balance: wallet.balance,
            escrow: _escrow,
            totals: summarizeMoney(wallet.transactions),
            onWithdraw: () => _withdraw(wallet.balance),
          ),
          const SizedBox(height: 12),
          const _HowPayoutsWork(),
          const SizedBox(height: 20),
          Text('Money in and out', style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              for (final f in MoneyFilter.values)
                ChoiceChip(label: Text(f.label), selected: _filter == f, onSelected: (_) => setState(() => _filter = f)),
            ],
          ),
          const SizedBox(height: 4),
          if (shown.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 36),
              child: Column(
                children: [
                  Icon(Icons.account_balance_wallet_outlined, size: 52, color: AppColors.textLight),
                  const SizedBox(height: 10),
                  Text(
                    wallet.transactions.isEmpty
                        ? 'No payments yet. Online orders are paid here after delivery.'
                        : 'Nothing here for this filter.',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.poppins(fontSize: 14, color: AppColors.textSecondary),
                  ),
                ],
              ),
            )
          else
            for (final (label, rows) in groups) ...[
              LedgerDayHeading(label: label),
              LedgerDayCard(children: [for (final t in rows) WalletTransactionTile(tx: t, grouped: true)]),
            ],
          const SizedBox(height: 20),
          Text('Withdrawals', style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
          const SizedBox(height: 8),
          WithdrawalHistoryList(refreshKey: _revision, pageSize: 5),
        ],
      ),
    );
  }
}

/// "TODAY" / "YESTERDAY" / "MON, 16 NOV" above a day's rows
class LedgerDayHeading extends StatelessWidget {
  final String label;
  const LedgerDayHeading({super.key, required this.label});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 14, 4, 8),
      child: Text(label.toUpperCase(),
          style: GoogleFonts.poppins(
              fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 0.8, color: AppColors.textSecondary)),
    );
  }
}

/// One rounded card holding a day's rows, separated by hairlines
class LedgerDayCard extends StatelessWidget {
  final List<Widget> children;
  const LedgerDayCard({super.key, required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.hairline),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) Divider(height: 1, thickness: 1, indent: 66, color: AppColors.hairline),
            children[i],
          ],
        ],
      ),
    );
  }
}

class _BalanceHeader extends StatelessWidget {
  final double balance;
  final EscrowHold? escrow;
  final MoneyTotals totals;
  final VoidCallback onWithdraw;
  const _BalanceHeader({required this.balance, required this.escrow, required this.totals, required this.onWithdraw});

  @override
  Widget build(BuildContext context) {
    final hold = escrow;
    final white70 = Colors.white.withValues(alpha: 0.75);
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppColors.navy, Color(0xFF14174A)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Available to withdraw', style: GoogleFonts.poppins(color: white70, fontSize: 13)),
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(formatRupees(balance),
                style: GoogleFonts.poppins(color: Colors.white, fontSize: 30, fontWeight: FontWeight.w700)),
          ),
          const SizedBox(height: 14),
          if (hold != null) ...[
            _HeaderStat(
              icon: Icons.lock_clock_outlined,
              label: 'On hold for you',
              value: formatRupees(hold.amount),
              note: hold.orders == 0
                  ? 'No online orders waiting for payment'
                  : '${hold.orders} order${hold.orders == 1 ? '' : 's'} · '
                      '${hold.nextReleaseAt != null ? 'next payment ${releaseTimeLabel(hold.nextReleaseAt!)}' : 'paid after delivery'}',
            ),
            const SizedBox(height: 8),
          ],
          _HeaderStat(
            icon: Icons.insights_outlined,
            label: 'Last 30 days',
            value: '${formatRupees(totals.received)} received',
            note: [
              '${totals.payouts} payment${totals.payouts == 1 ? '' : 's'}',
              if (totals.commission > 0) '${formatRupees(totals.commission)} commission',
              if (totals.withdrawn > 0) '${formatRupees(totals.withdrawn)} withdrawn',
            ].join(' · '),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: AppColors.navy,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              icon: const Icon(Icons.north_east),
              label: Text(AppConfig.current.payments.withdrawLabel, style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
              onPressed: balance > 0 ? onWithdraw : null,
            ),
          ),
        ],
      ),
    );
  }
}

class _HeaderStat extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final String note;
  const _HeaderStat({required this.icon, required this.label, required this.value, required this.note});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(icon, color: Colors.white, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(label,
                          style: GoogleFonts.poppins(fontSize: 12.5, color: Colors.white.withValues(alpha: 0.8))),
                    ),
                    Text(value, style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w700, color: Colors.white)),
                  ],
                ),
                if (note.isNotEmpty)
                  Text(note, style: GoogleFonts.poppins(fontSize: 12, color: Colors.white.withValues(alpha: 0.8))),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The payout rules in three plain steps (collapsed by default)
class _HowPayoutsWork extends StatelessWidget {
  const _HowPayoutsWork();

  String get _window {
    final m = AppConfig.current.disputeWindowMinutes;
    if (m <= 0) return 'right after delivery';
    if (m < 60) return '$m min after delivery';
    final h = m / 60;
    return '${h == h.roundToDouble() ? h.toStringAsFixed(0) : h.toStringAsFixed(1)} h after delivery';
  }

  @override
  Widget build(BuildContext context) {
    final payments = AppConfig.current.payments;
    Widget step(int n, String text) => Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: 11,
                backgroundColor: AppColors.secondary.withValues(alpha: 0.12),
                child: Text('$n', style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.secondary)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(text, style: GoogleFonts.poppins(fontSize: 13, height: 1.4, color: AppColors.textPrimary)),
              ),
            ],
          ),
        );

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.hairline),
      ),
      clipBehavior: Clip.antiAlias,
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          leading: Icon(Icons.help_outline, color: AppColors.secondary),
          title: Text('How payouts work',
              style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          children: [
            step(1, 'A customer pays online. Vendra holds the money safely ("on hold").'),
            step(2, 'You are paid $_window, once the customer can no longer report a problem. '
                'Vendra keeps its commission; the rest lands here.'),
            step(3, 'Withdraw any time to ${payments.payoutDestination}. If a payout fails, the money comes back here.'),
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text('Walk-in (counter) sales are paid to you in the shop, so they are not in this list.',
                  style: GoogleFonts.poppins(fontSize: 12.5, color: AppColors.textSecondary)),
            ),
          ],
        ),
      ),
    );
  }
}
