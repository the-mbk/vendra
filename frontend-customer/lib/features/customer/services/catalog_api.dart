// ══════════════════════════════════════════════════════════════
// Vendra Customer App - Catalog API
// The product page, store page and their reviews:
//   GET /api/products/:id                        product + gallery + rating breakdown
//   GET /api/customer/products/:id/review-order  { orderId } the customer can review it with
//   GET /api/customer/orders/:id                 that order (for the review sheet)
//   GET /api/vendors/:id                         store + logo/cover + reviews summary + products
//   GET /api/vendors/:id/reviews                 every review of the store's products (paged)
// Screens and blocs use [CatalogApi.instance]; tests swap in a fake.
// ══════════════════════════════════════════════════════════════

import 'package:vendra_customer/vendra_core.dart';

/// A failed reply the server explained; reads as its message
class CatalogException implements Exception {
  final String message;
  const CatalogException(this.message);
  @override
  String toString() => message;
}

class CatalogApi {
  const CatalogApi();

  /// What the app talks to; tests replace it with a stand-in
  static CatalogApi instance = const CatalogApi();

  static Map<String, dynamic> _data(dynamic body, String fallback) {
    if (body is! Map || body['success'] != true) {
      throw CatalogException(body is Map ? (body['message']?.toString() ?? fallback) : fallback);
    }
    final data = body['data'];
    if (data is Map) return Map<String, dynamic>.from(data);
    throw CatalogException(fallback);
  }

  /// GET /api/products/:id (the raw product with images, ratingDistribution, latestReviews)
  Future<Map<String, dynamic>> product(int id) async =>
      _data((await ApiService().get(ApiConfig.product(id))).data, 'Could not load this product');

  /// The signed-in customer's delivered, not-yet-reviewed order containing the
  /// product, or null (none, or not signed in)
  Future<int?> reviewOrderId(int productId) async {
    final res = await ApiService().get(ApiConfig.productReviewOrder(productId));
    final body = res.data;
    if (body is! Map || body['success'] != true || body['data'] is! Map) return null;
    return toIntOrNull((body['data'] as Map)['orderId']);
  }

  /// GET /api/customer/orders/:id
  Future<OrderModel> order(int id) async =>
      OrderModel.fromJson(_data((await ApiService().get(ApiConfig.customerOrder(id))).data, 'Could not load the order'));

  /// GET /api/vendors/:id
  Future<Map<String, dynamic>> store(int vendorId) async =>
      _data((await ApiService().get(ApiConfig.vendorDetails(vendorId))).data, 'Failed to load store');

  /// One page of GET /api/vendors/:id/reviews (newest first)
  Future<(List<ReviewModel>, PageMeta)> storeReviews(int vendorId, {int limit = 20, int offset = 0}) async {
    final res = await ApiService().get(ApiConfig.storeReviews(vendorId), queryParams: {'limit': limit, 'offset': offset});
    final body = res.data;
    if (body is! Map || body['success'] != true) {
      throw CatalogException(
          body is Map ? (body['message']?.toString() ?? 'Could not load reviews') : 'Could not load reviews');
    }
    final reviews = (body['data'] as List<dynamic>? ?? const [])
        .whereType<Map>()
        .map((r) => ReviewModel.fromJson(Map<String, dynamic>.from(r)))
        .toList();
    return (reviews, PageMeta.fromResponse(body));
  }
}
