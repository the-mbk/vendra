// ══════════════════════════════════════════════════════════════
// Vendra Vendor App - Store location status
// Once a store is approved, moving it needs admin approval: the live
// location (what customers and riders see) stays put while a request
// is pending. Parsed from GET /api/auth/me and from the responses of
// PUT /api/vendor/location and DELETE /api/vendor/location/request.
// ══════════════════════════════════════════════════════════════

import 'package:latlong2/latlong.dart';
import 'package:vendra_vendor/vendra_core.dart';

/// A location change waiting for an admin
class PendingStoreLocation {
  final double latitude;
  final double longitude;
  final String? address;
  final DateTime? requestedAt;

  const PendingStoreLocation({
    required this.latitude,
    required this.longitude,
    this.address,
    this.requestedAt,
  });

  LatLng get point => LatLng(latitude, longitude);

  static PendingStoreLocation? fromJson(dynamic json) {
    if (json is! Map) return null;
    final lat = toDoubleOrNull(json['latitude']);
    final lng = toDoubleOrNull(json['longitude']);
    if (lat == null || lng == null) return null;
    final address = json['address']?.toString();
    return PendingStoreLocation(
      latitude: lat,
      longitude: lng,
      address: (address == null || address.trim().isEmpty) ? null : address,
      requestedAt: toDate(json['requestedAt']),
    );
  }
}

class StoreLocationStatus {
  /// Live location (null until the store sets one)
  final double? latitude;
  final double? longitude;
  final String? storeAddress;
  final bool isApproved;
  final PendingStoreLocation? pending;

  /// Why the admin rejected the most recent request (cleared by the next request or an approval)
  final String? rejectionReason;

  const StoreLocationStatus({
    this.latitude,
    this.longitude,
    this.storeAddress,
    this.isApproved = false,
    this.pending,
    this.rejectionReason,
  });

  bool get hasLocation => latitude != null && longitude != null;
  LatLng? get point => hasLocation ? LatLng(latitude!, longitude!) : null;
  bool get hasPending => pending != null;

  /// An approved store's move goes to the admin instead of applying immediately
  bool get changeNeedsApproval => isApproved;

  static String? _reason(dynamic v) {
    final s = v?.toString().trim();
    return (s == null || s.isEmpty) ? null : s;
  }

  /// From GET /api/auth/me (storeLat/storeLng are the live location)
  factory StoreLocationStatus.fromMe(Map<String, dynamic> json) {
    return StoreLocationStatus(
      latitude: toDoubleOrNull(json['storeLat']),
      longitude: toDoubleOrNull(json['storeLng']),
      storeAddress: json['storeAddress']?.toString(),
      isApproved: json['isApproved'] == true,
      pending: PendingStoreLocation.fromJson(json['pendingLocation']),
      rejectionReason: _reason(json['locationRejectionReason']),
    );
  }

  /// From PUT /api/vendor/location or DELETE /api/vendor/location/request
  /// (that payload has no approval flag, so the caller passes it on)
  factory StoreLocationStatus.fromLocationResponse(Map<String, dynamic> json, {required bool isApproved}) {
    return StoreLocationStatus(
      latitude: toDoubleOrNull(json['latitude']),
      longitude: toDoubleOrNull(json['longitude']),
      storeAddress: json['storeAddress']?.toString(),
      isApproved: isApproved,
      pending: PendingStoreLocation.fromJson(json['pendingLocation']),
      rejectionReason: _reason(json['locationRejectionReason']),
    );
  }
}

/// What the location screen returns when it pops after a save
class StoreLocationResult {
  /// true: the live location changed; false: sent to the admin for approval
  final bool applied;
  final String message;
  final StoreLocationStatus status;

  const StoreLocationResult({required this.applied, required this.message, required this.status});
}
