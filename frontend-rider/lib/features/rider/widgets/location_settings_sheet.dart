// ══════════════════════════════════════════════════════════════
// Vendra Rider App - Location settings sheet + status banner
// GPS status, and — only when the server runs in development
// (`features.manualLocation`) — the "Simulate location" mode where the
// rider taps a point on the map that is sent instead of GPS.
// ══════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';
import 'package:vendra_rider/vendra_core.dart';

import '../models/rider_models.dart';
import '../services/rider_location_service.dart';
import '../services/simulated_drive.dart';

/// Opens the location settings. Pass the active [order] to show its store and
/// customer pins and "jump to" shortcuts.
Future<void> showLocationSettings(BuildContext context, {RiderOrder? order}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (_) => LocationSettingsSheet(order: order),
  );
}

class LocationSettingsSheet extends StatefulWidget {
  final RiderOrder? order;
  const LocationSettingsSheet({super.key, this.order});

  @override
  State<LocationSettingsSheet> createState() => _LocationSettingsSheetState();
}

class _LocationSettingsSheetState extends State<LocationSettingsSheet> {
  final _service = RiderLocationService();
  int _mapVersion = 0; // bump to re-centre the picker after a "jump"

  void _jumpTo(LatLng p) {
    _service.setSimulatedPoint(p);
    setState(() => _mapVersion++);
  }

  @override
  Widget build(BuildContext context) {
    final order = widget.order;
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.85,
      maxChildSize: 0.95,
      builder: (context, scroll) => ListenableBuilder(
        listenable: Listenable.merge([_service, AppConfig.notifier]),
        builder: (context, _) {
          final allowed = _service.manualAllowed;
          final sim = _service.simulate;
          final drive = _service.drive;
          final point = _service.simulatedPoint ?? RiderLocationService.defaultPoint;
          return ListView(
            controller: scroll,
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)),
                ),
              ),
              const SizedBox(height: 16),
              Text('Location settings', style: GoogleFonts.poppins(fontSize: 20, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
              const SizedBox(height: 4),
              Text(
                _service.isTracking
                    ? 'Online — your location is sent every ${RiderLocationService.sendInterval.inSeconds} s'
                        '${_service.lastSentAt != null ? ' (last ${DateFormat('HH:mm:ss').format(_service.lastSentAt!)})' : ''}'
                    : 'Offline — location is not being shared',
                style: GoogleFonts.poppins(fontSize: 12, color: AppColors.textSecondary),
              ),
              const SizedBox(height: 12),
              if (allowed) ...[
                Container(
                  decoration: BoxDecoration(
                    color: sim ? AppColors.reservedAmber.withValues(alpha: 0.12) : AppColors.background,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: sim ? AppColors.reservedAmber : Colors.grey.shade300),
                  ),
                  child: SwitchListTile(
                    value: sim,
                    onChanged: (v) => _service.setSimulate(v),
                    activeThumbColor: AppColors.reservedAmber,
                    title: Text('Simulate location', style: GoogleFonts.poppins(fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                    subtitle: Text(
                      'Development only. For testing indoors or on web/desktop: tap the map to set where you are. '
                      'That point is sent instead of GPS.',
                      style: GoogleFonts.poppins(fontSize: 12, color: AppColors.textSecondary),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
              ],
              if (sim) ...[
                Text('Tap the map to move', style: GoogleFonts.poppins(fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                if (drive != null)
                  Text(
                    'Simulated drive in progress (${SimulatedDrive.formatDistance(drive.remainingMeters)} left) — '
                    'moving the point by hand stops it.',
                    style: GoogleFonts.poppins(fontSize: 12, color: AppColors.reservedAmber),
                  ),
                const SizedBox(height: 8),
                MapPickerWidget(
                  key: ValueKey(_mapVersion),
                  initialCenter: point,
                  initialZoom: 15,
                  height: 320,
                  onLocationSelected: _service.setSimulatedPoint,
                  markers: [
                    if (order?.storePoint != null)
                      MapMarkerData(
                        position: order!.storePoint!,
                        label: order.storeName ?? 'Store',
                        icon: Icons.storefront,
                        color: AppColors.secondary,
                      ),
                    if (order?.customerPoint != null)
                      MapMarkerData(
                        position: order!.customerPoint!,
                        label: order.customerName ?? 'Customer',
                        icon: Icons.home,
                        color: AppColors.success,
                      ),
                  ],
                ),
                if (order != null) ...[
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      if (order.storePoint != null)
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () => _jumpTo(order.storePoint!),
                            style: _compactButton,
                            icon: const Icon(Icons.storefront, size: 18),
                            label: const Text('At store'),
                          ),
                        ),
                      if (order.storePoint != null && order.customerPoint != null) const SizedBox(width: 10),
                      if (order.customerPoint != null)
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () => _jumpTo(order.customerPoint!),
                            style: _compactButton,
                            icon: const Icon(Icons.home, size: 18),
                            label: const Text('At customer'),
                          ),
                        ),
                    ],
                  ),
                ],
              ] else
                _GpsStatus(service: _service),
              if (_service.error != null && sim) ...[
                const SizedBox(height: 12),
                _ErrorBox(message: _service.error!),
              ],
            ],
          );
        },
      ),
    );
  }
}

