// ══════════════════════════════════════════════════════════════
// Vendra Customer App - What happened when the receipt's Print / Share
// button was tapped (see receipt_output.dart). Kept in its own file so
// the browser implementation (receipt_browser_web.dart) can return it.
// ══════════════════════════════════════════════════════════════

enum ReceiptOutcome {
  /// The system / browser print dialog opened
  printDialog,

  /// The person closed the print dialog without printing
  cancelled,

  /// Web: the PDF opened in a new tab (the browser blocked printing it in place)
  openedInTab,

  /// Web: the PDF was saved to the downloads folder
  downloaded,

  /// Mobile: the share sheet opened with the PDF
  shared,

  /// Mobile: no print service was available, so the share sheet opened instead
  sharedInsteadOfPrint,
}

/// A print / share failure with a message that can be shown as-is
class ReceiptOutputException implements Exception {
  final String message;
  const ReceiptOutputException(this.message);

  @override
  String toString() => message;
}
