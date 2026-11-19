// ══════════════════════════════════════════════════════════════
// Vendra Vendor App - One POS receipt, full screen (reprint / share)
// Opened from today's walk-in sales: GET /api/vendor/pos/sales/:id
// returns the sale's receipt; Print / Share work as after a new sale.
// ══════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:vendra_vendor/vendra_core.dart';

import '../models/pos_receipt.dart';
import '../widgets/receipt_slip.dart';

class ReceiptScreen extends StatefulWidget {
  final int saleId;
  /// Already loaded (e.g. right after the sale); otherwise fetched by [saleId]
  final PosReceipt? receipt;

  const ReceiptScreen({super.key, required this.saleId, this.receipt});

  @override
  State<ReceiptScreen> createState() => _ReceiptScreenState();
}

class _ReceiptScreenState extends State<ReceiptScreen> {
  PosReceipt? _receipt;
  String? _error;

  @override
  void initState() {
    super.initState();
    _receipt = widget.receipt;
    if (_receipt == null) _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final res = await ApiService().get(ApiConfig.posSale(widget.saleId));
      final receipt = PosReceipt.fromJson(Map<String, dynamic>.from(res.data['data'] as Map));
      if (mounted) setState(() => _receipt = receipt);
    } catch (e) {
      if (mounted) setState(() => _error = ApiService.getErrorMessage(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final receipt = _receipt;
    return Scaffold(
      backgroundColor: AppColors.surfaceMuted,
      appBar: AppBar(
        title: Text(receipt?.receiptNumber ?? 'Receipt', style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
      ),
      body: receipt == null
          ? Center(
              child: _error == null
                  ? const CircularProgressIndicator(color: AppColors.primary)
                  : Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(_error!, textAlign: TextAlign.center, style: GoogleFonts.poppins(color: AppColors.textSecondary)),
                          const SizedBox(height: 12),
                          OutlinedButton(onPressed: _load, child: const Text('Retry')),
                        ],
                      ),
                    ),
            )
          : SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
              child: ReceiptSlip(receipt: receipt),
            ),
      bottomNavigationBar: receipt == null
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: ReceiptActions(receipt: receipt),
              ),
            ),
    );
  }
}
