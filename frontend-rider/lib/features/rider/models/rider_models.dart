// ══════════════════════════════════════════════════════════════
// Vendra Rider App - Rider models
// Shapes of /api/rider/tasks, /api/rider/orders, /api/rider/earnings
// and the deliver response. (Rider-only, so not in the shared core.)
// ══════════════════════════════════════════════════════════════

import 'package:latlong2/latlong.dart';
import 'package:vendra_rider/vendra_core.dart';

/// A delivery task or a rider's order — the API uses the same shape for both.
class RiderOrder {
  final int id;
  final String status;
  final String? storeName;
  final String? storeAddress;
  final String? storePhone;
  final double? storeLat;
  final double? storeLng;
  final String? customerName;
  final String? customerPhone;
  final String? deliveryAddress;
  final double? customerLat;
  final double? customerLng;
  final int itemCount;
  final double totalAmount;
  final DateTime? readyAt;
  final DateTime? assignedAt;
  final DateTime? arrivedAt;
  final DateTime? pickedAt;
  final DateTime? deliveredAt;
  final double? distanceKm;
  final double? waitMinutes;
  final double payout;
  // Task-only fields
  final double? distanceToStoreKm;
  final double? tripDistanceKm;
  final double? estimatedPayout;

  const RiderOrder({
    required this.id,
    required this.status,
    this.storeName,
    this.storeAddress,
    this.storePhone,
    this.storeLat,
    this.storeLng,
    this.customerName,
    this.customerPhone,
    this.deliveryAddress,
    this.customerLat,
    this.customerLng,
    this.itemCount = 0,
    this.totalAmount = 0,
    this.readyAt,
    this.assignedAt,
    this.arrivedAt,
    this.pickedAt,
    this.deliveredAt,
    this.distanceKm,
    this.waitMinutes,
    this.payout = 0,
    this.distanceToStoreKm,
    this.tripDistanceKm,
    this.estimatedPayout,
  });

  factory RiderOrder.fromJson(Map<String, dynamic> json) => RiderOrder(
        id: toInt(json['id']),
        status: json['status'] ?? '',
        storeName: json['storeName'],
        storeAddress: json['storeAddress'],
        storePhone: json['storePhone'],
        storeLat: toDoubleOrNull(json['storeLat']),
        storeLng: toDoubleOrNull(json['storeLng']),
        customerName: json['customerName'],
        customerPhone: json['customerPhone'],
        deliveryAddress: json['deliveryAddress'],
        customerLat: toDoubleOrNull(json['customerLat']),
        customerLng: toDoubleOrNull(json['customerLng']),
        itemCount: toInt(json['itemCount']),
        totalAmount: toDouble(json['totalAmount']),
        readyAt: toDate(json['readyAt']),
        assignedAt: toDate(json['assignedAt']),
        arrivedAt: toDate(json['arrivedAt']),
        pickedAt: toDate(json['pickedAt']),
        deliveredAt: toDate(json['deliveredAt']),
        distanceKm: toDoubleOrNull(json['distanceKm']),
        waitMinutes: toDoubleOrNull(json['waitMinutes']),
        payout: toDouble(json['payout']),
        distanceToStoreKm: toDoubleOrNull(json['distanceToStoreKm']),
        tripDistanceKm: toDoubleOrNull(json['tripDistanceKm']),
        estimatedPayout: toDoubleOrNull(json['estimatedPayout']),
      );

  LatLng? get storePoint => storeLat != null && storeLng != null ? LatLng(storeLat!, storeLng!) : null;
  LatLng? get customerPoint =>
      customerLat != null && customerLng != null ? LatLng(customerLat!, customerLng!) : null;

  bool get isDelivered => status == 'delivered';
  bool get isCancelled => status == 'cancelled';

  /// Where the rider is in the delivery flow
  DeliveryStep get step {
    switch (status) {
      case 'ready_for_pickup':
        return arrivedAt == null ? DeliveryStep.headingToStore : DeliveryStep.atStore;
      case 'picked':
        return DeliveryStep.pickedUp;
      case 'on_the_way':
        return DeliveryStep.onTheWay;
      case 'delivered':
        return DeliveryStep.delivered;
      default:
        return DeliveryStep.closed;
    }
  }

  String get statusText {
    switch (status) {
      case 'ready_for_pickup':
        return arrivedAt == null ? 'Heading to store' : 'At the store';
      case 'picked':
        return 'Picked up';
      case 'on_the_way':
        return 'On the way';
      case 'delivered':
        return 'Delivered';
      case 'cancelled':
        return 'Cancelled';
      default:
        return status;
    }
  }
}

