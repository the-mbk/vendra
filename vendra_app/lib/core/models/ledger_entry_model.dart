// ══════════════════════════════════════════════════════════════
// Vendra App - Ledger Entry Model
// ══════════════════════════════════════════════════════════════

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
    this.createdAt,
  });

  factory LedgerEntryModel.fromJson(Map<String, dynamic> json) {
    return LedgerEntryModel(
      id: json['id'],
      productId: json['productId'] ?? json['product_id'] ?? 0,
      productName: json['productName'] ?? json['product_name'],
      vendorId: json['vendorId'] ?? json['vendor_id'] ?? 0,
      changeType: json['changeType'] ?? json['change_type'] ?? '',
      quantityChange: json['quantityChange'] ?? json['quantity_change'] ?? 0,
      privateStockAfter: json['privateStockAfter'] ?? json['private_stock_after'],
      publicStockAfter: json['publicStockAfter'] ?? json['public_stock_after'],
      referenceId: json['referenceId'] ?? json['reference_id'],
      createdAt: json['createdAt'] ?? json['created_at'],
    );
  }

  /// Human-readable change type
  String get changeTypeDisplay {
    switch (changeType) {
      case 'stock_in': return 'Stock Added';
      case 'reserve': return 'Reserved';
      case 'release': return 'Released';
      case 'sale': return 'Sold';
      default: return changeType;
    }
  }
}
