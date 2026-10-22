// ══════════════════════════════════════════════════════════════
// Vendra Vendor App - Wallet Screen (FR03)
// GET /api/wallet. Online order payments sit in escrow until the order
// is delivered and the dispute window passes; the store then receives
// the subtotal minus the platform commission ("escrow_release").
// Withdraw sends wallet money to a card (Vendra Pay payout); the history
// of withdrawals is listed above the transactions. Card payout references
// (po_…) can be copied from a transaction row.
// ══════════════════════════════════════════════════════════════

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:vendra_vendor/vendra_core.dart';

import '../../auth/bloc/auth_bloc.dart';
import '../../auth/bloc/auth_event.dart';
import '../widgets/wallet_widgets.dart';

class WalletScreen extends StatefulWidget {
  const WalletScreen({super.key});

  @override
  State<WalletScreen> createState() => _WalletScreenState();
}

class _WalletScreenState extends State<WalletScreen> {
  static final _money = NumberFormat('#,##0.##');
  WalletSummary? _wallet;
  bool _loading = true;
  String? _error;
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

  Future<void> _load({bool silent = false}) async {
    if (!silent) setState(() { _loading = true; _error = null; });
    try {
      final res = await ApiService().get(ApiConfig.wallet, queryParams: {'limit': 100});
      final wallet = WalletSummary.fromJson(Map<String, dynamic>.from(res.data['data'] as Map));
      if (!mounted) return;
      setState(() { _wallet = wallet; _loading = false; _error = null; });
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
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: Text('Wallet', style: GoogleFonts.poppins(fontWeight: FontWeight.w600))),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
          : _error != null
              ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(_error!, textAlign: TextAlign.center)))
              : RefreshIndicator(onRefresh: _load, child: _buildContent()),
    );
  }

  Widget _buildContent() {
    final wallet = _wallet!;
    final releases = wallet.transactions.where((t) => t.type == 'escrow_release').toList();
    final releasedTotal = releases.fold<double>(0, (sum, t) => sum + t.amount);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Balance card
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: const LinearGradient(colors: [Color(0xFF0D2137), Color(0xFF1565C0)]),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Available balance', style: GoogleFonts.poppins(color: Colors.white70, fontSize: 13)),
              const SizedBox(height: 4),
              Text('Rs. ${_money.format(wallet.balance)}',
                  style: GoogleFonts.poppins(color: Colors.white, fontSize: 30, fontWeight: FontWeight.w700)),
              const SizedBox(height: 12),
              Row(
                children: [
                  const Icon(Icons.verified_outlined, color: Colors.white70, size: 16),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      '${releases.length} escrow release${releases.length == 1 ? '' : 's'} · Rs. ${_money.format(releasedTotal)} received',
                      style: GoogleFonts.poppins(color: Colors.white, fontSize: 12),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: AppColors.secondary,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  icon: const Icon(Icons.north_east),
                  label: Text('Withdraw to card', style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
                  onPressed: () => _withdraw(wallet.balance),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.secondary.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.info_outline, size: 18, color: AppColors.secondary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Customer payments are held in escrow. After delivery and the dispute window, '
                  'the order subtotal minus the platform commission is released here. '
                  'Walk-in (POS) sales are paid at the counter and are not shown in the wallet. '
                  'Withdraw sends your balance to a debit card; if the card refuses it, the money comes back here.',
                  style: GoogleFonts.poppins(fontSize: 12, color: AppColors.secondary),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        Text('Withdrawals', style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        WithdrawalHistoryList(refreshKey: _revision, pageSize: 5),
        const SizedBox(height: 20),
        Text('Transactions', style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        if (wallet.transactions.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 40),
            child: Column(
              children: [
                Icon(Icons.account_balance_wallet_outlined, size: 56, color: Colors.grey.shade300),
                const SizedBox(height: 12),
                Text('No payments yet', style: GoogleFonts.poppins(color: AppColors.textSecondary)),
              ],
            ),
          )
        else
          for (final t in wallet.transactions) WalletTransactionTile(tx: t),
      ],
    );
  }
}
