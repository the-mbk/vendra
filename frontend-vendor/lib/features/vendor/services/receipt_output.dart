// ══════════════════════════════════════════════════════════════
// Vendra Vendor App - Sends a receipt PDF to the printer / share sheet
// and picks how, per platform:
//   web      the browser itself (receipt_browser_web.dart): a hidden
//            iframe's print(), else a new tab, else a download. Share
//            downloads <receiptNumber>.pdf. Never the printing plugin's
//            platform channel, which only exists once the plugin's web
//            registrant has run.
//   mobile   the printing plugin (Android print service / AirPrint).
//            When the plugin or a print service is missing
//            (MissingPluginException / PlatformException) the PDF goes
//            to the share sheet instead, with a friendly note.
// ══════════════════════════════════════════════════════════════

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';

import 'receipt_browser_stub.dart' if (dart.library.js_interop) 'receipt_browser_web.dart' as browser;
import 'receipt_outcome.dart';

export 'receipt_outcome.dart';

/// One way of printing / sharing a PDF
abstract class PdfOutputDriver {
  Future<ReceiptOutcome> print(Uint8List bytes, {required String name, required PdfPageFormat format});
  Future<ReceiptOutcome> share(Uint8List bytes, {required String filename});
}

/// Web: the browser's own print dialog / downloads
class BrowserPdfDriver implements PdfOutputDriver {
  const BrowserPdfDriver();

  @override
  Future<ReceiptOutcome> print(Uint8List bytes, {required String name, required PdfPageFormat format}) =>
      browser.printPdfInBrowser(bytes, name: name);

  @override
  Future<ReceiptOutcome> share(Uint8List bytes, {required String filename}) =>
      browser.downloadPdfInBrowser(bytes, filename: filename);
}

/// Android / iOS: the printing plugin
class PrintingPluginDriver implements PdfOutputDriver {
  const PrintingPluginDriver();

  @override
  Future<ReceiptOutcome> print(Uint8List bytes, {required String name, required PdfPageFormat format}) async {
    final printed = await Printing.layoutPdf(onLayout: (_) async => bytes, name: name, format: format);
    return printed ? ReceiptOutcome.printDialog : ReceiptOutcome.cancelled;
  }

  @override
  Future<ReceiptOutcome> share(Uint8List bytes, {required String filename}) async {
    await Printing.sharePdf(bytes: bytes, filename: filename);
    return ReceiptOutcome.shared;
  }
}

class ReceiptOutput {
  final bool isWeb;
  final PdfOutputDriver browserDriver;
  final PdfOutputDriver pluginDriver;

  ReceiptOutput({bool? isWeb, PdfOutputDriver? browserDriver, PdfOutputDriver? pluginDriver})
      : isWeb = isWeb ?? kIsWeb,
        browserDriver = browserDriver ?? const BrowserPdfDriver(),
        pluginDriver = pluginDriver ?? const PrintingPluginDriver();

  /// Used by the receipt's buttons; tests swap in fakes
  static ReceiptOutput instance = ReceiptOutput();

  static const unavailableMessage =
      "Printing and sharing aren't available on this device. Try the Vendra web app on a computer.";

  /// The plugin isn't built into this app, or the device has no print / share service
  static bool isPlatformUnavailable(Object error) => error is MissingPluginException || error is PlatformException;

  Future<ReceiptOutcome> print(Uint8List bytes, {required String name, PdfPageFormat format = PdfPageFormat.roll80}) async {
    final filename = '$name.pdf';
    if (isWeb) {
      try {
        return await browserDriver.print(bytes, name: name, format: format);
      } catch (e) {
        debugPrint('Receipt print in the browser failed: $e');
        return _browserDownload(bytes, filename);
      }
    }
    try {
      return await pluginDriver.print(bytes, name: name, format: format);
    } catch (e) {
      if (!isPlatformUnavailable(e)) {
        debugPrint('Receipt print failed: $e');
        throw const ReceiptOutputException("Couldn't print the receipt. Please try again.");
      }
      debugPrint('No print service ($e) - sharing the receipt instead');
      try {
        await pluginDriver.share(bytes, filename: filename);
        return ReceiptOutcome.sharedInsteadOfPrint;
      } catch (e) {
        debugPrint('Receipt share failed: $e');
        throw ReceiptOutputException(
            isPlatformUnavailable(e) ? unavailableMessage : "Couldn't print or share the receipt. Please try again.");
      }
    }
  }

  Future<ReceiptOutcome> share(Uint8List bytes, {required String filename}) async {
    if (isWeb) return _browserDownload(bytes, filename);
    try {
      return await pluginDriver.share(bytes, filename: filename);
    } catch (e) {
      debugPrint('Receipt share failed: $e');
      throw ReceiptOutputException(
          isPlatformUnavailable(e) ? unavailableMessage : "Couldn't share the receipt. Please try again.");
    }
  }

  Future<ReceiptOutcome> _browserDownload(Uint8List bytes, String filename) async {
    try {
      return await browserDriver.share(bytes, filename: filename);
    } catch (e) {
      debugPrint('Receipt download failed: $e');
      throw const ReceiptOutputException("Your browser blocked the receipt PDF. Allow pop-ups and downloads for this site, then try again.");
    }
  }
}

/// Note shown after Print / Share, or null when the dialog / sheet speaks for itself
String? receiptOutcomeMessage(ReceiptOutcome outcome, {required bool printing, required String filename}) {
  switch (outcome) {
    case ReceiptOutcome.printDialog:
    case ReceiptOutcome.cancelled:
    case ReceiptOutcome.shared:
      return null;
    case ReceiptOutcome.openedInTab:
      return 'The receipt opened in a new tab. Print it from there.';
    case ReceiptOutcome.downloaded:
      return printing
          ? "Your browser can't print here, so $filename was downloaded. Open it to print."
          : 'Saved $filename to your downloads.';
    case ReceiptOutcome.sharedInsteadOfPrint:
      return 'No printer service on this device, so the receipt was shared as a PDF instead.';
  }
}
