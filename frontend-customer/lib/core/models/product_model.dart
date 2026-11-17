// ══════════════════════════════════════════════════════════════
// Vendra App - Product Model
// Supports dual inventory fields + vendor location + category/approval,
// ratings and the photo gallery
// ══════════════════════════════════════════════════════════════

import 'json_utils.dart';

class ProductModel {
  final int id;
  final int vendorId;
  final String? storeName;
  final String? storeAddress;
  /// The store's logo (relative /uploads path or absolute URL); null shows its initials
  final String? storeLogoUrl;
  final double? vendorLat;
  final double? vendorLng;
  final int? categoryId;
  final String? categoryName;
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
  final bool isApproved;
  final String? createdAt;
  /// 1-decimal average of customer reviews; null until the first review
  final double? averageRating;
  final int ratingCount;
  /// Extra photos after the cover ([imageUrl]). Vendor rows carry ids (to delete them)
  final List<GalleryPhoto> gallery;

  ProductModel({
    required this.id,
    required this.vendorId,
    this.storeName,
    this.storeAddress,
    this.storeLogoUrl,
    this.vendorLat,
    this.vendorLng,
    this.categoryId,
    this.categoryName,
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
    this.isApproved = true,
    this.createdAt,
    this.averageRating,
    this.ratingCount = 0,
    this.gallery = const [],
  });

  factory ProductModel.fromJson(Map<String, dynamic> json) {
    return ProductModel(
      id: toInt(json['id']),
      vendorId: toInt(pick(json, 'vendorId', 'vendor_id')),
      storeName: pick(json, 'storeName', 'store_name'),
      storeAddress: pick(json, 'storeAddress', 'store_address'),
      storeLogoUrl: pick(json, 'storeLogoUrl', 'store_logo_url'),
      vendorLat: toDoubleOrNull(pick(json, 'vendorLat', 'vendor_lat')),
      vendorLng: toDoubleOrNull(pick(json, 'vendorLng', 'vendor_lng')),
      categoryId: toIntOrNull(pick(json, 'categoryId', 'category_id')),
      categoryName: pick(json, 'categoryName', 'category_name'),
      name: json['name'] ?? '',
      description: json['description'],
      price: toDouble(json['price']),
      privateStock: toInt(pick(json, 'privateStock', 'private_stock')),
      buffer: toInt(json['buffer'], 5),
      reservedQuantity: toInt(pick(json, 'reservedQuantity', 'reserved_quantity')),
      publicStock: toInt(pick(json, 'publicStock', 'public_stock')),
      barcode: json['barcode'],
      imageUrl: pick(json, 'imageUrl', 'image_url'),
      isActive: pick(json, 'isActive', 'is_active') ?? true,
      isApproved: pick(json, 'isApproved', 'is_approved') ?? true,
      createdAt: pick(json, 'createdAt', 'created_at'),
      averageRating: toDoubleOrNull(pick(json, 'averageRating', 'average_rating')),
      ratingCount: toInt(pick(json, 'ratingCount', 'rating_count')),
      gallery: GalleryPhoto.listFrom(json),
    );
  }

  Map<String, dynamic> toJson() => {
    'name': name,
    'description': description,
    'price': price,
    'private_stock': privateStock,
    'buffer': buffer,
    'barcode': barcode,
    'category_id': categoryId,
  };

  /// Copy with new stock numbers (used when a realtime stock update arrives)
  ProductModel withStock({int? privateStock, int? reservedQuantity, int? buffer, int? publicStock}) {
    return ProductModel(
      id: id,
      vendorId: vendorId,
      storeName: storeName,
      storeAddress: storeAddress,
      storeLogoUrl: storeLogoUrl,
      vendorLat: vendorLat,
      vendorLng: vendorLng,
      categoryId: categoryId,
      categoryName: categoryName,
      name: name,
      description: description,
      price: price,
      privateStock: privateStock ?? this.privateStock,
      buffer: buffer ?? this.buffer,
      reservedQuantity: reservedQuantity ?? this.reservedQuantity,
      publicStock: publicStock ?? this.publicStock,
      barcode: barcode,
      imageUrl: imageUrl,
      isActive: isActive,
      isApproved: isApproved,
      createdAt: createdAt,
      averageRating: averageRating,
      ratingCount: ratingCount,
      gallery: gallery,
    );
  }

  /// Every photo, cover first (what the product page swipes through)
  List<String> get allImages => [
        if (imageUrl != null && imageUrl!.isNotEmpty) imageUrl!,
        ...gallery.map((g) => g.url).where((u) => u != imageUrl),
      ];

  /// Units a walk-in cashier may sell: the buffer is theirs, reserved units are not
  int get sellableInStore => (privateStock - reservedQuantity).clamp(0, privateStock);

  /// Whether this product has any reserved stock
  bool get hasReservations => reservedQuantity > 0;

  /// Whether stock is low (public stock < 10)
  bool get isLowStock => publicStock < 10 && publicStock > 0;

  /// Whether product is out of stock (public)
  bool get isOutOfStock => publicStock <= 0;
}

/// A gallery photo: vendor rows have `{ id, url }`; the public product page sends
/// `images: [url…]` (cover first), in which case the cover is skipped here.
class GalleryPhoto {
  final int? id;
  final String url;

  const GalleryPhoto({this.id, required this.url});

  static List<GalleryPhoto> listFrom(Map<String, dynamic> json) {
    final gallery = json['gallery'];
    if (gallery is List) {
      return gallery
          .whereType<Map>()
          .map((g) => GalleryPhoto(id: toIntOrNull(g['id']), url: g['url']?.toString() ?? ''))
          .where((g) => g.url.isNotEmpty)
          .toList();
    }
    final images = json['images'];
    if (images is List) {
      final cover = pick(json, 'imageUrl', 'image_url');
      return images.map((u) => u.toString()).where((u) => u != cover).map((u) => GalleryPhoto(url: u)).toList();
    }
    return const [];
  }
}
