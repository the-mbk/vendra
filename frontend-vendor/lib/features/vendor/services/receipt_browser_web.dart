// ══════════════════════════════════════════════════════════════
// Vendra Vendor App - Receipt PDF in the browser (web build only)
// Prints without the printing plugin's platform channel: the PDF becomes
// a Blob URL that is loaded into a hidden iframe whose print() opens the
// browser's print dialog (with the 80 mm page size from the PDF).
// When the browser won't print from an iframe (mobile browsers, Safari
// quirks, a blocked frame) the PDF opens in a new tab to print from
// there; when it can't show PDFs at all, or pop-ups are blocked, the
// PDF is downloaded instead. Share downloads <receiptNumber>.pdf.
// ══════════════════════════════════════════════════════════════

import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

import 'receipt_outcome.dart';

const _frameId = 'vendra-receipt-print-frame';

/// Blob URL of the last printed receipt; revoked when the next one is printed
String? _printedUrl;

String _blobUrl(Uint8List bytes) {
  final blob = web.Blob([bytes.toJS].toJS, web.BlobPropertyBag(type: 'application/pdf'));
  return web.URL.createObjectURL(blob);
}

String get _userAgent => web.window.navigator.userAgent;
bool get _isFirefox => _userAgent.contains('Firefox');
bool get _isSafari => _userAgent.contains('Safari') && !_userAgent.contains('Chrome') && !_userAgent.contains('Chromium');

/// Phones and tablets: their browsers don't render PDFs inside an iframe
bool get _isMobileBrowser => RegExp(r'Mobi|Android|iPhone|iPad|iPod').hasMatch(_userAgent);

/// `navigator.pdfViewerEnabled` is false when the browser downloads PDFs instead of showing them
/// (missing on older browsers, which then are assumed to show them)
bool get _canShowPdf {
  final value = (web.window.navigator as JSObject).getProperty<JSAny?>('pdfViewerEnabled'.toJS);
  return value.dartify() != false;
}

void _clickDownload(String url, String filename) {
  final link = web.HTMLAnchorElement()
    ..href = url
    ..download = filename;
  link.style.display = 'none';
  web.document.body?.append(link);
  link.click();
  link.remove();
}

/// The previous print's iframe and Blob URL (kept until now: the dialog may still be using them)
void _cleanUpLastPrint() {
  web.document.getElementById(_frameId)?.remove();
  final last = _printedUrl;
  if (last != null) web.URL.revokeObjectURL(last);
  _printedUrl = null;
}

/// Loads [url] into a hidden iframe and prints it; false if the browser wouldn't
Future<bool> _printInFrame(String url) {
  final completer = Completer<bool>();
  final frame = web.HTMLIFrameElement()
    ..id = _frameId
    ..title = 'Receipt';
  // Firefox only prints a frame that is (technically) on screen; others print a hidden one
  frame.setAttribute(
    'style',
    _isFirefox
        ? 'position:fixed;left:0;top:0;width:1px;height:100px;opacity:0;border:0;margin:0;padding:0;pointer-events:none;'
        : 'position:fixed;right:0;bottom:0;width:0;height:0;border:0;visibility:hidden;',
  );

  void finish(bool printed) {
    if (!completer.isCompleted) completer.complete(printed);
  }

  frame.addEventListener(
    'load',
    ((web.Event _) {
      // Safari needs a moment before its PDF view can print
      Timer(Duration(milliseconds: _isSafari ? 500 : 50), () {
        try {
          final window = frame.contentWindow;
          if (window == null) {
            finish(false);
          } else {
            window.focus();
            window.print();
            finish(true);
          }
        } catch (_) {
          finish(false); // e.g. the browser blocked scripting the PDF frame
        }
      });
    }).toJS,
  );
  frame.src = url;
  web.document.body?.append(frame);

  // Some browsers never fire `load` for a PDF they won't display
  final timeout = Timer(const Duration(seconds: 6), () => finish(false));
  return completer.future.whenComplete(timeout.cancel);
}

/// Prints the PDF: iframe → new tab → download, whichever the browser allows first
Future<ReceiptOutcome> printPdfInBrowser(Uint8List bytes, {required String name}) async {
  _cleanUpLastPrint();
  final url = _blobUrl(bytes);
  _printedUrl = url;
  final filename = '$name.pdf';

  if (!_canShowPdf) {
    _clickDownload(url, filename);
    return ReceiptOutcome.downloaded;
  }
  if (!_isMobileBrowser && await _printInFrame(url)) return ReceiptOutcome.printDialog;

  web.document.getElementById(_frameId)?.remove();
  final tab = web.window.open(url, '_blank');
  if (tab != null) return ReceiptOutcome.openedInTab;
  _clickDownload(url, filename); // pop-up blocked
  return ReceiptOutcome.downloaded;
}

/// Saves the PDF as [filename] in the downloads folder
Future<ReceiptOutcome> downloadPdfInBrowser(Uint8List bytes, {required String filename}) async {
  final url = _blobUrl(bytes);
  _clickDownload(url, filename);
  // The download has started by now; give slow browsers a little longer before freeing it
  Timer(const Duration(minutes: 1), () => web.URL.revokeObjectURL(url));
  return ReceiptOutcome.downloaded;
}