final _compactButton = OutlinedButton.styleFrom(
  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
  textStyle: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w600),
);

class _GpsStatus extends StatelessWidget {
  final RiderLocationService service;
  const _GpsStatus({required this.service});

  @override
  Widget build(BuildContext context) {
    final p = service.gpsPoint;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(Icons.gps_fixed, color: p != null ? AppColors.success : AppColors.textLight),
          title: Text('Device GPS', style: GoogleFonts.poppins(fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
          subtitle: Text(
            p != null
                ? '${p.latitude.toStringAsFixed(5)}, ${p.longitude.toStringAsFixed(5)}'
                : 'No fix yet',
            style: GoogleFonts.poppins(fontSize: 12, color: AppColors.textSecondary),
          ),
        ),
        if (service.error != null) ...[
          _ErrorBox(message: service.error!),
          const SizedBox(height: 12),
        ],
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: service.retryGps,
                style: _compactButton,
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('Retry GPS', maxLines: 1),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: service.openSettings,
                style: _compactButton,
                icon: const Icon(Icons.settings, size: 18),
                label: const Text('App settings', maxLines: 1),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _ErrorBox extends StatelessWidget {
  final String message;
  const _ErrorBox({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.error.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.location_off, color: AppColors.error, size: 20),
          const SizedBox(width: 8),
          Expanded(child: Text(message, style: GoogleFonts.poppins(fontSize: 12, color: AppColors.error))),
        ],
      ),
    );
  }
}

/// Darker than reservedAmber so white text on the banner stays readable
const _bannerAmber = Color(0xFFB9650B);

/// Strip shown on the home and delivery screens: amber while simulating,
/// red when GPS is failing. Tap to open the settings sheet.
class LocationStatusBanner extends StatelessWidget {
  final RiderOrder? order;
  const LocationStatusBanner({super.key, this.order});

  @override
  Widget build(BuildContext context) {
    final service = RiderLocationService();
    return ListenableBuilder(
      listenable: Listenable.merge([service, AppConfig.notifier]),
      builder: (context, _) {
        final String text;
        final Color color;
        final IconData icon;
        final drive = service.drive;
        if (service.simulate && drive != null) {
          text = 'SIMULATED DRIVE · ${SimulatedDrive.formatDistance(drive.remainingMeters)} to the '
              '${drive.targetKind == DriveTarget.store ? 'store' : 'customer'} · ${SimulatedDrive.formatEta(drive.eta)}';
          color = _bannerAmber;
          icon = Icons.route;
        } else if (service.simulate) {
          final p = service.simulatedPoint;
          text = 'SIMULATED LOCATION${p != null ? ' · ${p.latitude.toStringAsFixed(4)}, ${p.longitude.toStringAsFixed(4)}' : ''}'
              ' — tap to change';
          color = _bannerAmber;
          icon = Icons.science_outlined;
        } else if (service.error != null) {
          text = service.error!;
          color = AppColors.error;
          icon = Icons.location_off;
        } else {
          return const SizedBox.shrink();
        }
        return Material(
          color: color,
          child: InkWell(
            onTap: () => showLocationSettings(context, order: order),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  Icon(icon, color: Colors.white, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      text,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.white),
                    ),
                  ),
                  const Icon(Icons.chevron_right, color: Colors.white, size: 18),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
