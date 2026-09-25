// ══════════════════════════════════════════════════════════════
// Vendra Vendor App - Wallet Screen (FR03)
// GET /api/wallet. Online order payments sit in escrow until the order
// is delivered and the dispute window passes; the store then receives
// the subtotal minus the platform commission ("escrow_release").
// ══════════════════════════════════════════════════════════════

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:vendra_vendor/vendra_core.dart';

import '../../auth/bloc/auth_bloc.dart';
import '../../auth/bloc/auth_event.dart';

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

  @override
  void initState() {
    super.initState();
    _load();
    // An escrow release lands in the wallet while this screen is open
    _sub = RealtimeService().orderUpdates.listen((e) {
      if (e.escrowStatus == 'released') _load(silent: true);
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent) setState(() { _loading = true; _error = null; });
    try {
      final res = await ApiService().get(ApiConfig.wallet, queryParams: {'limit': 100});
      final wallet = WalletSummary.fromJson(Map<String, dynamic>.from(res.data['data'] as Map));
      if (!mounted) return;
      setState(() { _wallet = wallet; _loading = false; _error = null; });
      context.read<AuthBloc>().add(RefreshUserRequested()); // keep the dashboard chip in sync
    } catch (e) {
      if (!mounted) return;
      setState(() { _loading = false; if (!silent) _error = ApiService.getErrorMessage(e); });
    }
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
                  'Walk-in (POS) sales are paid at the counter and are not shown in the wallet.',
                  style: GoogleFonts.poppins(fontSize: 12, color: AppColors.secondary),
                ),
              ),
            ],
          ),
        ),
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
          for (final t in wallet.transactions) _transactionTile(t),
      ],
    );
  }

  Widget _transactionTile(WalletTransaction t) {
    final isRelease = t.type == 'escrow_release';
    final color = t.isDebit ? AppColors.stockRed : (isRelease ? AppColors.stockGreen : AppColors.secondary);
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
            child: Icon(isRelease ? Icons.lock_open : Icons.swap_horiz, color: color, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(isRelease ? 'Escrow released' : t.label,
                    style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w600)),
                if (t.description != null)
                  Text(t.description!, style: GoogleFonts.poppins(fontSize: 12, color: AppColors.textSecondary)),
                if (t.createdAt != null)
                  Text(DateFormat('MMM dd, hh:mm a').format(t.createdAt!),
                      style: GoogleFonts.poppins(fontSize: 11, color: AppColors.textLight)),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('${t.isDebit ? '−' : '+'} Rs. ${_money.format(t.amount)}',
                  style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w700, color: color)),
              Text('Bal: Rs. ${_money.format(t.balanceAfter)}',
                  style: GoogleFonts.poppins(fontSize: 11, color: AppColors.textLight)),
            ],
          ),
        ],
      ),
    );
  }
}
