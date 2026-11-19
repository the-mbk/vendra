// ══════════════════════════════════════════════════════════════
// Vendra App - Ledger tab
// Stock: every stock movement in plain language, grouped by day:
//   "Stock added +5", "Held for online order #12 (2 held, still on the
//   shelf)", "Back on sale", "Sold online −2", "Sold at the counter −1",
//   each with what is left afterwards ("Shelf 11 · Online 9").
//   A hold does not take units off the shelf; only the sale does, so a
//   delivered order is never counted twice. Today's totals sit on top;
//   chips filter Sold / Added / Online holds.
// Money (owner only): the shared MoneyLedgerView (balance, money on
//   hold, payouts with the commission breakdown, withdrawals).
// Refreshes itself whenever a `stock:vendor` event says stock moved.
// ══════════════════════════════════════════════════════════════

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:vendra_vendor/vendra_core.dart';
import '../models/ledger_lines.dart';
import '../widgets/money_ledger.dart';
import '../widgets/tab_header.dart';
import '../../../core/models/ledger_entry_model.dart';

class StockLedgerScreen extends StatefulWidget {
  /// Show the Stock / Money switch (the store owner); staff see stock only
  final bool showMoney;
  const StockLedgerScreen({super.key, this.showMoney = false});

  @override
  State<StockLedgerScreen> createState() => _StockLedgerScreenState();
}

class _StockLedgerScreenState extends State<StockLedgerScreen> {
  bool _money = false;

  @override
  Widget build(BuildContext context) {
    final money = widget.showMoney && _money;
    return SafeArea(
      bottom: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TabHeader(
            icon: money ? Icons.account_balance_wallet : Icons.inventory_2,
            title: 'Ledger',
            subtitle: money ? 'What you were paid, and what is still on hold' : 'Every unit in and out of your shop',
          ),
          if (widget.showMoney)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(value: false, icon: Icon(Icons.inventory_2_outlined), label: Text('Stock')),
                  ButtonSegment(value: true, icon: Icon(Icons.payments_outlined), label: Text('Money')),
                ],
                selected: {_money},
                showSelectedIcon: false,
                onSelectionChanged: (s) => setState(() => _money = s.first),
              ),
            ),
          Expanded(child: money ? const MoneyLedgerView() : const _StockLedgerView()),
        ],
      ),
    );
  }
}

class _StockLedgerView extends StatefulWidget {
  const _StockLedgerView();

  @override
  State<_StockLedgerView> createState() => _StockLedgerViewState();
}

class _StockLedgerViewState extends State<_StockLedgerView> {
  List<LedgerEntryModel> _entries = [];
  bool _isLoading = true;
  String? _error;
  StockFilter _filter = StockFilter.all;
  StreamSubscription<VendorStockEvent>? _stockSub;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _fetchLedger();
    // A sale / reservation / edit just moved stock → new ledger rows
    _stockSub = RealtimeService().vendorStock.listen((_) {
      _debounce?.cancel();
      _debounce = Timer(const Duration(milliseconds: 600), () => _fetchLedger(silent: true));
    });
  }

  @override
  void dispose() {
    _stockSub?.cancel();
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _fetchLedger({bool silent = false}) async {
    if (!silent) setState(() { _isLoading = true; _error = null; });
    try {
      final response = await ApiService().get(ApiConfig.inventoryLedger);
      if (response.data['success'] == true) {
        _entries = (response.data['data'] as List)
            .map((j) => LedgerEntryModel.fromJson(Map<String, dynamic>.from(j)))
            .toList();
        _error = null;
      } else if (!silent) {
        _error = response.data['message'];
      }
    } catch (e) {
      if (!silent) _error = ApiService.getErrorMessage(e);
    }
    if (mounted) setState(() { _isLoading = false; });
  }

  static DateTime? _when(LedgerEntryModel e) => e.createdAt != null ? DateTime.tryParse(e.createdAt!)?.toLocal() : null;

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const Center(child: CircularProgressIndicator(color: AppColors.primary));
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
              OutlinedButton(onPressed: _fetchLedger, child: const Text('Retry')),
            ],
          ),
        ),
      );
    }

    final shown = _entries.where((e) => describeStockEntry(e).matches(_filter)).toList();
    final groups = groupByLedgerDay(shown, _when);

    return RefreshIndicator(
      onRefresh: _fetchLedger,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          _TodayStrip(summary: summarizeStockToday(_entries)),
          const SizedBox(height: 10),
          const _Legend(),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final f in StockFilter.values)
                ChoiceChip(label: Text(f.label), selected: _filter == f, onSelected: (_) => setState(() => _filter = f)),
            ],
          ),
          if (shown.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 40),
              child: Column(
                children: [
                  Icon(Icons.history, size: 56, color: AppColors.textLight),
                  const SizedBox(height: 12),
                  Text(
                    _entries.isEmpty
                        ? 'No stock movements yet. Adding stock and every sale will show up here.'
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
              LedgerDayCard(children: [for (final e in rows) _StockRow(entry: e, at: _when(e))]),
            ],
        ],
      ),
    );
  }
}

