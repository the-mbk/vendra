// ══════════════════════════════════════════════════════════════
// Vendra App - Order Model
// ══════════════════════════════════════════════════════════════

class OrderModel {
  final int id;
  final int? vendorId;
  final String? storeName;
  final int? customerId;
  final String? customerName;
  final String status;
  final String? deliveryType;
  final int? estimatedMinutes;
  final String? escrowStatus;
  final String? cancellationReason;
  final double totalAmount;
  final String? createdAt;
  final List<OrderItemModel> items;

  OrderModel({
    required this.id,
    this.vendorId,
    this.storeName,
    this.customerId,
    this.customerName,
    required this.status,
    this.deliveryType,
    this.estimatedMinutes,
    this.escrowStatus,
    this.cancellationReason,
    required this.totalAmount,
    this.createdAt,
    this.items = const [],
  });

  factory OrderModel.fromJson(Map<String, dynamic> json) {
    return OrderModel(
      id: json['id'],
      vendorId: json['vendorId'] ?? json['vendor_id'],
      storeName: json['storeName'] ?? json['store_name'],
      customerId: json['customerId'] ?? json['customer_id'],
      customerName: json['customerName'] ?? json['customer_name'],
      status: json['status'] ?? 'pending',
      deliveryType: json['deliveryType'] ?? json['delivery_type'],
      estimatedMinutes: json['estimatedMinutes'] ?? json['estimated_minutes'],
      escrowStatus: json['escrowStatus'] ?? json['escrow_status'],
      cancellationReason: json['cancellationReason'] ?? json['cancellation_reason'],
      totalAmount: (json['totalAmount'] is num)
          ? (json['totalAmount'] as num).toDouble()
          : double.tryParse(json['totalAmount']?.toString() ?? json['total_amount']?.toString() ?? '0') ?? 0,
      createdAt: json['createdAt'] ?? json['created_at'],
      items: (json['items'] as List<dynamic>?)
              ?.map((item) => OrderItemModel.fromJson(item))
              .toList() ??
          [],
    );
  }

  /// Get display-friendly status text
  String get statusText {
    switch (status) {
      case 'pending':
        return 'Pending Vendor Confirmation';
      case 'confirmed':
        return 'Confirmed by Vendor';
      case 'packed':
        return 'Preparing';
      case 'ready_for_pickup':
        return 'Ready for Pickup';
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
      case 'released': return 'Payment Released';
      default: return 'Payment Processing';
    }
  }
}

class OrderItemModel {
  final int? id;
  final int productId;
  final String? productName;
  final int quantity;
  final double unitPrice;

  OrderItemModel({
    this.id,
    required this.productId,
    this.productName,
    required this.quantity,
    required this.unitPrice,
  });

  factory OrderItemModel.fromJson(Map<String, dynamic> json) {
    return OrderItemModel(
      id: json['id'],
      productId: json['productId'] ?? json['product_id'] ?? 0,
      productName: json['productName'] ?? json['product_name'],
      quantity: json['quantity'] ?? 0,
      unitPrice: (json['unitPrice'] is num)
          ? (json['unitPrice'] as num).toDouble()
          : double.tryParse(json['unitPrice']?.toString() ?? json['unit_price']?.toString() ?? '0') ?? 0,
    );
  }

  double get total => unitPrice * quantity;
}
