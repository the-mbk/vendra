// ══════════════════════════════════════════════════════════════
// Vendra Rider App - Rider models
// Shapes of /api/rider/tasks, /api/rider/orders, /api/rider/earnings
// and the deliver response. (Rider-only, so not in the shared core.)
// ══════════════════════════════════════════════════════════════

import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';
import 'package:vendra_rider/vendra_core.dart';

import 'payout_breakdown.dart';

export 'payout_breakdown.dart';

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

  /// The customer's note for the rider ("gate code 402"); only on accepted deliveries
  final String? deliveryNote;
  final double? customerLat;
  final double? customerLng;
  final int itemCount;

  /// Sum of the products' listed weights; [parcelWeightComplete] is false when
  /// some product has no weight listed (the class is then a lower bound)
  final int parcelWeightGrams;
  final bool parcelWeightComplete;
  final double totalAmount;
  final DateTime? readyAt;
  final DateTime? assignedAt;
  final DateTime? arrivedAt;
  final DateTime? pickedAt;
  final DateTime? deliveredAt;
  final double? distanceKm;
  final double? waitMinutes;
  final double payout;

  /// The payout slip (FR04); null for orders delivered before slips existed
  final PayoutBreakdown? payoutBreakdown;

  /// Delivering needs the customer's 4-digit handover code
  final bool otpRequired;

  /// 1–5 stars the customer gave the rider, once rated
  final int? customerRating;
  // Task-only fields
  final double? distanceToStoreKm;
  final double? tripDistanceKm;
  final double? estimatedPayout;
  final PayoutBreakdown? estimatedPayoutBreakdown;

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
    this.deliveryNote,
    this.customerLat,
    this.customerLng,
    this.itemCount = 0,
    this.parcelWeightGrams = 0,
    this.parcelWeightComplete = false,
    this.totalAmount = 0,
    this.readyAt,
    this.assignedAt,
    this.arrivedAt,
    this.pickedAt,
    this.deliveredAt,
    this.distanceKm,
    this.waitMinutes,
    this.payout = 0,
    this.payoutBreakdown,
    this.otpRequired = false,
    this.customerRating,
    this.distanceToStoreKm,
    this.tripDistanceKm,
    this.estimatedPayout,
    this.estimatedPayoutBreakdown,
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
        deliveryNote: json['deliveryNote'],
        customerLat: toDoubleOrNull(json['customerLat']),
        customerLng: toDoubleOrNull(json['customerLng']),
        itemCount: toInt(json['itemCount']),
        parcelWeightGrams: toInt(json['parcelWeightGrams']),
        parcelWeightComplete: json['parcelWeightComplete'] == true,
        totalAmount: toDouble(json['totalAmount']),
        readyAt: toDate(json['readyAt']),
        assignedAt: toDate(json['assignedAt']),
        arrivedAt: toDate(json['arrivedAt']),
        pickedAt: toDate(json['pickedAt']),
        deliveredAt: toDate(json['deliveredAt']),
        distanceKm: toDoubleOrNull(json['distanceKm']),
        waitMinutes: toDoubleOrNull(json['waitMinutes']),
        payout: toDouble(json['payout']),
        payoutBreakdown: PayoutBreakdown.tryParse(json['payoutBreakdown']),
        otpRequired: json['otpRequired'] == true,
        customerRating: toIntOrNull(json['customerRating']),
        distanceToStoreKm: toDoubleOrNull(json['distanceToStoreKm']),
        tripDistanceKm: toDoubleOrNull(json['tripDistanceKm']),
        estimatedPayout: toDoubleOrNull(json['estimatedPayout']),
        estimatedPayoutBreakdown: PayoutBreakdown.tryParse(json['estimatedPayoutBreakdown']),
      );

  LatLng? get storePoint => storeLat != null && storeLng != null ? LatLng(storeLat!, storeLng!) : null;
  LatLng? get customerPoint =>
      customerLat != null && customerLng != null ? LatLng(customerLat!, customerLng!) : null;

  ParcelClass get parcelClass {
    if (parcelWeightGrams <= 0) return ParcelClass.unknown;
    if (parcelWeightGrams > 8000) return ParcelClass.heavy;
    if (parcelWeightGrams >= 3000) return ParcelClass.medium;
    // Under 3 kg of listed weight but some items unlisted: can't call it standard
    return parcelWeightComplete ? ParcelClass.standard : ParcelClass.unknown;
  }

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

