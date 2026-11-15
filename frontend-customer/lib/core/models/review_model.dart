// ══════════════════════════════════════════════════════════════
// Vendra App - Review Model (SRDS §2.3)
// One customer's stars + comment for a product of a delivered order.
// ══════════════════════════════════════════════════════════════

import 'json_utils.dart';

class ReviewModel {
  final int id;
  final int? orderId;
  final int productId;
  final String? productName;
  final int rating;
  final String? comment;
  final String customerName; // "Ahmed R."
  final DateTime? createdAt;

  ReviewModel({
    required this.id,
    this.orderId,
    required this.productId,
    this.productName,
    required this.rating,
    this.comment,
    required this.customerName,
    this.createdAt,
  });

  factory ReviewModel.fromJson(Map<String, dynamic> json) => ReviewModel(
        id: toInt(json['id']),
        orderId: toIntOrNull(json['orderId']),
        productId: toInt(json['productId']),
        productName: json['productName'],
        rating: toInt(json['rating']),
        comment: json['comment'],
        customerName: json['customerName'] ?? 'Customer',
        createdAt: toDate(json['createdAt']),
      );
}
