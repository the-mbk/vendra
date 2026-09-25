// ══════════════════════════════════════════════════════════════
// Vendra Vendor App - Disputes Screen (FR08)
// GET /api/disputes/mine — disputes raised on this store's orders,
// with status, outcome, admin note and evidence photos. While a
// dispute is open the order's payment stays frozen in escrow.
// ══════════════════════════════════════════════════════════════

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:vendra_vendor/vendra_core.dart';

class VendorDisputesScreen extends StatefulWidget {
  /// Scroll hint: highlight the dispute on this order (from the orders list)
  final int? highlightOrderId;
  const VendorDisputesScreen({super.key, this.highlightOrderId});

  @override
  State<VendorDisputesScreen> createState() => _VendorDisputesScreenState();
}

class _VendorDisputesScreenState extends State<VendorDisputesScreen> {
  static final _money = NumberFormat('#,##0.##');
  List<DisputeModel> _disputes = [];
  bool _loading = true;
  String? _error;
  StreamSubscription<NotificationModel>? _sub;

  @override
  void initState() {
    super.initState();
    _load();
    _sub = RealtimeService().notifications.listen((n) {
      if (n.type.startsWith('dispute')) _load(silent: true);
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
      final res = await ApiService().get(ApiConfig.myDisputes);
      final list = (res.data['data'] as List<dynamic>)
          .map((d) => DisputeModel.fromJson(Map<String, dynamic>.from(d)))
          .toList();
      if (!mounted) return;
      setState(() { _disputes = list; _loading = false; _error = null; });
    } catch (e) {
      if (!mounted) return;
      setState(() { _loading = false; if (!silent) _error = ApiService.getErrorMessage(e); });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: Text('Disputes', style: GoogleFonts.poppins(fontWeight: FontWeight.w600))),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
          : _error != null
              ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(_error!, textAlign: TextAlign.center)))
              : RefreshIndicator(
                  onRefresh: _load,
                  child: _disputes.isEmpty
                      ? ListView(
                          children: [
                            const SizedBox(height: 120),
                            Icon(Icons.gavel_outlined, size: 64, color: Colors.grey.shade300),
                            const SizedBox(height: 16),
                            Center(
                              child: Text('No disputes on your orders',
                                  style: GoogleFonts.poppins(color: AppColors.textSecondary)),
                            ),
                          ],
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.all(16),
                          itemCount: _disputes.length,
                          itemBuilder: (context, i) => _disputeCard(_disputes[i]),
                        ),
                ),
    );
  }

  Widget _disputeCard(DisputeModel d) {
    final open = d.status == 'open';
    final color = open
        ? AppColors.stockRed
        : (d.resolution == 'refund' ? AppColors.reservedAmber : AppColors.stockGreen);
    final highlighted = widget.highlightOrderId == d.orderId;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: highlighted ? AppColors.primary : color.withValues(alpha: 0.3), width: highlighted ? 2 : 1),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('#ORD-${d.orderId.toString().padLeft(3, '0')} · ${d.issueLabel}',
                    style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w600)),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
                child: Text(open ? 'Open' : 'Resolved',
                    style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w600, color: color)),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Raised by ${d.raisedByName ?? 'someone'}${d.raisedByRole != null ? ' (${d.raisedByRole})' : ''}'
            '${d.createdAt != null ? ' · ${DateFormat('MMM dd, hh:mm a').format(d.createdAt!)}' : ''}',
            style: GoogleFonts.poppins(fontSize: 12, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 8),
          Text(d.description, style: GoogleFonts.poppins(fontSize: 13, color: AppColors.textPrimary)),
          if (d.evidenceUrls.isNotEmpty) ...[
            const SizedBox(height: 10),
            SizedBox(
              height: 72,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: d.evidenceUrls.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (context, i) {
                  final url = ApiConfig.fileUrl(d.evidenceUrls[i]);
                  return GestureDetector(
                    onTap: () => _openImage(url),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.network(
                        url,
                        width: 72,
                        height: 72,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Container(
                          width: 72,
                          height: 72,
                          color: Colors.grey.shade200,
                          child: const Icon(Icons.broken_image_outlined, color: AppColors.textLight),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
          const Divider(height: 20),
          Row(
            children: [
              Icon(open ? Icons.lock_clock : Icons.gavel, size: 16, color: color),
              const SizedBox(width: 6),
              Expanded(
                child: Text(d.outcomeText,
                    style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w600, color: color)),
              ),
              if (d.heldAmount > 0)
                Text('Rs. ${_money.format(d.heldAmount)}',
                    style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w600)),
            ],
          ),
          if (d.adminNote != null && d.adminNote!.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text('Admin note: ${d.adminNote}',
                style: GoogleFonts.poppins(fontSize: 12, color: AppColors.textSecondary, fontStyle: FontStyle.italic)),
          ],
        ],
      ),
    );
  }

  void _openImage(String url) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.black,
        insetPadding: const EdgeInsets.all(16),
        child: Stack(
          children: [
            InteractiveViewer(child: Image.network(url, fit: BoxFit.contain)),
            Positioned(
              top: 4,
              right: 4,
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white),
                onPressed: () => Navigator.pop(ctx),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
