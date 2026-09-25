// ══════════════════════════════════════════════════════════════
// Vendra Customer App - Public platform config (GET /api/public-config)
// Delivery fee, dispute window and geofence come from admin policies,
// so the app never hard-codes them. Loaded once and cached.
// ══════════════════════════════════════════════════════════════

import 'package:vendra_customer/vendra_core.dart';

class PublicConfig {
  final double deliveryFee;
  final int disputeWindowMinutes;
  final int geofenceMeters;

  const PublicConfig({
    required this.deliveryFee,
    required this.disputeWindowMinutes,
    required this.geofenceMeters,
  });

  factory PublicConfig.fromJson(Map<String, dynamic> json) => PublicConfig(
        deliveryFee: toDouble(json['deliveryFee']),
        disputeWindowMinutes: toInt(json['disputeWindowMinutes']),
        geofenceMeters: toInt(json['geofenceMeters'], 200),
      );
}

class PublicConfigService {
  PublicConfigService._();

  static PublicConfig? _cached;

  /// Returns the cached config, fetching it on first use (or when [refresh] is set)
  static Future<PublicConfig> load({bool refresh = false}) async {
    if (_cached != null && !refresh) return _cached!;
    final res = await ApiService().get(ApiConfig.publicConfig);
    _cached = PublicConfig.fromJson(Map<String, dynamic>.from(res.data['data'] as Map));
    return _cached!;
  }
}
