// ══════════════════════════════════════════════════════════════
// Vendra Vendor App - Walk-in POS models (FR01 / FR02)
// POST /api/vendor/pos/sales  → { id, total_amount, created_at, items: [...] }
// GET  /api/vendor/pos/sales  → { sales, today_count, today_total }
// ══════════════════════════════════════════════════════════════

import 'package:vendra_vendor/vendra_core.dart';

/// One product line in the sale being rung up
class PosLine {
  final int productId;
  final String name;
  final double unitPrice;
  final int quantity;

  const PosLine({required this.productId, required this.name, required this.unitPrice, required this.quantity});

  PosLine withQuantity(int q) => PosLine(productId: productId, name: name, unitPrice: unitPrice, quantity: q);

  double get total => unitPrice * quantity;
}

class PosSaleItem {
  final int productId;
  final String productName;
  final int quantity;
  final double unitPrice;
  // Only present on the POST response (stock right after the sale)
  final int? privateStockAfter;
  final int? publicStockAfter;
  final int? reservedQuantity;

  PosSaleItem({
    required this.productId,
    required this.productName,
    required this.quantity,
    required this.unitPrice,
    this.privateStockAfter,
    this.publicStockAfter,
    this.reservedQuantity,
  });

  factory PosSaleItem.fromJson(Map<String, dynamic> json) => PosSaleItem(
        productId: toInt(json['product_id']),
        productName: json['product_name'] ?? 'Product',
        quantity: toInt(json['quantity']),
        unitPrice: toDouble(json['unit_price']),
        privateStockAfter: toIntOrNull(json['private_stock_after']),
        publicStockAfter: toIntOrNull(json['public_stock_after']),
        reservedQuantity: toIntOrNull(json['reserved_quantity']),
      );

  double get total => unitPrice * quantity;
}

class PosSale {
  final int id;
  final double totalAmount;
  final DateTime? createdAt;
  final List<PosSaleItem> items;

  PosSale({required this.id, required this.totalAmount, this.createdAt, this.items = const []});

  factory PosSale.fromJson(Map<String, dynamic> json) => PosSale(
        id: toInt(json['id']),
        totalAmount: toDouble(json['total_amount']),
        createdAt: toDate(json['created_at']),
        items: (json['items'] as List<dynamic>? ?? const [])
            .map((i) => PosSaleItem.fromJson(Map<String, dynamic>.from(i)))
            .toList(),
      );

  int get unitCount => items.fold(0, (sum, i) => sum + i.quantity);
}
