// ══════════════════════════════════════════════════════════════
// Vendra App - Order Model
// Parses both the customer (camelCase) and vendor (snake_case) shapes.
// ══════════════════════════════════════════════════════════════

import 'json_utils.dart';

class OrderModel {
  final int id;
  final int? vendorId;
  final String? storeName;
  final String? storeAddress;
  final double? vendorLat;
  final double? vendorLng;
  final int? customerId;
  final String? customerName;
  final String? customerPhone;
  final String status;
  final String? deliveryType;
  final String? deliveryAddress;
  final double? customerLat;
  final double? customerLng;
  final int? estimatedMinutes;
  final String? escrowStatus;
  final DateTime? escrowReleaseDueAt;
  final String? cancellationReason;
  final double subtotal;
  final double deliveryFee;
  final double totalAmount;
  final double riderPayout;
  final OrderRider? rider;
  final DisputeSummary? latestDispute;
  final String? createdAt;
  final DateTime? assignedAt;
  final DateTime? pickedAt;
  final DateTime? deliveredAt;
  final List<OrderItemModel> items;

  OrderModel({
    required this.id,
    this.vendorId,
    this.storeName,
    this.storeAddress,
    this.vendorLat,
    this.vendorLng,
    this.customerId,
    this.customerName,
    this.customerPhone,
    required this.status,
    this.deliveryType,
    this.deliveryAddress,
    this.customerLat,
    this.customerLng,
    this.estimatedMinutes,
    this.escrowStatus,
    this.escrowReleaseDueAt,
    this.cancellationReason,
    this.subtotal = 0,
    this.deliveryFee = 0,
    required this.totalAmount,
    this.riderPayout = 0,
    this.rider,
    this.latestDispute,
    this.createdAt,
    this.assignedAt,
    this.pickedAt,
    this.deliveredAt,
    this.items = const [],
  });

  factory OrderModel.fromJson(Map<String, dynamic> json) {
    final total = toDouble(pick(json, 'totalAmount', 'total_amount'));
    final riderJson = json['rider'];
    final riderId = toIntOrNull(pick(json, 'riderUserId', 'rider_user_id'));
    final disputeJson = pick(json, 'latestDispute', 'latest_dispute');

    return OrderModel(
      id: toInt(json['id']),
      vendorId: toIntOrNull(pick(json, 'vendorId', 'vendor_id')),
      storeName: pick(json, 'storeName', 'store_name'),
      storeAddress: pick(json, 'storeAddress', 'store_address'),
      vendorLat: toDoubleOrNull(pick(json, 'vendorLat', 'vendor_lat')),
      vendorLng: toDoubleOrNull(pick(json, 'vendorLng', 'vendor_lng')),
      customerId: toIntOrNull(pick(json, 'customerId', 'customer_id')),
      customerName: pick(json, 'customerName', 'customer_name'),
      customerPhone: pick(json, 'customerPhone', 'customer_phone'),
      status: json['status'] ?? 'pending',
      deliveryType: pick(json, 'deliveryType', 'delivery_type'),
      deliveryAddress: pick(json, 'deliveryAddress', 'delivery_address'),
      customerLat: toDoubleOrNull(pick(json, 'customerLat', 'customer_lat')),
      customerLng: toDoubleOrNull(pick(json, 'customerLng', 'customer_lng')),
      estimatedMinutes: toIntOrNull(pick(json, 'estimatedMinutes', 'estimated_minutes')),
      escrowStatus: pick(json, 'escrowStatus', 'escrow_status'),
      escrowReleaseDueAt: toDate(pick(json, 'escrowReleaseDueAt', 'escrow_release_due_at')),
      cancellationReason: pick(json, 'cancellationReason', 'cancellation_reason'),
      subtotal: toDouble(pick(json, 'subtotal'), total),
      deliveryFee: toDouble(pick(json, 'deliveryFee', 'delivery_fee')),
      totalAmount: total,
      riderPayout: toDouble(pick(json, 'riderPayout', 'rider_payout')),
      rider: riderJson is Map<String, dynamic>
          ? OrderRider.fromJson(riderJson)
          : (riderId != null
              ? OrderRider(id: riderId, name: json['rider_name'], phone: json['rider_phone'])
              : null),
      latestDispute: disputeJson is Map<String, dynamic> ? DisputeSummary.fromJson(disputeJson) : null,
      createdAt: pick(json, 'createdAt', 'created_at'),
      assignedAt: toDate(pick(json, 'assignedAt', 'assigned_at')),
      pickedAt: toDate(pick(json, 'pickedAt', 'picked_at')),
      deliveredAt: toDate(pick(json, 'deliveredAt', 'delivered_at')),
      items: (json['items'] as List<dynamic>?)
              ?.map((item) => OrderItemModel.fromJson(Map<String, dynamic>.from(item)))
              .toList() ??
          [],
    );
  }

