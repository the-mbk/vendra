// ══════════════════════════════════════════════════════════════
// Vendra Rider App - Where the work is (demand map)
// For an online rider with no requests: nearby stores coloured by how
// busy they are today (GET /api/rider/demand): red = several orders in
// the last hour or deliveries already waiting for a rider, amber = some,
// green = quiet. Moving closer to a busy store means the next request
// arrives sooner. Refreshes every minute while shown.
// ══════════════════════════════════════════════════════════════

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:latlong2/latlong.dart';
import 'package:vendra_rider/vendra_core.dart';

import '../services/rider_location_service.dart';

class DemandZone {
  final String storeName;
  final LatLng point;
  final int ordersLastHour;
  final int ordersToday;
  final int waitingForRider;

  /// high | medium | low
  final String level;

  const DemandZone({
    required this.storeName,
    required this.point,
    required this.ordersLastHour,
    required this.ordersToday,
    required this.waitingForRider,
    required this.level,
  });

  factory DemandZone.fromJson(Map<String, dynamic> j) => DemandZone(
        storeName: j['storeName']?.toString() ?? 'Store',
        point: LatLng(toDouble(j['lat']), toDouble(j['lng'])),
        ordersLastHour: toInt(j['ordersLastHour']),
        ordersToday: toInt(j['ordersToday']),
        waitingForRider: toInt(j['waitingForRider']),
        level: j['level']?.toString() ?? 'low',
      );

  Color get color => switch (level) {
        'high' => AppColors.error,
        'medium' => AppColors.warning,
        _ => AppColors.success,
      };

  String get summary {
    final parts = <String>[
      '$ordersLastHour order${ordersLastHour == 1 ? '' : 's'} in the last hour',
      if (waitingForRider > 0) '$waitingForRider waiting for a rider',
    ];
    return parts.join(' · ');
  }
}

class DemandMapCard extends StatefulWidget {
  const DemandMapCard({super.key});

  @override
  State<DemandMapCard> createState() => _DemandMapCardState();
}

class _DemandMapCardState extends State<DemandMapCard> {
  List<DemandZone>? _zones;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _load();
    _timer = Timer.periodic(const Duration(minutes: 1), (_) => _load());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final res = await ApiService().get(ApiConfig.riderDemand);
      final zones = ((res.data['data'] as Map)['zones'] as List<dynamic>)
          .map((z) => DemandZone.fromJson(Map<String, dynamic>.from(z)))
          .toList();
      if (mounted) setState(() => _zones = zones);
    } catch (_) {
      // Optional card: keep the last zones (or stay hidden) when it can't load
    }
  }

  @override
  Widget build(BuildContext context) {
    final zones = _zones;
    if (zones == null || zones.isEmpty) return const SizedBox.shrink();
    final rider = RiderLocationService().position;
    final points = <LatLng>[for (final z in zones) z.point, if (rider != null) rider];

    return Container(
      margin: const EdgeInsets.only(top: 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.hairline),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Where the work is',
                    style: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                Text('Stores near you by orders today. Waiting closer to a busy one gets you the next request sooner.',
                    style: GoogleFonts.poppins(fontSize: 12, color: AppColors.textSecondary)),
              ],
            ),
          ),
          SizedBox(
            height: 200,
            child: FlutterMap(
              options: MapOptions(
                initialCameraFit: points.length > 1
                    ? CameraFit.coordinates(coordinates: points, padding: const EdgeInsets.all(36), maxZoom: 15)
                    : null,
                initialCenter: points.first,
                initialZoom: 14,
                interactionOptions: const InteractionOptions(flags: InteractiveFlag.pinchZoom | InteractiveFlag.drag),
              ),
              children: [
                MapTiles.layer(),
                CircleLayer(circles: [
                  for (final z in zones)
                    CircleMarker(
                      point: z.point,
                      radius: 250.0 + 120.0 * (z.ordersLastHour + 2 * z.waitingForRider).clamp(0, 6),
                      useRadiusInMeter: true,
                      color: z.color.withValues(alpha: 0.25),
                      borderColor: z.color,
                      borderStrokeWidth: 1.5,
                    ),
                ]),
                if (rider != null)
                  MarkerLayer(markers: [
                    Marker(
                      point: rider,
                      width: 28,
                      height: 28,
                      child: Container(
                        decoration: BoxDecoration(
                          color: AppColors.secondary,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 2),
                        ),
                        child: const Icon(AppIcons.rider, size: 15, color: Colors.white),
                      ),
                    ),
                  ]),
              ],
            ),
          ),
          for (final z in zones.take(3))
            ListTile(
              dense: true,
              leading: Icon(Icons.circle, size: 12, color: z.color),
              title: Text(z.storeName, style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w600)),
              subtitle: Text(z.summary, style: GoogleFonts.poppins(fontSize: 12, color: AppColors.textSecondary)),
            ),
        ],
      ),
    );
  }
}
