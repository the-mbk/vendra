// ══════════════════════════════════════════════════════════════
// Vendra Vendor App - Receipt PDF in the browser: placeholder for
// Android / iOS / desktop / tests. The web build imports
// receipt_browser_web.dart instead (see receipt_output.dart), and
// ReceiptOutput only calls these when running on the web.
// ══════════════════════════════════════════════════════════════

import 'dart:typed_data';

import 'receipt_outcome.dart';

Future<ReceiptOutcome> printPdfInBrowser(Uint8List bytes, {required String name}) =>
    throw UnsupportedError('Browser printing is only available on the web');

Future<ReceiptOutcome> downloadPdfInBrowser(Uint8List bytes, {required String filename}) =>
    throw UnsupportedError('Browser downloads are only available on the web');
