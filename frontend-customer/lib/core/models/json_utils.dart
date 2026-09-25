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