  bool get isDelivery => deliveryType == 'delivery';
  bool get hasOpenDispute => latestDispute?.status == 'open';

  /// Disputes are allowed while payment is still held (not cancelled, not settled)
  bool get canDispute => status != 'cancelled' && escrowStatus == 'held';

  /// Get display-friendly status text
  String get statusText {
    switch (status) {
      case 'pending':
        return 'Pending Vendor Confirmation';
      case 'confirmed':
        return 'Confirmed by Vendor';
      case 'packed':
        return 'Packed';
      case 'ready_for_pickup':
        return isDelivery ? (rider != null ? 'Rider Assigned' : 'Finding a Rider') : 'Ready for Pickup';
      case 'picked':
        return 'Picked Up';
      case 'on_the_way':
        return 'On the Way';
      case 'delivered':
        return 'Delivered';
      case 'cancelled':
        return cancellationReason != null && cancellationReason!.isNotEmpty
            ? cancellationReason!
            : 'Cancelled';
      default:
        return status;
    }
  }

  /// Delivery type display
  String get deliveryTypeText {
    switch (deliveryType) {
      case 'self_pickup': return 'Self Pickup';
      case 'delivery': return 'Home Delivery';
      default: return 'Delivery';
    }
  }

  /// Escrow status display
  String get escrowStatusText {
    switch (escrowStatus) {
      case 'held': return 'Payment Held in Escrow';
      case 'disputed': return 'Payment Frozen — Dispute Open';
      case 'released': return 'Payment Released';
      case 'refunded': return 'Payment Refunded';
      default: return 'Payment Processing';
    }
  }
}

class OrderRider {
  final int id;
  final String? name;
  final String? phone;

  OrderRider({required this.id, this.name, this.phone});

  factory OrderRider.fromJson(Map<String, dynamic> json) =>
      OrderRider(id: toInt(json['id']), name: json['name'], phone: json['phone']);
}

class DisputeSummary {
  final int id;
  final String status; // open | resolved
  final String? resolution; // refund | release
  final String? issueType;

  DisputeSummary({required this.id, required this.status, this.resolution, this.issueType});

  factory DisputeSummary.fromJson(Map<String, dynamic> json) => DisputeSummary(
        id: toInt(json['id']),
        status: json['status'] ?? 'open',
        resolution: json['resolution'],
        issueType: pick(json, 'issueType', 'issue_type'),
      );
}

class OrderItemModel {
  final int? id;
  final int productId;
  final String? productName;
  final int quantity;
  final double unitPrice;
  final String? imageUrl; // product photo path, if the product has one

  OrderItemModel({
    this.id,
    required this.productId,
    this.productName,
    required this.quantity,
    required this.unitPrice,
    this.imageUrl,
  });

  factory OrderItemModel.fromJson(Map<String, dynamic> json) {
    return OrderItemModel(
      id: toIntOrNull(json['id']),
      productId: toInt(pick(json, 'productId', 'product_id')),
      productName: pick(json, 'productName', 'product_name'),
      quantity: toInt(json['quantity']),
      unitPrice: toDouble(pick(json, 'unitPrice', 'unit_price')),
      imageUrl: pick(json, 'imageUrl', 'image_url'),
    );
  }

  double get total => unitPrice * quantity;
}
