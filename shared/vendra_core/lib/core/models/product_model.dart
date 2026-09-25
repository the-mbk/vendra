// ══════════════════════════════════════════════════════════════
// Vendra App - Product Model
// Supports dual inventory fields + vendor location
// ══════════════════════════════════════════════════════════════

class ProductModel {
  final int id;
  final int vendorId;
  final String? storeName;
  final String? storeAddress;
  final double? vendorLat;
  final double? vendorLng;
  final String name;
  final String? description;
  final double price;
  final int privateStock;
  final int buffer;
  final int reservedQuantity;
  final int publicStock;
  final String? barcode;
  final String? imageUrl;
  final bool isActive;
  final String? createdAt;

  ProductModel({
    required this.id,
    required this.vendorId,
    this.storeName,
    this.storeAddress,
    this.vendorLat,
    this.vendorLng,
    required this.name,
    this.description,
    required this.price,
    this.privateStock = 0,
    this.buffer = 5,
    this.reservedQuantity = 0,
    required this.publicStock,
    this.barcode,
    this.imageUrl,
    this.isActive = true,
    this.createdAt,
  });

  factory ProductModel.fromJson(Map<String, dynamic> json) {
    return ProductModel(
      id: json['id'],
      vendorId: json['vendorId'] ?? json['vendor_id'] ?? 0,
      storeName: json['storeName'] ?? json['store_name'],
      storeAddress: json['storeAddress'] ?? json['store_address'],
      vendorLat: json['vendorLat'] != null ? (json['vendorLat'] as num).toDouble() : null,
      vendorLng: json['vendorLng'] != null ? (json['vendorLng'] as num).toDouble() : null,
      name: json['name'] ?? '',
      description: json['description'],
      price: (json['price'] is num) ? (json['price'] as num).toDouble() : double.tryParse(json['price']?.toString() ?? '0') ?? 0,
      privateStock: json['privateStock'] ?? json['private_stock'] ?? 0,
      buffer: json['buffer'] ?? 5,
      reservedQuantity: json['reservedQuantity'] ?? json['reserved_quantity'] ?? 0,
      publicStock: json['publicStock'] ?? json['public_stock'] ?? 0,
      barcode: json['barcode'],
      imageUrl: json['imageUrl'] ?? json['image_url'],
      isActive: json['isActive'] ?? json['is_active'] ?? true,
      createdAt: json['createdAt'] ?? json['created_at'],
    );
  }

  Map<String, dynamic> toJson() => {
    'name': name,
    'description': description,
    'price': price,
    'private_stock': privateStock,
    'buffer': buffer,
    'barcode': barcode,
  };

  /// Whether this product has any reserved stock
  bool get hasReservations => reservedQuantity > 0;

  /// Whether stock is low (public stock < 10)
  bool get isLowStock => publicStock < 10 && publicStock > 0;

  /// Whether product is out of stock (public)
  bool get isOutOfStock => publicStock <= 0;
}
