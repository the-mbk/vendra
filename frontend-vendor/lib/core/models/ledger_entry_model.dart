// ══════════════════════════════════════════════════════════════
// Vendra App - Ledger Entry Model (vendor app only)
// GET /api/vendor/inventory/ledger — change_type is one of:
//   stock_in, adjustment, reserve, release,
//   sale (online order delivered), pos_sale (walk-in sale)
// ══════════════════════════════════════════════════════════════

import 'json_utils.dart';

class LedgerEntryModel {
  final int id;
  final int productId;
  final String? productName;
  final int vendorId;
  final String changeType;
  final int quantityChange;
  final int? privateStockAfter;
  final int? publicStockAfter;
  final int? referenceId;
  final String? notes;
  final String? createdAt;

  LedgerEntryModel({
    required this.id,
    required this.productId,
    this.productName,
    required this.vendorId,
    required this.changeType,
    required this.quantityChange,
    this.privateStockAfter,
    this.publicStockAfter,
    this.referenceId,
    this.notes,
    this.createdAt,
  });

  factory LedgerEntryModel.fromJson(Map<String, dynamic> json) {
    return LedgerEntryModel(
      id: toInt(json['id']),
      productId: toInt(pick(json, 'productId', 'product_id')),
      productName: pick(json, 'productName', 'product_name'),
      vendorId: toInt(pick(json, 'vendorId', 'vendor_id')),
      changeType: pick(json, 'changeType', 'change_type') ?? '',
      quantityChange: toInt(pick(json, 'quantityChange', 'quantity_change')),
      privateStockAfter: toIntOrNull(pick(json, 'privateStockAfter', 'private_stock_after')),
      publicStockAfter: toIntOrNull(pick(json, 'publicStockAfter', 'public_stock_after')),
      referenceId: toIntOrNull(pick(json, 'referenceId', 'reference_id')),
      notes: json['notes'],
      createdAt: pick(json, 'createdAt', 'created_at'),
    );
  }

  /// Human-readable change type
  String get changeTypeDisplay {
    switch (changeType) {
      case 'stock_in': return 'Stock Added';
      case 'adjustment': return 'Stock Adjusted';
      case 'reserve': return 'Reserved for Online Order';
      case 'release': return 'Reservation Released';
      case 'sale': return 'Sold Online (Delivered)';
      case 'pos_sale': return 'Walk-in Sale (POS)';
      default: return changeType;
    }
  }

  /// What the reference id points at, e.g. "Order #12" / "Sale #4"
  String? get referenceLabel {
    if (referenceId == null) return null;
    switch (changeType) {
      case 'reserve':
      case 'release':
      case 'sale':
        return 'Order #$referenceId';
      case 'pos_sale':
        return 'Sale #$referenceId';
      default:
        return null;
    }
  }
}
