// ══════════════════════════════════════════════════════════════
// Vendra App - Stock Ledger Screen
// Shows chronological inventory changes: stock in, manual adjustments,
// online reservations / releases, online sales and walk-in POS sales.
// Refreshes itself whenever a `stock:vendor` event says stock moved.
// ══════════════════════════════════════════════════════════════

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:vendra_vendor/vendra_core.dart';
import '../../../core/models/ledger_entry_model.dart';

class StockLedgerScreen extends StatefulWidget {
  const StockLedgerScreen({super.key});

  @override
  State<StockLedgerScreen> createState() => _StockLedgerScreenState();
}

class _StockLedgerScreenState extends State<StockLedgerScreen> {
  List<LedgerEntryModel> _entries = [];
  bool _isLoading = true;
  String? _error;
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

  Color _typeColor(String type) {
    switch (type) {
      case 'stock_in': return AppColors.stockGreen;
      case 'adjustment': return Colors.blueGrey;
      case 'reserve': return AppColors.reservedAmber;
      case 'release': return AppColors.info;
      case 'sale': return AppColors.secondary;
      case 'pos_sale': return AppColors.primary;
      default: return Colors.grey;
    }
  }

  IconData _typeIcon(String type) {
    switch (type) {
      case 'stock_in': return Icons.add_circle_outline;
      case 'adjustment': return Icons.tune;
      case 'reserve': return Icons.lock_outline;
      case 'release': return Icons.lock_open;
      case 'sale': return Icons.local_shipping_outlined;
      case 'pos_sale': return Icons.point_of_sale;
      default: return Icons.change_circle_outlined;
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Text('Stock Ledger', style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.w600)),
          ),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
                : _error != null
                    ? Center(child: Text(_error!))
                    : _entries.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.history, size: 64, color: Colors.grey.shade300),
                                const SizedBox(height: 16),
                                Text('No ledger entries yet', style: GoogleFonts.poppins(color: AppColors.textSecondary)),
                              ],
                            ),
                          )
                        : RefreshIndicator(
                            onRefresh: _fetchLedger,
                            child: ListView.builder(
                              padding: const EdgeInsets.all(16),
                              itemCount: _entries.length,
                              itemBuilder: (context, index) => _entryTile(_entries[index]),
                            ),
                          ),
          ),
        ],
      ),
    );
  }

  Widget _entryTile(LedgerEntryModel entry) {
    final color = _typeColor(entry.changeType);
    final created = entry.createdAt != null ? DateTime.tryParse(entry.createdAt!)?.toLocal() : null;
    final subtitle = [
      if (entry.referenceLabel != null) entry.referenceLabel!,
      if (created != null) DateFormat('MMM dd, hh:mm a').format(created),
    ].join(' · ');

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
          // Type icon
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(color: color.withValues(alpha: 0.1), shape: BoxShape.circle),
            child: Icon(_typeIcon(entry.changeType), color: color, size: 20),
          ),
          const SizedBox(width: 12),
          // Details
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(entry.productName ?? 'Product #${entry.productId}',
                    style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w500)),
                const SizedBox(height: 2),
                Text(entry.changeTypeDisplay,
                    style: GoogleFonts.poppins(fontSize: 12, color: color, fontWeight: FontWeight.w600)),
                if (entry.notes != null && entry.notes!.isNotEmpty)
                  Text(entry.notes!, style: GoogleFonts.poppins(fontSize: 11, color: AppColors.textSecondary)),
                if (subtitle.isNotEmpty)
                  Text(subtitle, style: GoogleFonts.poppins(fontSize: 11, color: AppColors.textLight)),
              ],
            ),
          ),
          // Quantity change
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${entry.quantityChange > 0 ? '+' : ''}${entry.quantityChange}',
                style: GoogleFonts.poppins(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: entry.quantityChange > 0 ? AppColors.stockGreen : AppColors.stockRed,
                ),
              ),
              if (entry.privateStockAfter != null)
                Text('Priv: ${entry.privateStockAfter}',
                    style: GoogleFonts.poppins(fontSize: 11, color: AppColors.textLight)),
              if (entry.publicStockAfter != null)
                Text('Pub: ${entry.publicStockAfter}',
                    style: GoogleFonts.poppins(fontSize: 11, color: AppColors.textLight)),
            ],
          ),
        ],
      ),
    );
  }
}
