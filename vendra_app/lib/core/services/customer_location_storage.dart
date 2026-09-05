// ══════════════════════════════════════════════════════════════
// Persisted default delivery location & address line for checkout
// ══════════════════════════════════════════════════════════════

import 'package:shared_preferences/shared_preferences.dart';

class CustomerLocationStorage {
  static const _kLat = 'customer_default_lat';
  static const _kLng = 'customer_default_lng';
  static const _kName = 'customer_default_location_name';
  static const _kAddressLine = 'customer_delivery_address_line';

  static const double defaultLat = 33.6844;
  static const double defaultLng = 73.0479;
  static const String defaultName = 'Islamabad, Pakistan';

  static Future<void> save({
    required double latitude,
    required double longitude,
    required String locationName,
    String? addressLine,
  }) async {
    final p = await SharedPreferences.getInstance();
    await p.setDouble(_kLat, latitude);
    await p.setDouble(_kLng, longitude);
    await p.setString(_kName, locationName);
    if (addressLine != null) {
      await p.setString(_kAddressLine, addressLine);
    }
  }

  static Future<void> saveAddressLineOnly(String addressLine) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_kAddressLine, addressLine);
  }

  static Future<CustomerDeliverySnapshot> loadSnapshot() async {
    final p = await SharedPreferences.getInstance();
    final lat = p.getDouble(_kLat) ?? defaultLat;
    final lng = p.getDouble(_kLng) ?? defaultLng;
    final name = p.getString(_kName) ?? defaultName;
    final addressLine = p.getString(_kAddressLine);
    return CustomerDeliverySnapshot(
      lat: lat,
      lng: lng,
      locationLabel: name,
      addressLine: addressLine?.isNotEmpty == true ? addressLine : null,
    );
  }

  /// Legacy tuple-style load for screens that only need map coords + label
  static Future<({double lat, double lng, String name})> load() async {
    final s = await loadSnapshot();
    return (lat: s.lat, lng: s.lng, name: s.locationLabel);
  }
}

class CustomerDeliverySnapshot {
  final double lat;
  final double lng;
  final String locationLabel;
  final String? addressLine;

  const CustomerDeliverySnapshot({
    required this.lat,
    required this.lng,
    required this.locationLabel,
    this.addressLine,
  });

  /// Human-readable default for delivery address field
  String get defaultAddressText =>
      addressLine?.trim().isNotEmpty == true ? addressLine!.trim() : locationLabel;
}
