// ══════════════════════════════════════════════════════════════
// Vendra Vendor App - scan confirmation
// scanBeep() as soon as the camera reads a barcode, so the cashier or
// packer hears it without looking: a beep in the browser, a click and a
// short vibration on a phone.
// ══════════════════════════════════════════════════════════════

export 'scan_beep_stub.dart' if (dart.library.js_interop) 'scan_beep_web.dart';
