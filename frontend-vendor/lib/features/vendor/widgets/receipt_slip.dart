// ══════════════════════════════════════════════════════════════
// Vendra Vendor App - On-screen POS receipt, styled like an 80 mm
// thermal roll: monospace text, dashed rules, torn edges, and the
// scan-to-pay QR (payment_qr.payload) when the store has a payment
// account. ReceiptActions prints (80 mm PDF) or shares the same slip.
// ══════════════════════════════════════════════════════════════

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:vendra_vendor/vendra_core.dart';

import '../models/pos_receipt.dart';
import '../services/receipt_output.dart';
import '../services/receipt_pdf.dart';

class ReceiptSlip extends StatelessWidget {
  final PosReceipt receipt;
  const ReceiptSlip({super.key, required this.receipt});

  /// ~80 mm roll at phone density
  static const double paperWidth = 300;

  TextStyle _mono({double size = 12, FontWeight weight = FontWeight.w400, Color color = const Color(0xFF222222)}) =>
      GoogleFonts.robotoMono(fontSize: size, fontWeight: weight, color: color, height: 1.35);

  @override
  Widget build(BuildContext context) {
    final r = receipt;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: paperWidth),
        child: DecoratedBox(
          decoration: BoxDecoration(
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.12), blurRadius: 10, offset: const Offset(0, 3))],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const _TornEdge(top: true),
              Container(
                color: Colors.white,
                padding: const EdgeInsets.fromLTRB(16, 6, 16, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(r.storeName.toUpperCase(),
                        textAlign: TextAlign.center, style: _mono(size: 15, weight: FontWeight.w700)),
                    if (r.storeAddress != null) Text(r.storeAddress!, textAlign: TextAlign.center, style: _mono(size: 11)),
                    if (r.storePhone != null) Text('Tel: ${r.storePhone}', textAlign: TextAlign.center, style: _mono(size: 11)),
                    if (r.header != null) ...[
                      const SizedBox(height: 4),
                      Text(r.header!, textAlign: TextAlign.center, style: _mono(size: 11, weight: FontWeight.w600)),
                    ],
                    const _DashedRule(),
                    _kv('Receipt', r.receiptNumber),
                    _kv('Date', ReceiptFormat.dateTime(r.createdAt)),
                    if (r.cashier != null) _kv('Cashier', r.cashier!),
                    const _DashedRule(),
                    for (final line in r.items) ...[
                      Text(line.name, style: _mono(weight: FontWeight.w600)),
                      Row(
                        children: [
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.only(left: 12),
                              child: Text(ReceiptFormat.qtyLine(line), style: _mono(size: 11, color: Colors.black54)),
                            ),
                          ),
                          Text(ReceiptFormat.money(line.total), style: _mono()),
                        ],
                      ),
                      const SizedBox(height: 4),
                    ],
                    const _DashedRule(),
                    Row(
                      children: [
                        Expanded(child: Text('TOTAL', style: _mono(size: 14, weight: FontWeight.w700))),
                        Flexible(
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerRight,
                            child: Text(ReceiptFormat.money(r.total), style: _mono(size: 15, weight: FontWeight.w700)),
                          ),
                        ),
                      ],
                    ),
                    Text(ReceiptFormat.itemCount(r), style: _mono(size: 11, color: Colors.black54)),
                    if (r.paymentQr != null) ...[
                      const _DashedRule(),
                      Text('SCAN TO PAY', textAlign: TextAlign.center, style: _mono(weight: FontWeight.w700)),
                      const SizedBox(height: 6),
                      Center(
                        child: QrImageView(
                          data: r.paymentQr!.payload,
                          size: 150,
                          padding: EdgeInsets.zero,
                          backgroundColor: Colors.white,
                          semanticsLabel: 'Scan-to-pay QR code',
                        ),
                      ),
                      const SizedBox(height: 6),
                      if (r.paymentQr!.title.isNotEmpty)
                        Text(r.paymentQr!.title, textAlign: TextAlign.center, style: _mono(size: 11, weight: FontWeight.w600)),
                      Text(r.paymentQr!.account, textAlign: TextAlign.center, style: _mono(size: 11)),
                    ],
                    const _DashedRule(),
                    Text(r.footer ?? 'Thank you for shopping with us!',
                        textAlign: TextAlign.center, style: _mono(size: 11)),
                    const SizedBox(height: 4),
                    Text('Powered by Vendra', textAlign: TextAlign.center, style: _mono(size: 9, color: Colors.black38)),
                  ],
                ),
              ),
              const _TornEdge(top: false),
            ],
          ),
        ),
      ),
    );
  }

  Widget _kv(String key, String value) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 72, child: Text(key, style: _mono(size: 11, color: Colors.black54))),
          Expanded(child: Text(value, textAlign: TextAlign.right, style: _mono(size: 11))),
        ],
      );
}

