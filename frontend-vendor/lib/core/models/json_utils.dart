// ══════════════════════════════════════════════════════════════
// Vendra App - JSON helpers
// The API returns camelCase for customer/rider/admin routes and snake_case
// rows for vendor routes; Postgres numerics may arrive as strings.
// ══════════════════════════════════════════════════════════════

/// First non-null value among the given keys
dynamic pick(Map<String, dynamic> json, String camel, [String? snake]) =>
    json[camel] ?? (snake != null ? json[snake] : null);

double toDouble(dynamic v, [double fallback = 0]) {
  if (v == null) return fallback;
  if (v is num) return v.toDouble();
  return double.tryParse(v.toString()) ?? fallback;
}

double? toDoubleOrNull(dynamic v) {
  if (v == null) return null;
  if (v is num) return v.toDouble();
  return double.tryParse(v.toString());
}

int toInt(dynamic v, [int fallback = 0]) {
  if (v == null) return fallback;
  if (v is int) return v;
  if (v is num) return v.toInt();
  return int.tryParse(v.toString()) ?? fallback;
}

int? toIntOrNull(dynamic v) {
  if (v == null) return null;
  if (v is int) return v;
  if (v is num) return v.toInt();
  return int.tryParse(v.toString());
}

DateTime? toDate(dynamic v) => v == null ? null : DateTime.tryParse(v.toString())?.toLocal();

/// "Rs. 1,500" (no decimals for whole rupees), "Rs. 1,234.50"
String formatRupees(double v) {
  final whole = v % 1 == 0;
  final fixed = v.toStringAsFixed(whole ? 0 : 2);
  final parts = fixed.split('.');
  final grouped = parts[0].replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',');
  return 'Rs. $grouped${parts.length > 1 ? '.${parts[1]}' : ''}';
}