/// Today: units sold (online / counter) and added
class _TodayStrip extends StatelessWidget {
  final StockDaySummary summary;
  const _TodayStrip({required this.summary});

  @override
  Widget build(BuildContext context) {
    Widget cell(String value, String label, Color color) => Expanded(
          child: Column(
            children: [
              Text(value, style: GoogleFonts.poppins(fontSize: 20, fontWeight: FontWeight.w700, color: color)),
              Text(label,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.poppins(fontSize: 12, color: AppColors.textSecondary)),
            ],
          ),
        );
    Widget rule() => Container(width: 1, height: 36, color: AppColors.hairline);

    return Container(
      padding: const EdgeInsets.fromLTRB(8, 12, 8, 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.hairline),
      ),
      child: Column(
        children: [
          Text('TODAY',
              style: GoogleFonts.poppins(
                  fontSize: 11.5, fontWeight: FontWeight.w700, letterSpacing: 0.8, color: AppColors.textSecondary)),
          const SizedBox(height: 6),
          Row(
            children: [
              cell('${summary.soldOnline}', 'Sold online', AppColors.secondary),
              rule(),
              cell('${summary.soldCounter}', 'Sold at counter', AppColors.primary),
              rule(),
              cell('${summary.added}', 'Units added', AppColors.success),
            ],
          ),
        ],
      ),
    );
  }
}

/// What "Shelf" and "Online" mean on each row
class _Legend extends StatelessWidget {
  const _Legend();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.secondary.withValues(alpha: AppColors.isDark ? 0.14 : 0.06),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, size: 18, color: AppColors.secondary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Shelf: units physically in your shop.  Online: units customers can still buy in the app. '
              'Units held for an online order stay on your shelf until the rider collects them.',
              style: GoogleFonts.poppins(fontSize: 12.5, height: 1.4, color: AppColors.textPrimary),
            ),
          ),
        ],
      ),
    );
  }
}

class _StockRow extends StatelessWidget {
  final LedgerEntryModel entry;
  final DateTime? at;
  const _StockRow({required this.entry, required this.at});

  @override
  Widget build(BuildContext context) {
    final move = describeStockEntry(entry);
    final amountColor = !move.movesShelf
        ? move.color
        : entry.quantityChange >= 0
            ? AppColors.success
            : AppColors.error;
    final after = [
      if (entry.privateStockAfter != null) 'Shelf ${entry.privateStockAfter}',
      if (entry.publicStockAfter != null) 'Online ${entry.publicStockAfter}',
    ].join(' · ');

    return Padding(
      padding: const EdgeInsets.all(14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: move.color.withValues(alpha: AppColors.isDark ? 0.20 : 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(move.icon, color: move.color, size: 21),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(move.title,
                    style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                Text(entry.productName ?? 'Product #${entry.productId}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w500, color: AppColors.textPrimary)),
                if (move.detail.isNotEmpty)
                  Text(move.detail, style: GoogleFonts.poppins(fontSize: 12.5, height: 1.35, color: AppColors.textSecondary)),
                if (at != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(DateFormat('h:mm a').format(at!),
                        style: GoogleFonts.poppins(fontSize: 12, color: AppColors.textSecondary)),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(move.amountText,
                  style: GoogleFonts.poppins(
                      fontSize: move.movesShelf ? 16 : 13.5, fontWeight: FontWeight.w700, color: amountColor)),
              if (after.isNotEmpty)
                Text(after, style: GoogleFonts.poppins(fontSize: 11.5, color: AppColors.textSecondary)),
            ],
          ),
        ],
      ),
    );
  }
}
