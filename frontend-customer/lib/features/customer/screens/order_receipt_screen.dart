// ══════════════════════════════════════════════════════════════
// Vendra Customer App - Order receipt
// Any order (in progress, delivered or cancelled) as a receipt: the
// store, a PAID / REFUNDED / PART REFUNDED / CANCELLED / UNDER REVIEW
// stamp, order details (dates, fulfilment, address, how it was paid and
// where the money is now), the items and the totals with any refund.
// Download PDF (a download on the web, the share sheet on a phone) and
// Print use the A5 PDF from order_receipt_pdf.dart. Readable in light
// and dark mode: only theme tokens, apart from the navy brand band.
// ══════════════════════════════════════════════════════════════

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:vendra_customer/vendra_core.dart';

import '../models/order_receipt.dart';
import '../services/order_receipt_pdf.dart';
import '../services/receipt_output.dart';

class OrderReceiptScreen extends StatefulWidget {
  final OrderModel order;
  const OrderReceiptScreen({super.key, required this.order});

  static Future<void> open(BuildContext context, OrderModel order) =>
      Navigator.push(context, MaterialPageRoute(builder: (_) => OrderReceiptScreen(order: order)));

  @override
  State<OrderReceiptScreen> createState() => _OrderReceiptScreenState();
}

enum _Busy { none, download, print }

class _OrderReceiptScreenState extends State<OrderReceiptScreen> {
  _Busy _busy = _Busy.none;

  OrderReceipt get _receipt => OrderReceipt(widget.order);