enum DeliveryStep { headingToStore, atStore, pickedUp, onTheWay, delivered, closed }

/// GET /api/rider/tasks
class RiderTasksResult {
  final List<RiderOrder> tasks;
  final int? activeOrderId;
  final String? reason; // offline | busy | no_location
  final double? radiusKm;

  const RiderTasksResult({required this.tasks, this.activeOrderId, this.reason, this.radiusKm});

  factory RiderTasksResult.fromJson(Map<String, dynamic> json) => RiderTasksResult(
        tasks: (json['tasks'] as List<dynamic>? ?? const [])
            .map((t) => RiderOrder.fromJson(Map<String, dynamic>.from(t)))
            .toList(),
        activeOrderId: toIntOrNull(json['activeOrderId']),
        reason: json['reason'],
        radiusKm: toDoubleOrNull(json['radiusKm']),
      );
}

/// GET /api/rider/profile
class RiderProfile {
  final bool isOnline;
  final String? vehicleType;
  final double? currentLat;
  final double? currentLng;
  final DateTime? lastLocationAt;
  final int? activeOrderId;

  const RiderProfile({
    required this.isOnline,
    this.vehicleType,
    this.currentLat,
    this.currentLng,
    this.lastLocationAt,
    this.activeOrderId,
  });

  factory RiderProfile.fromJson(Map<String, dynamic> json) => RiderProfile(
        isOnline: json['isOnline'] == true,
        vehicleType: json['vehicleType'],
        currentLat: toDoubleOrNull(json['currentLat']),
        currentLng: toDoubleOrNull(json['currentLng']),
        lastLocationAt: toDate(json['lastLocationAt']),
        activeOrderId: toIntOrNull(json['activeOrderId']),
      );
}

/// GET /api/rider/earnings
class RiderEarnings {
  final double today;
  final int todayCount;
  final double week;
  final int weekCount;
  final double allTime;
  final int allTimeCount;
  final double totalKm;
  final double walletBalance;
  final List<RiderOrder> recent;

  const RiderEarnings({
    this.today = 0,
    this.todayCount = 0,
    this.week = 0,
    this.weekCount = 0,
    this.allTime = 0,
    this.allTimeCount = 0,
    this.totalKm = 0,
    this.walletBalance = 0,
    this.recent = const [],
  });

  factory RiderEarnings.fromJson(Map<String, dynamic> json) => RiderEarnings(
        today: toDouble(json['today']),
        todayCount: toInt(json['todayCount']),
        week: toDouble(json['week']),
        weekCount: toInt(json['weekCount']),
        allTime: toDouble(json['allTime']),
        allTimeCount: toInt(json['allTimeCount']),
        totalKm: toDouble(json['totalKm']),
        walletBalance: toDouble(json['walletBalance']),
        recent: (json['recent'] as List<dynamic>? ?? const [])
            .map((o) => RiderOrder.fromJson(Map<String, dynamic>.from(o)))
            .toList(),
      );
}

/// POST /api/rider/orders/:id/deliver (FR04 payout breakdown)
class DeliveryResult {
  final int orderId;
  final double distanceKm;
  final String distanceSource; // gps | straight_line
  final double waitMinutes;
  final double payout;

  const DeliveryResult({
    required this.orderId,
    required this.distanceKm,
    required this.distanceSource,
    required this.waitMinutes,
    required this.payout,
  });

  factory DeliveryResult.fromJson(Map<String, dynamic> json) => DeliveryResult(
        orderId: toInt(json['orderId']),
        distanceKm: toDouble(json['distanceKm']),
        distanceSource: json['distanceSource'] ?? 'gps',
        waitMinutes: toDouble(json['waitMinutes']),
        payout: toDouble(json['payout']),
      );

  bool get isGps => distanceSource == 'gps';
}

/// Small formatting helpers shared by the rider screens
String rs(double v) => 'Rs. ${v.toStringAsFixed(v.truncateToDouble() == v ? 0 : 2)}';
String km(double? v) => v == null ? '—' : '${v.toStringAsFixed(v < 10 ? 2 : 1)} km';

String vehicleLabel(String? type) {
  switch (type) {
    case 'motorbike':
      return 'Motorbike';
    case 'bicycle':
      return 'Bicycle';
    case 'car':
      return 'Car';
    default:
      return 'Rider';
  }
}
