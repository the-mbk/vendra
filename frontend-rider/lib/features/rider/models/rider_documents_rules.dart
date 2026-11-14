// ══════════════════════════════════════════════════════════════
// Vendra Rider App - Rider document rules
// CNIC, driving licence and vehicle registration, checked the same way
// the server does (backend services/riderDocuments.js) so most mistakes
// are caught before sending. A bicycle needs neither licence nor plate.
// ══════════════════════════════════════════════════════════════

import 'package:flutter/services.dart';

/// Vehicle types offered at sign-up: (value, label). The server also
/// accepts the older `motorbike`.
const riderVehicleTypes = [
  ('motorcycle', 'Motorcycle'),
  ('scooter', 'Scooter'),
  ('bicycle', 'Bicycle'),
  ('car', 'Car'),
];

/// Licence and registration are only asked for motorised vehicles
bool vehicleNeedsLicence(String? vehicleType) => vehicleType != 'bicycle';

/// Digits only, at most 13
String cnicDigits(String value) {
  final digits = value.replaceAll(RegExp(r'\D'), '');
  return digits.length > 13 ? digits.substring(0, 13) : digits;
}

/// Any layout → 12345-1234567-1 (dashes appear as the digits are typed)
String formatCnic(String value) {
  final d = cnicDigits(value);
  if (d.length <= 5) return d;
  if (d.length <= 12) return '${d.substring(0, 5)}-${d.substring(5)}';
  return '${d.substring(0, 5)}-${d.substring(5, 12)}-${d.substring(12)}';
}

String? validateCnic(String? value) {
  final d = cnicDigits(value ?? '');
  if (d.isEmpty) return 'CNIC is required';
  if (d.length != 13) return 'CNIC must have 13 digits (12345-1234567-1)';
  return null;
}

/// Upper-case, single spaces (how the server stores it)
String normalizeDocumentCode(String value) => value.trim().toUpperCase().replaceAll(RegExp(r'\s+'), ' ');

String? _validateCode(String? value, String label, int min, int max) {
  final s = normalizeDocumentCode(value ?? '');
  if (s.isEmpty) return '$label is required';
  if (s.length < min || s.length > max || !RegExp(r'^[A-Z0-9 /-]+$').hasMatch(s)) {
    return '$label must be $min–$max letters, digits or dashes';
  }
  return null;
}

String? validateLicenceNumber(String? value) => _validateCode(value, 'Licence number', 5, 30);
String? validateVehicleNumber(String? value) => _validateCode(value, 'Registration number', 3, 20);

/// Keeps the CNIC field as 12345-1234567-1 while typing or pasting
class CnicInputFormatter extends TextInputFormatter {
  const CnicInputFormatter();

  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    // Deleting a dash deletes the digit before it, otherwise backspace would get stuck
    var raw = newValue.text;
    final deletedDash = oldValue.text.length - raw.length == 1 &&
        newValue.selection.baseOffset >= 0 &&
        newValue.selection.baseOffset < oldValue.text.length &&
        oldValue.text[newValue.selection.baseOffset] == '-';
    if (deletedDash && newValue.selection.baseOffset > 0) {
      final at = newValue.selection.baseOffset - 1;
      raw = raw.substring(0, at) + raw.substring(at + 1);
    }
    // Keep the caret after the same number of digits
    final base = newValue.selection.baseOffset;
    final caret = base < 0 ? raw.length : (deletedDash ? base - 1 : base);
    final digitsBeforeCaret = cnicDigits(raw.substring(0, caret.clamp(0, raw.length))).length;
    final formatted = formatCnic(raw);
    var offset = 0;
    for (var seen = 0; offset < formatted.length && seen < digitsBeforeCaret; offset++) {
      if (formatted[offset] != '-') seen++;
    }
    return TextEditingValue(text: formatted, selection: TextSelection.collapsed(offset: offset));
  }
}
