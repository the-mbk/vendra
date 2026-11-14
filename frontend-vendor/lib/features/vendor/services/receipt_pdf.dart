// ══════════════════════════════════════════════════════════════
// Vendra Vendor App - POS receipt as a PDF laid out for an 80 mm roll
// (PdfPageFormat.roll80: the page is as long as the slip). Used by the
// receipt's Print (system print dialog / thermal printer driver) and
// Share (PDF to WhatsApp, email…) buttons. Courier keeps the thermal
// look; text is limited to what the built-in font can draw.
// ══════════════════════════════════════════════════════════════

import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../models/pos_receipt.dart';

class ReceiptPdf {
  static String _t(String s) => ReceiptFormat.pdfSafe(s);

  static Future<Uint8List> build(PosReceipt r) {
    final regular = pw.Font.courier();
    final bold = pw.Font.courierBold();
    pw.TextStyle style({double size = 8, bool isBold = false}) =>
        pw.TextStyle(font: isBold ? bold : regular, fontSize: size, lineSpacing: 1);

    pw.Widget rule() => pw.Padding(
          padding: const pw.EdgeInsets.symmetric(vertical: 4),
          child: pw.Container(
            decoration: const pw.BoxDecoration(
              border: pw.Border(bottom: pw.BorderSide(width: 0.5, style: pw.BorderStyle.dashed)),
            ),
          ),
        );
    pw.Widget center(String text, {double size = 8, bool isBold = false}) =>
        pw.Text(_t(text), textAlign: pw.TextAlign.center, style: style(size: size, isBold: isBold));
    pw.Widget kv(String key, String value, {double size = 8, bool isBold = false}) => pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Expanded(child: pw.Text(_t(key), style: style(size: size, isBold: isBold))),
            pw.Text(_t(value), style: style(size: size, isBold: isBold)),
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
            kv('  ${ReceiptFormat.qtyLine(line)}', ReceiptFormat.money(line.total)),
            pw.SizedBox(height: 2),
          ],
          rule(),
          kv('TOTAL', ReceiptFormat.money(r.total), size: 10, isBold: true),
          pw.Text(_t(ReceiptFormat.itemCount(r)), style: style(size: 7)),
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
          center('Powered by Vendra', size: 6),
        ],
      ),
    ));
    return doc.save();
  }

  /// System print dialog with the 80 mm roll pre-selected
  static Future<void> printReceipt(PosReceipt r) async {
    final bytes = await build(r);
    await Printing.layoutPdf(onLayout: (_) async => bytes, name: r.receiptNumber, format: PdfPageFormat.roll80);
  }

  /// Share sheet (mobile) / download (web) with the PDF
  static Future<void> shareReceipt(PosReceipt r) async {
    final bytes = await build(r);
    await Printing.sharePdf(bytes: bytes, filename: '${r.receiptNumber}.pdf');
  }
}
