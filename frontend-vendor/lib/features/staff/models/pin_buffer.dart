// ══════════════════════════════════════════════════════════════
// Vendra Vendor App - Digits typed on the switch-user PIN pad
// Staff PINs are 4–6 digits: OK is enabled from the 4th digit, and the
// 6th digit submits on its own.
// ══════════════════════════════════════════════════════════════

class PinBuffer {
  static const int minLength = 4;
  static const int maxLength = 6;

  String _digits = '';

  String get value => _digits;
  int get length => _digits.length;
  bool get isEmpty => _digits.isEmpty;
  bool get isFull => _digits.length >= maxLength;
  bool get canSubmit => _digits.length >= minLength;

  /// Adds one digit; returns false when [digit] isn't 0–9 or the PIN is full
  bool add(String digit) {
    if (isFull || !RegExp(r'^\d$').hasMatch(digit)) return false;
    _digits += digit;
    return true;
  }

  void backspace() {
    if (_digits.isNotEmpty) _digits = _digits.substring(0, _digits.length - 1);
  }

  void clear() => _digits = '';
}
