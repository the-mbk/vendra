// ══════════════════════════════════════════════════════════════
// Vendra Customer App - Order receipt as an A5 PDF
// The same wording as the on-screen receipt (OrderReceipt): navy header
// band, the store, a PAID / REFUNDED / CANCELLED stamp, order details,
// the items, totals with any refund, and a short footnote. Long orders
// flow onto more pages. Download / Print go through receipt_output.dart.
// The built-in Helvetica only draws Latin-1, so text is passed through
// OrderReceipt.pdfSafe.
// ══════════════════════════════════════════════════════════════

import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:vendra_customer/vendra_core.dart';

import '../models/order_receipt.dart';

class OrderReceiptPdf {
  static const pageFormat = PdfPageFormat.a5;

  static const _navy = PdfColor.fromInt(0xFF232774);
  static const _orange = PdfColor.fromInt(0xFFFD761A);
  static const _ink = PdfColor.fromInt(0xFF1A1A2E);
  static const _muted = PdfColor.fromInt(0xFF6C757D);
  static const _hairline = PdfColor.fromInt(0xFFE6E8EB);
  static const _band = PdfColor.fromInt(0xFFF1F3F5);

  static PdfColor stampColor(ReceiptStamp stamp) => switch (stamp) {
        ReceiptStamp.paid => const PdfColor.fromInt(0xFF15803D),
        ReceiptStamp.refunded => const PdfColor.fromInt(0xFF1D4ED8),
        ReceiptStamp.partlyRefunded || ReceiptStamp.underReview => const PdfColor.fromInt(0xFFB45309),
        ReceiptStamp.cancelled => const PdfColor.fromInt(0xFFB91C1C),
      };

