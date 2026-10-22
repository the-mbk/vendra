// ══════════════════════════════════════════════════════════════
// Vendra App - Card helpers (pure Dart, no Flutter)
// Formatting, brand detection and validation for the card entry sheet.
// Card numbers only ever live in the text field and are sent straight
// to the payment gateway — never logged, stored or sent to the Vendra API.
// ══════════════════════════════════════════════════════════════

class CardUtils {
  CardUtils._();

  static const int maxDigits = 19;

  /// Keeps only 0-9
  static String digitsOnly(String input) => input.replaceAll(RegExp(r'[^0-9]'), '');

  /// "4242424242424242" → "4242 4242 4242 4242" (groups of 4, max 19 digits)
  static String formatNumber(String input) {
    final digits = digitsOnly(input);
    final capped = digits.length > maxDigits ? digits.substring(0, maxDigits) : digits;
    final buf = StringBuffer();
    for (var i = 0; i < capped.length; i++) {
      if (i > 0 && i % 4 == 0) buf.write(' ');
      buf.write(capped[i]);
    }
    return buf.toString();
  }

  /// Card network from the leading digits: visa | mastercard | amex | unknown
  static String detectBrand(String input) {
    final d = digitsOnly(input);
    if (d.isEmpty) return 'unknown';
    if (d.startsWith('4')) return 'visa';
    if (d.length >= 2) {
      final two = int.parse(d.substring(0, 2));
      if (two >= 51 && two <= 55) return 'mastercard';
      if (two == 34 || two == 37) return 'amex';
    }
    if (d.length >= 4) {
      final four = int.parse(d.substring(0, 4));
      if (four >= 2221 && four <= 2720) return 'mastercard';
    }
    return 'unknown';
  }

  /// "visa" → "Visa", "mastercard" → "Mastercard"
  static String brandLabel(String? brand) {
    switch ((brand ?? '').toLowerCase()) {
      case 'visa':
        return 'Visa';
      case 'mastercard':
        return 'Mastercard';
      case 'amex':
        return 'American Express';
      case '':
      case 'unknown':
        return 'Card';
      default:
        return brand![0].toUpperCase() + brand.substring(1);
    }
  }

  /// "Visa •••• 4242"
  static String maskedLabel(String? brand, String? last4) =>
      last4 == null || last4.isEmpty ? brandLabel(brand) : '${brandLabel(brand)} •••• $last4';

  /// Luhn checksum (catches most typos before the gateway is called)
  static bool luhnValid(String input) {
    final d = digitsOnly(input);
    if (d.length < 12) return false;
    var sum = 0;
    var doubleIt = false;
    for (var i = d.length - 1; i >= 0; i--) {
      var n = d.codeUnitAt(i) - 48;
      if (doubleIt) {
        n *= 2;
        if (n > 9) n -= 9;
      }
      sum += n;
      doubleIt = !doubleIt;
    }
    return sum % 10 == 0;
  }

  /// Error text for the number field, or null when it looks valid
  static String? validateNumber(String input) {
    final d = digitsOnly(input);
    if (d.isEmpty) return 'Enter the card number';
    if (d.length < 13) return 'The card number is incomplete';
    if (!luhnValid(d)) return 'Check the card number';
    return null;
  }

  /// "1230" / "12/30" → "12/30" as the user types
  static String formatExpiry(String input) {
    final d = digitsOnly(input);
    final capped = d.length > 4 ? d.substring(0, 4) : d;
    if (capped.length <= 2) return capped;
    return '${capped.substring(0, 2)}/${capped.substring(2)}';
  }

  /// Parses "MM/YY" → (month, four-digit year), or null if it isn't a date
  static ({int month, int year})? parseExpiry(String input) {
    final d = digitsOnly(input);
    if (d.length != 4) return null;
    final month = int.parse(d.substring(0, 2));
    final year = 2000 + int.parse(d.substring(2));
    if (month < 1 || month > 12) return null;
    return (month: month, year: year);
  }

  /// Error text for "MM/YY", or null when it is a valid, unexpired date
  static String? validateExpiry(String input, {DateTime? now}) {
    if (digitsOnly(input).isEmpty) return 'Enter the expiry date';
    final exp = parseExpiry(input);
    if (exp == null) return 'Use MM/YY';
    final today = now ?? DateTime.now();
    // A card is valid through the last day of its expiry month
    if (exp.year < today.year || (exp.year == today.year && exp.month < today.month)) {
      return 'This card has expired';
    }
    return null;
  }

  /// Error text for the security code (3 digits, 4 for Amex)
  static String? validateCvc(String input, {String brand = 'unknown'}) {
    final d = digitsOnly(input);
    final needed = brand == 'amex' ? 4 : 3;
    if (d.isEmpty) return 'Enter the CVC';
    if (d.length < needed) return 'The CVC is incomplete';
    return null;
  }
}