  Future<void> _output({required bool printing}) async {
    if (_busy != _Busy.none) return;
    setState(() => _busy = printing ? _Busy.print : _Busy.download);
    final receipt = _receipt;
    final filename = '${receipt.fileName}.pdf';
    String? message;
    var isError = false;
    try {
      final bytes = await OrderReceiptPdf.build(receipt);
      final outcome = printing
          ? await ReceiptOutput.instance.print(bytes, name: receipt.fileName, format: OrderReceiptPdf.pageFormat)
          : await ReceiptOutput.instance.share(bytes, filename: filename);
      message = receiptOutcomeMessage(outcome, printing: printing, filename: filename);
    } on ReceiptOutputException catch (e) {
      message = e.message;
      isError = true;
    } catch (e) {
      debugPrint('Order receipt PDF failed: $e');
      message = "Couldn't create the receipt PDF. Please try again.";
      isError = true;
    }
    if (!mounted) return;
    setState(() => _busy = _Busy.none);
    if (message != null) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
          content: Text(message),
          backgroundColor: isError ? AppColors.error : null,
          behavior: SnackBarBehavior.floating,
        ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final receipt = _receipt;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: Text('Receipt ${receipt.number}', style: GoogleFonts.poppins(fontWeight: FontWeight.w600))),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: ReceiptCard(receipt: receipt),
          ),
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
          decoration: BoxDecoration(
            color: AppColors.surface,
            border: Border(top: BorderSide(color: AppColors.hairline)),
          ),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _busy == _Busy.none ? () => _output(printing: true) : null,
                  icon: _busy == _Busy.print ? const _Spinner() : const Icon(Icons.print_outlined, size: 18),
                  label: const Text('Print'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.secondary,
                    side: BorderSide(color: AppColors.secondary),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _busy == _Busy.none ? () => _output(printing: false) : null,
                  icon: _busy == _Busy.download
                      ? const _Spinner(color: Colors.white)
                      : const Icon(kIsWeb ? Icons.download_outlined : Icons.ios_share, size: 18),
                  label: const Text(kIsWeb ? 'Download PDF' : 'Save / share PDF'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.secondary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Spinner extends StatelessWidget {
  final Color? color;
  const _Spinner({this.color});

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 16,
        height: 16,
        child: CircularProgressIndicator(strokeWidth: 2, color: color ?? AppColors.secondary),
      );
}

/// The receipt itself (also usable inside other screens)
class ReceiptCard extends StatelessWidget {
  final OrderReceipt receipt;
  const ReceiptCard({super.key, required this.receipt});

  static Color stampColor(ReceiptStamp stamp) => switch (stamp) {
        ReceiptStamp.paid => AppColors.successInk,
        ReceiptStamp.refunded => AppColors.info,
        ReceiptStamp.partlyRefunded || ReceiptStamp.underReview => AppColors.warningInk,
        ReceiptStamp.cancelled => AppColors.error,
      };

  @override
  Widget build(BuildContext context) {
    final order = receipt.order;
    final stampColor = ReceiptCard.stampColor(receipt.stamp);

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _header(),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _caps('SOLD BY'),
                          const SizedBox(height: 2),
                          Text(order.storeName ?? 'Vendra store',
                              style: GoogleFonts.poppins(
                                  fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                          if ((order.storeAddress ?? '').isNotEmpty)
                            Text(order.storeAddress!,
                                style: GoogleFonts.poppins(fontSize: 12, color: AppColors.textSecondary)),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Padding(
                      padding: const EdgeInsets.only(top: 6, right: 4),
                      child: _Stamp(label: receipt.stamp.label, color: stampColor),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                _details(),
                const SizedBox(height: 18),
                _caps('ITEMS'),
                const SizedBox(height: 4),
                for (final item in order.items) _itemRow(item),
                Divider(height: 20, color: AppColors.hairline),
                _total('Subtotal', formatRupees(order.subtotal)),
                _total(order.isDelivery ? 'Delivery fee' : 'Self pickup', receipt.deliveryFeeText),
                Divider(height: 20, color: AppColors.hairline),
                _total('Total charged', formatRupees(receipt.total), strong: true),
                if (receipt.refunded > 0) ...[
                  _total(receipt.refundLabel, '− ${formatRupees(receipt.refunded)}', color: stampColor),
                  Divider(height: 20, color: AppColors.hairline),
                  _total('You paid', formatRupees(receipt.netPaid), strong: true),
                ],
                const SizedBox(height: 16),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.verified_user_outlined, size: 16, color: AppColors.textSecondary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(receipt.footnote,
                          style: GoogleFonts.poppins(fontSize: 12, height: 1.4, color: AppColors.textSecondary)),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _header() {
    return Container(
      color: AppColors.navy,
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('Vendra',
                          style: GoogleFonts.poppins(fontSize: 22, fontWeight: FontWeight.w700, color: Colors.white)),
                      const SizedBox(width: 4),
                      Container(
                        width: 7,
                        height: 7,
                        decoration: const BoxDecoration(color: AppColors.primary, shape: BoxShape.circle),
                      ),
                    ],
                  ),
                ),
                Text('Order receipt', style: GoogleFonts.poppins(fontSize: 12, color: Colors.white70)),
              ],
            ),
          ),
          const SizedBox(width: 12),
          // The date is in the details below; the number stays readable on a narrow phone
          Text(receipt.number,
              style: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w700, color: Colors.white)),
        ],
      ),
    );
  }

  Widget _caps(String text) => Text(text,
      style: GoogleFonts.poppins(
          fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 0.8, color: AppColors.textSecondary));

  Widget _details() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: AppColors.surfaceMuted, borderRadius: BorderRadius.circular(12)),
      child: Column(
        children: [
          for (final d in receipt.details)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 104,
                    child: Text(d.label, style: GoogleFonts.poppins(fontSize: 12, color: AppColors.textSecondary)),
                  ),
                  Expanded(
                    child: Text(d.value,
                        style: GoogleFonts.poppins(
                            fontSize: 13, fontWeight: FontWeight.w500, color: AppColors.textPrimary)),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _itemRow(OrderItemModel item) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.productName ?? 'Item',
                    style:
                        GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w500, color: AppColors.textPrimary)),
                Text(OrderReceipt.unitLine(item),
                    style: GoogleFonts.poppins(fontSize: 12, color: AppColors.textSecondary)),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Text(formatRupees(item.total),
              style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
        ],
      ),
    );
  }

  Widget _total(String label, String value, {bool strong = false, Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(
            child: Text(label,
                style: GoogleFonts.poppins(
                    fontSize: strong ? 15 : 13,
                    fontWeight: strong ? FontWeight.w600 : FontWeight.w400,
                    color: strong ? AppColors.textPrimary : AppColors.textSecondary)),
          ),
          Text(value,
              style: GoogleFonts.poppins(
                  fontSize: strong ? 18 : 13,
                  fontWeight: strong ? FontWeight.w700 : FontWeight.w500,
                  color: color ?? (strong ? AppColors.secondary : AppColors.textPrimary))),
        ],
      ),
    );
  }
}

/// A slightly tilted rubber-stamp label
class _Stamp extends StatelessWidget {
  final String label;
  final Color color;
  const _Stamp({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Transform.rotate(
      angle: -0.12,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          border: Border.all(color: color, width: 2),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(label,
            style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w800, letterSpacing: 1.2, color: color)),
      ),
    );
  }
}