/// Parcel profile shown before a rider accepts (SRDS §2.4.3, PR 03)
enum ParcelClass {
  standard('Standard parcel', '< 3 kg'),
  medium('Medium / multi-bag', '3 – 8 kg'),
  heavy('Heavy / bulky', '> 8 kg'),
  unknown('Weight not listed', '');

  final String label;
  final String range;
  const ParcelClass(this.label, this.range);
}

/// GET /api/rider/tasks
class RiderTasksResult {
  final List<RiderOrder> tasks;
  final int? activeOrderId;
  final String? reason; // not_approved | offline | busy | no_location
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

/// GET /api/rider/profile (also the PUT /api/rider/documents response)
class RiderProfile {
  final bool isOnline;
  final String? vehicleType;
  final double? currentLat;
  final double? currentLng;
  final DateTime? lastLocationAt;
  final int? activeOrderId;

  /// pending | approved | rejected — an admin checks the documents first
  final String approvalStatus;
  final String? rejectionReason;
  final RiderDocuments documents;

  const RiderProfile({
    required this.isOnline,
    this.vehicleType,
    this.currentLat,
    this.currentLng,
    this.lastLocationAt,
    this.activeOrderId,
    this.approvalStatus = 'approved',
    this.rejectionReason,
    this.documents = const RiderDocuments(),
  });

  factory RiderProfile.fromJson(Map<String, dynamic> json) => RiderProfile(
        isOnline: json['isOnline'] == true,
        vehicleType: json['vehicleType'],
        currentLat: toDoubleOrNull(json['currentLat']),
        currentLng: toDoubleOrNull(json['currentLng']),
        lastLocationAt: toDate(json['lastLocationAt']),
        activeOrderId: toIntOrNull(json['activeOrderId']),
        // Older backends send no status: they had no approval step
        approvalStatus: json['approvalStatus'] ?? 'approved',
        rejectionReason: json['rejectionReason'],
        documents: RiderDocuments.fromJson(json),
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

  /// Average customer rating of the rider (1 decimal), null before the first rating
  final double? averageRating;
  final int ratingCount;
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
    this.averageRating,
    this.ratingCount = 0,
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
        averageRating: toDoubleOrNull(json['averageRating']),
        ratingCount: toInt(json['ratingCount']),
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
  final PayoutBreakdown? breakdown;

  const DeliveryResult({
    required this.orderId,
    required this.distanceKm,
    required this.distanceSource,
    required this.waitMinutes,
    required this.payout,
    this.breakdown,
  });

  factory DeliveryResult.fromJson(Map<String, dynamic> json) => DeliveryResult(
        orderId: toInt(json['orderId']),
        distanceKm: toDouble(json['distanceKm']),
        distanceSource: json['distanceSource'] ?? 'gps',
        waitMinutes: toDouble(json['waitMinutes']),
        payout: toDouble(json['payout']),
        breakdown: PayoutBreakdown.tryParse(json['payoutBreakdown']),
      );

  bool get isGps => distanceSource == 'gps';
}

/// Small formatting helpers shared by the rider screens
final _rsWhole = NumberFormat('#,##0', 'en_US');
final _rsCents = NumberFormat('#,##0.00', 'en_US');

/// "Rs. 4,041.76" (whole amounts drop the decimals: "Rs. 500")
String rs(double v) => 'Rs. ${(v.truncateToDouble() == v ? _rsWhole : _rsCents).format(v)}';
String km(double? v) => v == null ? '—' : '${v.toStringAsFixed(v < 10 ? 2 : 1)} km';

String vehicleLabel(String? type) {
  switch (type) {
    case 'motorcycle':
      return 'Motorcycle';
    case 'motorbike':
      return 'Motorbike';
    case 'scooter':
      return 'Scooter';
    case 'bicycle':
      return 'Bicycle';
    case 'car':
      return 'Car';
    default:
      return 'Rider';
  }
}
