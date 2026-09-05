// ══════════════════════════════════════════════════════════════
// Vendra App - Stock Ledger Screen
// Shows chronological inventory changes
// ══════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../../config/app_theme.dart';
import '../../../core/models/ledger_entry_model.dart';
import '../../../core/services/api_service.dart';
import '../../../config/api_config.dart';

class StockLedgerScreen extends StatefulWidget {
  const StockLedgerScreen({super.key});

  @override
  State<StockLedgerScreen> createState() => _StockLedgerScreenState();
}

class _StockLedgerScreenState extends State<StockLedgerScreen> {
  List<LedgerEntryModel> _entries = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _fetchLedger();
  }

  Future<void> _fetchLedger() async {
    setState(() { _isLoading = true; _error = null; });
    try {
      final response = await ApiService().get(ApiConfig.inventoryLedger);
      if (response.data['success'] == true) {
        _entries = (response.data['data'] as List)
            .map((j) => LedgerEntryModel.fromJson(j))
            .toList();
      } else {
        _error = response.data['message'];
      }
    } catch (e) {
      _error = ApiService.getErrorMessage(e);
    }
    setState(() { _isLoading = false; });
  }

  Color _typeColor(String type) {
    switch (type) {
      case 'stock_in': return AppColors.stockGreen;
      case 'reserve': return AppColors.reservedAmber;
      case 'release': return AppColors.info;
      case 'sale': return AppColors.secondary;
      default: return Colors.grey;
    }
  }

  IconData _typeIcon(String type) {
    switch (type) {
      case 'stock_in': return Icons.add_circle_outline;
      case 'reserve': return Icons.lock_outline;
      case 'release': return Icons.lock_open;
      case 'sale': return Icons.sell_outlined;
      default: return Icons.change_circle_outlined;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
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
                        itemBuilder: (context, index) {
                          final entry = _entries[index];
                          return Container(
                            margin: const EdgeInsets.only(bottom: 10),
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(12),
                              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 6)],
                            ),
                            child: Row(
                              children: [
                                // Type icon
                                Container(
                                  width: 40,
                                  height: 40,
                                  decoration: BoxDecoration(
                                    color: _typeColor(entry.changeType).withOpacity(0.1),
                                    shape: BoxShape.circle,
                                  ),
                                  child: Icon(_typeIcon(entry.changeType), color: _typeColor(entry.changeType), size: 20),
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
                                          style: GoogleFonts.poppins(fontSize: 12, color: _typeColor(entry.changeType), fontWeight: FontWeight.w600)),
                                      if (entry.createdAt != null)
                                        Text(
                                          DateFormat('MMM dd, hh:mm a').format(DateTime.parse(entry.createdAt!)),
                                          style: GoogleFonts.poppins(fontSize: 11, color: AppColors.textLight),
                                        ),
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
                                    if (entry.publicStockAfter != null)
                                      Text('Pub: ${entry.publicStockAfter}',
                                          style: GoogleFonts.poppins(fontSize: 11, color: AppColors.textLight)),
                                  ],
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
        ),
      ],
    );
  }
}