  static Future<Uint8List> build(OrderReceipt r, {DateTime? generatedAt}) {
    final order = r.order;
    final regular = pw.Font.helvetica();
    final bold = pw.Font.helveticaBold();
    String t(String s) => OrderReceipt.pdfSafe(s);
    pw.TextStyle style({double size = 9, bool isBold = false, PdfColor color = _ink}) =>
        pw.TextStyle(font: isBold ? bold : regular, fontSize: size, color: color, lineSpacing: 1.5);

    final stampColor = OrderReceiptPdf.stampColor(r.stamp);

    pw.Widget header() => pw.Container(
          padding: const pw.EdgeInsets.fromLTRB(18, 14, 18, 14),
          decoration: const pw.BoxDecoration(
            color: _navy,
            borderRadius: pw.BorderRadius.all(pw.Radius.circular(8)),
          ),
          child: pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Expanded(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Row(children: [
                      pw.Text('Vendra', style: style(size: 20, isBold: true, color: PdfColors.white)),
                      pw.SizedBox(width: 4),
                      pw.Container(
                        width: 6,
                        height: 6,
                        decoration: const pw.BoxDecoration(color: _orange, shape: pw.BoxShape.circle),
                      ),
                    ]),
                    pw.Text('Order receipt', style: style(size: 9, color: PdfColors.grey300)),
                  ],
                ),
              ),
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  pw.Text(t(r.number), style: style(size: 12, isBold: true, color: PdfColors.white)),
                  pw.Text(t(r.formatDate(r.placedAt)), style: style(size: 8, color: PdfColors.grey300)),
                ],
              ),
            ],
          ),
        );

    pw.Widget stamp() => pw.Transform.rotate(
          angle: 0.12,
          child: pw.Container(
            padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: pw.BoxDecoration(
              border: pw.Border.all(color: stampColor, width: 1.6),
              borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
            ),
            child: pw.Text(r.stamp.label, style: style(size: 13, isBold: true, color: stampColor)),
          ),
        );

    pw.Widget seller() => pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Expanded(
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text('SOLD BY', style: style(size: 7, isBold: true, color: _muted)),
                  pw.SizedBox(height: 2),
                  pw.Text(t(order.storeName ?? 'Vendra store'), style: style(size: 12, isBold: true)),
                  if ((order.storeAddress ?? '').isNotEmpty)
                    pw.Text(t(order.storeAddress!), style: style(size: 8.5, color: _muted)),
                ],
              ),
            ),
            pw.SizedBox(width: 12),
            pw.Padding(padding: const pw.EdgeInsets.only(top: 6, right: 4), child: stamp()),
          ],
        );

    pw.Widget details() => pw.Container(
          padding: const pw.EdgeInsets.all(10),
          decoration: const pw.BoxDecoration(
            color: _band,
            borderRadius: pw.BorderRadius.all(pw.Radius.circular(6)),
          ),
          child: pw.Column(
            children: [
              for (final d in r.details)
                pw.Padding(
                  padding: const pw.EdgeInsets.symmetric(vertical: 1.5),
                  child: pw.Row(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.SizedBox(width: 78, child: pw.Text(t(d.label), style: style(size: 8.5, color: _muted))),
                      pw.Expanded(child: pw.Text(t(d.value), style: style(size: 8.5, isBold: true))),
                    ],
                  ),
                ),
            ],
          ),
        );

    pw.Widget itemsTable() => pw.Table(
          columnWidths: const {
            0: pw.FlexColumnWidth(5),
            1: pw.FlexColumnWidth(3),
            2: pw.FlexColumnWidth(2.4),
          },
          border: const pw.TableBorder(horizontalInside: pw.BorderSide(color: _hairline, width: 0.6)),
          children: [
            pw.TableRow(
              decoration: const pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(color: _navy, width: 1))),
              children: [
                for (final (i, h) in const ['ITEM', 'QTY x PRICE', 'AMOUNT'].indexed)
                  pw.Padding(
                    padding: const pw.EdgeInsets.only(bottom: 4),
                    child: pw.Text(h,
                        textAlign: i == 0 ? pw.TextAlign.left : pw.TextAlign.right,
                        style: style(size: 7, isBold: true, color: _navy)),
                  ),
              ],
            ),
            for (final item in order.items)
              pw.TableRow(children: [
                pw.Padding(
                  padding: const pw.EdgeInsets.symmetric(vertical: 5),
                  child: pw.Text(t(item.productName ?? 'Item'), style: style(size: 9)),
                ),
                pw.Padding(
                  padding: const pw.EdgeInsets.symmetric(vertical: 5),
                  child: pw.Text(t(OrderReceipt.unitLine(item)),
                      textAlign: pw.TextAlign.right, style: style(size: 8.5, color: _muted)),
                ),
                pw.Padding(
                  padding: const pw.EdgeInsets.symmetric(vertical: 5),
                  child: pw.Text(t(formatRupees(item.total)),
                      textAlign: pw.TextAlign.right, style: style(size: 9, isBold: true)),
                ),
              ]),
          ],
        );

    pw.Widget totalRow(String label, String value, {bool strong = false, PdfColor? color}) => pw.Padding(
          padding: const pw.EdgeInsets.symmetric(vertical: 2),
          child: pw.Row(children: [
            pw.Expanded(
                child: pw.Text(t(label),
                    style: style(size: strong ? 10 : 9, isBold: strong, color: strong ? _ink : _muted))),
            pw.Text(t(value),
                style: style(size: strong ? 12 : 9, isBold: true, color: color ?? (strong ? _navy : _ink))),
          ]),
        );

    pw.Widget totals() => pw.Align(
          alignment: pw.Alignment.centerRight,
          child: pw.SizedBox(
            width: 210,
            child: pw.Column(children: [
              totalRow('Subtotal', formatRupees(order.subtotal)),
              totalRow(order.isDelivery ? 'Delivery fee' : 'Self pickup', r.deliveryFeeText),
              pw.Divider(color: _hairline, height: 8, thickness: 0.8),
              totalRow('Total charged', formatRupees(r.total), strong: true),
              if (r.refunded > 0) ...[
                totalRow(r.refundLabel, '- ${formatRupees(r.refunded)}', color: stampColor),
                pw.Divider(color: _hairline, height: 8, thickness: 0.8),
                totalRow('You paid', formatRupees(r.netPaid), strong: true),
              ],
            ]),
          ),
        );

    final printed = DateFormat('d MMM yyyy, h:mm a').format(generatedAt ?? DateTime.now());
    final doc = pw.Document(title: 'Vendra receipt ${r.number}', author: 'Vendra');
    doc.addPage(pw.MultiPage(
      pageFormat: pageFormat,
      margin: const pw.EdgeInsets.all(24),
      footer: (context) => pw.Row(children: [
        pw.Expanded(child: pw.Text(t('Generated $printed'), style: style(size: 7, color: _muted))),
        pw.Text('Page ${context.pageNumber} of ${context.pagesCount}', style: style(size: 7, color: _muted)),
      ]),
      build: (context) => [
        header(),
        pw.SizedBox(height: 14),
        seller(),
        pw.SizedBox(height: 12),
        details(),
        pw.SizedBox(height: 14),
        itemsTable(),
        pw.SizedBox(height: 10),
        totals(),
        pw.SizedBox(height: 16),
        pw.Text(t(r.footnote), style: style(size: 8, color: _muted)),
        pw.SizedBox(height: 4),
        pw.Text('Need help with this order? Open it in the Vendra app and tap "Report an issue".',
            style: style(size: 8, color: _muted)),
      ],
    ));
    return doc.save();
  }
}