/// Print (an 80 mm PDF to the print dialog) and Share (the PDF; a download on the web).
/// Problems show as a short, friendly snackbar - never the raw platform error.
class ReceiptActions extends StatefulWidget {
  final PosReceipt receipt;
  const ReceiptActions({super.key, required this.receipt});

  @override
  State<ReceiptActions> createState() => _ReceiptActionsState();
}

class _ReceiptActionsState extends State<ReceiptActions> {
  bool _busy = false;

  Future<void> _run(Future<ReceiptOutcome> Function(PosReceipt) action, {required bool printing}) async {
    if (_busy) return;
    setState(() => _busy = true);
    String? message;
    var isError = false;
    try {
      final outcome = await action(widget.receipt);
      message = receiptOutcomeMessage(outcome, printing: printing, filename: '${widget.receipt.receiptNumber}.pdf');
    } on ReceiptOutputException catch (e) {
      message = e.message;
      isError = true;
    } catch (e) {
      debugPrint('Receipt ${printing ? 'print' : 'share'} failed: $e');
      message = printing ? "Couldn't print the receipt. Please try again." : "Couldn't share the receipt. Please try again.";
      isError = true;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    if (message != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(message),
        backgroundColor: isError ? AppColors.error : null,
        behavior: SnackBarBehavior.floating,
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: ElevatedButton.icon(
            onPressed: _busy ? null : () => _run(ReceiptPdf.printReceipt, printing: true),
            icon: const Icon(Icons.print_outlined, size: 18),
            label: const Text('Print'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.secondary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 12),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: OutlinedButton.icon(
            onPressed: _busy ? null : () => _run(ReceiptPdf.shareReceipt, printing: false),
            icon: const Icon(kIsWeb ? Icons.download_outlined : Icons.share_outlined, size: 18),
            label: const Text(kIsWeb ? 'Download' : 'Share'),
            style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 12)),
          ),
        ),
      ],
    );
  }
}

class _DashedRule extends StatelessWidget {
  const _DashedRule();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: CustomPaint(size: const Size(double.infinity, 1), painter: _DashPainter()),
    );
  }
}

class _DashPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.black38
      ..strokeWidth = 1;
    for (double x = 0; x < size.width; x += 6) {
      canvas.drawLine(Offset(x, 0), Offset((x + 3).clamp(0, size.width), 0), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Saw-tooth edge where the slip was torn off the roll
class _TornEdge extends StatelessWidget {
  final bool top;
  const _TornEdge({required this.top});

  @override
  Widget build(BuildContext context) =>
      CustomPaint(size: const Size(double.infinity, 8), painter: _TornPainter(top));
}

class _TornPainter extends CustomPainter {
  final bool top;
  _TornPainter(this.top);

  @override
  void paint(Canvas canvas, Size size) {
    const tooth = 10.0;
    final path = Path();
    if (top) {
      path.moveTo(0, size.height);
      for (double x = 0; x < size.width; x += tooth) {
        path.lineTo(x + tooth / 2, 0);
        path.lineTo((x + tooth).clamp(0, size.width), size.height);
      }
    } else {
      path.moveTo(0, 0);
      for (double x = 0; x < size.width; x += tooth) {
        path.lineTo(x + tooth / 2, size.height);
        path.lineTo((x + tooth).clamp(0, size.width), 0);
      }
    }
    path.close();
    canvas.drawPath(path, Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(covariant _TornPainter oldDelegate) => oldDelegate.top != top;
}
