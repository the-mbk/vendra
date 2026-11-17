// The web build's receipt printing, run in a real browser:
//   flutter test --platform chrome test/receipt_browser_web_test.dart
// (skipped by a plain `flutter test`, which runs on the Dart VM)
@TestOn('browser')
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:vendra_vendor/features/vendor/models/pos_receipt.dart';
import 'package:vendra_vendor/features/vendor/services/receipt_browser_web.dart';
import 'package:vendra_vendor/features/vendor/services/receipt_output.dart';
import 'package:vendra_vendor/features/vendor/services/receipt_pdf.dart';
import 'package:web/web.dart' as web;

void main() {
  final receipt = PosReceipt.fromJson({
    'receipt_number': 'POS-000042',
    'store': {'name': 'Usman Electronics'},
    'sale': {
      'id': 42,
      'total_amount': 900,
      'created_at': '2026-11-14T10:30:00Z',
      'items': [
        {'product_name': 'USB-C Cable', 'quantity': 2, 'unit_price': 450},
      ],
    },
  });

  test('ReceiptOutput uses the browser on the web', () {
    expect(ReceiptOutput().isWeb, isTrue);
  });

  test('Print hands the 80 mm PDF to the browser without the printing plugin', () async {
    final bytes = await ReceiptPdf.build(receipt);
    final outcome = await printPdfInBrowser(bytes, name: receipt.receiptNumber);
    expect(outcome, isIn([ReceiptOutcome.printDialog, ReceiptOutcome.openedInTab, ReceiptOutcome.downloaded]));
    // ignore: avoid_print
    print('browser print outcome: $outcome · pdfViewerEnabled=${web.window.navigator.pdfViewerEnabled}');
  });

  test('Share downloads <receiptNumber>.pdf', () async {
    final bytes = await ReceiptPdf.build(receipt);
    expect(await downloadPdfInBrowser(bytes, filename: 'POS-000042.pdf'), ReceiptOutcome.downloaded);
  });

  test('ReceiptPdf.printReceipt goes through the browser path end to end', () async {
    final outcome = await ReceiptPdf.printReceipt(receipt);
    expect(outcome, isNot(ReceiptOutcome.sharedInsteadOfPrint));
  });
}
