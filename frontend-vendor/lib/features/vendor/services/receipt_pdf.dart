// ══════════════════════════════════════════════════════════════
// Vendra Vendor App - POS receipt as a PDF laid out for an 80 mm roll
// (PdfPageFormat.roll80: the page is as long as the slip), mirroring the
// on-screen ReceiptSlip line for line. Used by the receipt's Print
// (system / browser print dialog, thermal printer driver) and Share (PDF
// to WhatsApp, email… or a download on the web) buttons; receipt_output
// decides how per platform. Courier keeps the thermal look; text is
// limited to what the built-in font can draw.
// ══════════════════════════════════════════════════════════════

import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../models/pos_receipt.dart';
import 'receipt_output.dart';

class ReceiptPdf {
  static String _t(String s) => ReceiptFormat.pdfSafe(s);
  static const _muted = PdfColors.grey700;

  static Future<Uint8List> build(PosReceipt r) {
    final regular = pw.Font.courier();
    final bold = pw.Font.courierBold();
    pw.TextStyle style({double size = 8, bool isBold = false, PdfColor color = PdfColors.black}) =>
        pw.TextStyle(font: isBold ? bold : regular, fontSize: size, lineSpacing: 1, color: color);

    pw.Widget rule() => pw.Padding(
          padding: const pw.EdgeInsets.symmetric(vertical: 4),
          child: pw.Container(
            decoration: const pw.BoxDecoration(
              border: pw.Border(bottom: pw.BorderSide(width: 0.5, style: pw.BorderStyle.dashed)),
            ),
          ),
        );
    pw.Widget center(String text, {double size = 8, bool isBold = false, PdfColor color = PdfColors.black}) =>
        pw.Text(_t(text), textAlign: pw.TextAlign.center, style: style(size: size, isBold: isBold, color: color));
    // Label column + right-aligned value that wraps, like the on-screen slip
    pw.Widget kv(String key, String value) => pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.SizedBox(width: 19 * PdfPageFormat.mm, child: pw.Text(_t(key), style: style(color: _muted))),
            pw.Expanded(child: pw.Text(_t(value), textAlign: pw.TextAlign.right, style: style())),
          ],
        );

    final doc = pw.Document(title: r.receiptNumber, author: r.storeName, creator: 'Vendra');
    doc.addPage(pw.Page(
      pageFormat: PdfPageFormat.roll80,
      build: (_) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          center(r.storeName.toUpperCase(), size: 11, isBold: true),
          if (r.storeAddress != null) center(r.storeAddress!),
          if (r.storePhone != null) center('Tel: ${r.storePhone}'),
          if (r.header != null) ...[pw.SizedBox(height: 2), center(r.header!, isBold: true)],
          rule(),
          kv('Receipt', r.receiptNumber),
          kv('Date', ReceiptFormat.dateTime(r.createdAt)),
          if (r.cashier != null) kv('Cashier', r.cashier!),
          rule(),
          for (final line in r.items) ...[
            pw.Text(_t(line.name), style: style(isBold: true)),
            pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Expanded(
                  child: pw.Padding(
                    padding: const pw.EdgeInsets.only(left: 3 * PdfPageFormat.mm),
                    child: pw.Text(_t(ReceiptFormat.qtyLine(line)), style: style(size: 7.5, color: _muted)),
                  ),
                ),
                pw.Text(_t(ReceiptFormat.money(line.total)), style: style()),
              ],
            ),
            pw.SizedBox(height: 3),
          ],
          rule(),
          pw.Row(
            children: [
              pw.Expanded(child: pw.Text('TOTAL', style: style(size: 10.5, isBold: true))),
              pw.Text(_t(ReceiptFormat.money(r.total)), style: style(size: 11, isBold: true)),
            ],
          ),
          pw.Text(_t(ReceiptFormat.itemCount(r)), style: style(size: 7.5, color: _muted)),
          if (r.paymentQr != null) ...[
            rule(),
            center('SCAN TO PAY', isBold: true),
            pw.SizedBox(height: 4),
            pw.Center(
              child: pw.BarcodeWidget(
                barcode: pw.Barcode.qrCode(),
                data: r.paymentQr!.payload,
                width: 110,
                height: 110,
              ),
            ),
            pw.SizedBox(height: 4),
            if (r.paymentQr!.title.isNotEmpty) center(r.paymentQr!.title, isBold: true),
            center(r.paymentQr!.account),
          ],
          rule(),
          center(r.footer ?? 'Thank you for shopping with us!'),
          pw.SizedBox(height: 2),
          center('Powered by Vendra', size: 6, color: PdfColors.grey600),
        ],
      ),
    ));
    return doc.save();
  }

  /// Print dialog with the 80 mm roll pre-selected (browser dialog on the web;
  /// the share sheet on a phone without a print service)
  static Future<ReceiptOutcome> printReceipt(PosReceipt r) async {
    final bytes = await build(r);
    return ReceiptOutput.instance.print(bytes, name: r.receiptNumber, format: PdfPageFormat.roll80);
  }

  /// Share sheet (mobile) / download of <receiptNumber>.pdf (web)
  static Future<ReceiptOutcome> shareReceipt(PosReceipt r) async {
    final bytes = await build(r);
    return ReceiptOutput.instance.share(bytes, filename: '${r.receiptNumber}.pdf');
  }
}
