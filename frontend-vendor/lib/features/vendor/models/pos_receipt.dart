// ══════════════════════════════════════════════════════════════
// Vendra Vendor App - Walk-in POS receipt (the printed / shared slip)
// Sent with POST /api/vendor/pos/sales (`receipt`) and by
// GET /api/vendor/pos/sales/:id for a reprint:
//   { receipt_number, store: { name, address, phone, header, footer },
//     sale: { id, total_amount, created_at, cashier_name, items: [...] },
//     cashier, payment_qr: { account, title, payload } | null }
// payment_qr.payload is the text of the slip's scan-to-pay QR; it is null
// until the owner sets a payment account in Receipt settings.
// ══════════════════════════════════════════════════════════════

import 'package:intl/intl.dart';
import 'package:vendra_vendor/vendra_core.dart';

class ReceiptLine {
  final String name;
  final String? barcode;
  final int quantity;
  final double unitPrice;

  const ReceiptLine({required this.name, this.barcode, required this.quantity, required this.unitPrice});

  factory ReceiptLine.fromJson(Map<String, dynamic> json) => ReceiptLine(
        name: json['product_name'] ?? 'Item',
        barcode: json['barcode'],
        quantity: toInt(json['quantity']),
        unitPrice: toDouble(json['unit_price']),
      );

  double get total => unitPrice * quantity;
}

class ReceiptPaymentQr {
  final String account; // IBAN / Raast ID / wallet number
  final String title;
  final String payload; // encoded in the QR

  const ReceiptPaymentQr({required this.account, required this.title, required this.payload});
}

class PosReceipt {
  final String receiptNumber; // "POS-000042"
  final String storeName;
  final String? storeAddress;
  final String? storePhone;
  final String? header;
  final String? footer;
  final int saleId;
  final double total;
  final DateTime? createdAt;
  final String? cashier;
  final List<ReceiptLine> items;
  final ReceiptPaymentQr? paymentQr;

  const PosReceipt({
    required this.receiptNumber,
    required this.storeName,
    this.storeAddress,
    this.storePhone,
    this.header,
    this.footer,
    required this.saleId,
    required this.total,
    this.createdAt,
    this.cashier,
    this.items = const [],
    this.paymentQr,
  });

  factory PosReceipt.fromJson(Map<String, dynamic> json) {
    final store = json['store'] is Map ? Map<String, dynamic>.from(json['store']) : const <String, dynamic>{};
    final sale = json['sale'] is Map ? Map<String, dynamic>.from(json['sale']) : const <String, dynamic>{};
    final qr = json['payment_qr'] is Map ? Map<String, dynamic>.from(json['payment_qr']) : null;
    final payload = qr?['payload']?.toString();
    return PosReceipt(
      receiptNumber: json['receipt_number'] ?? 'POS-${toInt(sale['id'])}',
      storeName: _text(store['name']) ?? 'Vendra Store',
      storeAddress: _text(store['address']),
      storePhone: _text(store['phone']),
      header: _text(store['header']),
      footer: _text(store['footer']),
      saleId: toInt(sale['id']),
      total: toDouble(sale['total_amount']),
      createdAt: toDate(sale['created_at']),
      cashier: _text(json['cashier']) ?? _text(sale['cashier_name']),
      items: (sale['items'] as List? ?? const [])
          .whereType<Map>()
          .map((i) => ReceiptLine.fromJson(Map<String, dynamic>.from(i)))
          .toList(),
      paymentQr: payload == null || payload.isEmpty
          ? null
          : ReceiptPaymentQr(
              account: qr?['account']?.toString() ?? '',
              title: qr?['title']?.toString() ?? '',
              payload: payload,
            ),
    );
  }

  /// Trimmed text, null when blank
  static String? _text(dynamic v) {
    final s = v?.toString().trim();
    return s == null || s.isEmpty ? null : s;
  }

  int get unitCount => items.fold(0, (s, i) => s + i.quantity);
}

/// Text shared by the on-screen slip and the 80 mm PDF
class ReceiptFormat {
  static final DateFormat _date = DateFormat('d MMM yyyy, h:mm a');

  /// "Rs. 1,250" / "Rs. 99.50"
  static String money(double v) => formatRupees(v);

  /// "2 × Rs. 150"
  static String qtyLine(ReceiptLine line) => '${line.quantity} × ${money(line.unitPrice)}';

  static String dateTime(DateTime? at) => at == null ? '' : _date.format(at);

  static String itemCount(PosReceipt r) =>
      '${r.unitCount} item${r.unitCount == 1 ? '' : 's'}';

  /// The PDF's built-in Courier font only covers Latin-1: swap common
  /// typography for ASCII and drop anything else (e.g. Urdu script) to '?'
  static String pdfSafe(String text) {
    const swaps = {
      '×': 'x', '—': '-', '–': '-', '‘': "'", '’': "'", '“': '"', '”': '"',
      '…': '...', '•': '*', '·': '-', '₨': 'Rs.',
    };
    final out = StringBuffer();
    for (final rune in text.runes) {
      final ch = String.fromCharCode(rune);
      if (swaps.containsKey(ch)) {
        out.write(swaps[ch]);
      } else if (rune == 0x0A || (rune >= 0x20 && rune <= 0x7E) || (rune >= 0xA0 && rune <= 0xFF)) {
        out.write(ch);
      } else {
        out.write('?');
      }
    }
    return out.toString();
  }
}
