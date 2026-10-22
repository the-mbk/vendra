// ══════════════════════════════════════════════════════════════
// Vendra Rider App - Active Delivery
// Map (store, customer pin + 200 m geofence, live rider position),
// store/customer details (tap a phone number to call), and one primary button that walks the
// delivery: Arrived at store → Picked up → On the way → Confirm delivery.
// In development (`features.manualLocation`) a "Simulate drive" card moves
// the simulated position to the store / customer, one ping every 10 s.
// ══════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:latlong2/latlong.dart';
import 'package:vendra_rider/vendra_core.dart';

import '../bloc/delivery_bloc.dart';
import '../models/rider_models.dart';
import '../services/rider_location_service.dart';
import '../services/simulated_drive.dart';
import '../widgets/location_settings_sheet.dart';
import '../widgets/payout_summary_dialog.dart';

class ActiveDeliveryScreen extends StatefulWidget {
  const ActiveDeliveryScreen({super.key});

  @override
  State<ActiveDeliveryScreen> createState() => _ActiveDeliveryScreenState();
}

class _ActiveDeliveryScreenState extends State<ActiveDeliveryScreen> {
  int _handledMessageId = 0;
  bool _resultShown = false;

  @override
  void dispose() {
    // Leaving the delivery ends any simulated drive
    RiderLocationService().stopDrive();
    super.dispose();
  }

  /// Stops a simulated drive that no longer fits: the delivery ended, or it
  /// moved on (e.g. picked up while still driving to the store)
  void _checkDrive(DeliveryState state) {
    final location = RiderLocationService();
    final drive = location.drive;
    if (drive == null) return;
    final order = state.order;
    final step = order?.step;
    final stillValid = order != null &&
        state.result == null &&
        drive.orderId == order.id &&
        step != DeliveryStep.delivered &&
        step != DeliveryStep.closed &&
        drive.targetKind == _driveTargetFor(order);
    if (!stillValid) location.stopDrive();
  }

  Future<void> _onState(BuildContext context, DeliveryState state) async {
    _checkDrive(state);
    final m = state.message;
    if (m != null && m.id != _handledMessageId) {
      _handledMessageId = m.id;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
          content: Text(m.text),
          backgroundColor: m.isError ? AppColors.error : AppColors.success,
          behavior: SnackBarBehavior.floating,
          duration: Duration(seconds: m.isError ? 5 : 3),
        ));
    }
    final result = state.result;
    if (result != null && !_resultShown) {
      _resultShown = true;
      await showPayoutSummary(context, result);
      if (context.mounted) Navigator.of(context).pop(true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<DeliveryBloc, DeliveryState>(
      listener: _onState,
      builder: (context, state) {
        final order = state.order;
        return Scaffold(
          backgroundColor: AppColors.background,
          appBar: AppBar(
            title: Text(order != null ? 'Delivery #${order.id}' : 'Delivery'),
            actions: [
              IconButton(
                tooltip: 'Location settings',
                icon: const Icon(Icons.my_location),
                onPressed: () => showLocationSettings(context, order: order),
              ),
            ],
          ),
          body: _body(context, state),
        );
      },
    );
  }

  Widget _body(BuildContext context, DeliveryState state) {
    if (state.loading && state.order == null) {
      return const Center(child: CircularProgressIndicator());
    }
    final order = state.order;
    if (order == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(state.loadError != null ? Icons.cloud_off : Icons.inventory_2_outlined,
                  size: 56, color: AppColors.textLight),
              const SizedBox(height: 12),
              Text(state.loadError ?? 'No active delivery. It may have been completed or cancelled.',
                  textAlign: TextAlign.center, style: GoogleFonts.poppins(color: AppColors.textSecondary)),
              const SizedBox(height: 20),
              if (state.loadError != null)
                VendraButton(
                  text: 'Retry',
                  onPressed: () => context.read<DeliveryBloc>().add(const DeliveryLoadRequested()),
                )
              else
                VendraButton(text: 'Back to home', onPressed: () => Navigator.of(context).pop(true)),
            ],
          ),
        ),
      );
    }

    return Column(
      children: [
        LocationStatusBanner(order: order),
        Expanded(flex: 5, child: _DeliveryMap(order: order, geofenceMeters: state.geofenceMeters)),
        Expanded(
          flex: 6,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            children: [
              _StepProgress(step: order.step),
              const SizedBox(height: 12),
              _ProximityHint(order: order, geofenceMeters: state.geofenceMeters),
              const SizedBox(height: 12),
              _SimulatedDriveCard(order: order),
              _PartyCard(
                icon: Icons.storefront,
                color: AppColors.secondary,
                label: 'PICKUP',
                name: order.storeName ?? 'Store',
                address: order.storeAddress,
                phone: order.storePhone,
              ),
              _PartyCard(
                icon: Icons.home,
                color: AppColors.success,
                label: 'DROP-OFF',
                name: order.customerName ?? 'Customer',
                address: order.deliveryAddress,
                phone: order.customerPhone,
              ),
              Card(
                child: ListTile(
                  leading: const Icon(Icons.shopping_bag_outlined, color: AppColors.primary),
                  title: Text('${order.itemCount} item${order.itemCount == 1 ? '' : 's'}',
                      style: GoogleFonts.poppins(fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                  subtitle: Text('Order total ${rs(order.totalAmount)} · paid online (escrow)',
                      style: GoogleFonts.poppins(fontSize: 12, color: AppColors.textSecondary)),
                ),
              ),
            ],
          ),
        ),
        _PrimaryAction(order: order, busy: state.busy),
      ],
    );
  }
}

// ── Map ──────────────────────────────────────────────────────

class _DeliveryMap extends StatefulWidget {
  final RiderOrder order;
  final double geofenceMeters;
  const _DeliveryMap({required this.order, required this.geofenceMeters});

  @override
  State<_DeliveryMap> createState() => _DeliveryMapState();
}

class _DeliveryMapState extends State<_DeliveryMap> {
  final _controller = MapController();
  final _location = RiderLocationService();

  List<LatLng> _points() => [
        if (widget.order.storePoint != null) widget.order.storePoint!,
        if (widget.order.customerPoint != null) widget.order.customerPoint!,
        if (_location.position != null) _location.position!,
      ];

  void _fit() {
    final pts = _points();
    if (pts.isEmpty) return;
    _controller.fitCamera(CameraFit.coordinates(
      coordinates: pts,
      padding: const EdgeInsets.all(48),
      maxZoom: 17,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final order = widget.order;
    final pts = _points();
    final target = order.step.index <= DeliveryStep.atStore.index ? order.storePoint : order.customerPoint;

    return Stack(
      children: [
        ListenableBuilder(
          listenable: _location,
          builder: (context, _) {
            final rider = _location.position;
            return FlutterMap(
              mapController: _controller,
              options: MapOptions(
                initialCameraFit: pts.isEmpty
                    ? null
                    : CameraFit.coordinates(coordinates: pts, padding: const EdgeInsets.all(48), maxZoom: 17),
                initialCenter: pts.isEmpty ? RiderLocationService.defaultPoint : pts.first,
                initialZoom: 14,
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.vendra.rider',
                ),
                if (order.customerPoint != null)
                  CircleLayer(circles: [
                    CircleMarker(
                      point: order.customerPoint!,
                      radius: widget.geofenceMeters,
                      useRadiusInMeter: true,
                      color: AppColors.success.withValues(alpha: 0.12),
                      borderColor: AppColors.success,
                      borderStrokeWidth: 1.5,
                    ),
                  ]),
                if (rider != null && target != null)
                  PolylineLayer(polylines: [
                    Polyline(points: [rider, target], strokeWidth: 3, color: AppColors.primary.withValues(alpha: 0.6)),
                  ]),
                MarkerLayer(markers: [
                  if (order.storePoint != null)
                    Marker(
                      point: order.storePoint!,
                      width: 44,
                      height: 44,
                      child: const _Pin(icon: Icons.storefront, color: AppColors.secondary),
                    ),
                  if (order.customerPoint != null)
                    Marker(
                      point: order.customerPoint!,
                      width: 44,
                      height: 44,
                      child: const _Pin(icon: Icons.home, color: AppColors.success),
                    ),
                  if (rider != null)
                    Marker(
                      point: rider,
                      width: 44,
                      height: 44,
                      child: _Pin(
                        icon: Icons.two_wheeler,
                        color: _location.simulate ? AppColors.reservedAmber : AppColors.primary,
                      ),
                    ),
                ]),
              ],
            );
          },
        ),
        Positioned(
          right: 12,
          bottom: 12,
          child: FloatingActionButton.small(
            heroTag: 'fit',
            backgroundColor: Colors.white,
            foregroundColor: AppColors.textPrimary,
            onPressed: _fit,
            child: const Icon(Icons.center_focus_strong),
          ),
        ),
        const Positioned(left: 8, bottom: 8, child: _MapLegend()),
      ],
    );
  }
}

class _Pin extends StatelessWidget {
  final IconData icon;
  final Color color;
  const _Pin({required this.icon, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 3),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.25), blurRadius: 6)],
      ),
      child: Icon(icon, color: Colors.white, size: 20),
    );
  }
}

class _MapLegend extends StatelessWidget {
  const _MapLegend();

  @override
  Widget build(BuildContext context) {
    Widget item(Color c, String t) => Padding(
          padding: const EdgeInsets.only(right: 8),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Container(width: 8, height: 8, decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
            const SizedBox(width: 4),
            Text(t, style: GoogleFonts.poppins(fontSize: 11, fontWeight: FontWeight.w500, color: AppColors.textPrimary)),
          ]),
        );
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.12), blurRadius: 6)],
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        item(AppColors.secondary, 'Store'),
        item(AppColors.success, 'Customer'),
        item(RiderLocationService().simulate ? AppColors.reservedAmber : AppColors.primary, 'You'),
      ]),
    );
  }
}

// ── Details ──────────────────────────────────────────────────

class _StepProgress extends StatelessWidget {
  final DeliveryStep step;
  const _StepProgress({required this.step});

  static const _labels = ['Accepted', 'At store', 'Picked up', 'On the way', 'Delivered'];

  @override
  Widget build(BuildContext context) {
    // headingToStore=0 → "Accepted" done; atStore=1; pickedUp=2; onTheWay=3; delivered=4
    final current = step == DeliveryStep.closed ? 0 : step.index;
    Color lineColor(int i) => i <= current ? AppColors.primary : Colors.grey.shade300;
    return Container(
      padding: const EdgeInsets.fromLTRB(4, 14, 4, 12),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < _labels.length; i++)
            Expanded(
              child: Column(
                children: [
                  SizedBox(
                    height: 28,
                    child: Row(
                      children: [
                        // Connector into this step (none before the first)
                        Expanded(
                            child: Container(height: 3, color: i == 0 ? Colors.transparent : lineColor(i))),
                        Container(
                          width: 26,
                          height: 26,
                          decoration: BoxDecoration(
                            color: i <= current ? AppColors.primary : Colors.white,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: i <= current ? AppColors.primary : Colors.grey.shade300,
                              width: 2,
                            ),
                            boxShadow: i == current
                                ? [BoxShadow(color: AppColors.primary.withValues(alpha: 0.35), blurRadius: 8)]
                                : null,
                          ),
                          child: i <= current
                              ? const Icon(Icons.check, size: 15, color: Colors.white)
                              : Center(
                                  child: Text('${i + 1}',
                                      style: GoogleFonts.poppins(
                                          fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.textLight)),
                                ),
                        ),
                        Expanded(
                          child: Container(
                            height: 3,
                            color: i == _labels.length - 1 ? Colors.transparent : lineColor(i + 1),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(_labels[i],
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.poppins(
                          fontSize: 11,
                          fontWeight: i == current ? FontWeight.w700 : FontWeight.w500,
                          color: i == current
                              ? AppColors.primary
                              : i < current
                                  ? AppColors.textPrimary
                                  : AppColors.textLight)),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Live distance from the rider to the next stop (and the geofence check)
class _ProximityHint extends StatelessWidget {
  final RiderOrder order;
  final double geofenceMeters;
  const _ProximityHint({required this.order, required this.geofenceMeters});

  @override
  Widget build(BuildContext context) {
    final location = RiderLocationService();
    return ListenableBuilder(
      listenable: location,
      builder: (context, _) {
        final rider = location.position;
        final toStore = order.step.index <= DeliveryStep.atStore.index;
        final target = toStore ? order.storePoint : order.customerPoint;
        if (rider == null || target == null) {
          return _hint(Icons.gps_not_fixed, AppColors.textSecondary, 'Waiting for your location…');
        }
        final meters = const Distance().as(LengthUnit.Meter, rider, target);
        final dist = meters >= 1000 ? '${(meters / 1000).toStringAsFixed(2)} km' : '${meters.round()} m';
        if (toStore) {
          return _hint(Icons.storefront, AppColors.secondary, '$dist from the store');
        }
        final inside = meters <= geofenceMeters;
        return _hint(
          inside ? Icons.verified : Icons.near_me,
          inside ? AppColors.success : AppColors.reservedAmber,
          inside
              ? 'Within ${geofenceMeters.round()} m of the customer — you can confirm delivery'
              : '$dist from the customer · confirm within ${geofenceMeters.round()} m',
        );
      },
    );
  }

  Widget _hint(IconData icon, Color color, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            child: Icon(icon, color: Colors.white, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
              child: Text(text,
                  style: GoogleFonts.poppins(
                      fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.textPrimary, height: 1.3))),
        ],
      ),
    );
  }
}

/// Store before pickup, customer after
DriveTarget _driveTargetFor(RiderOrder order) =>
    order.step.index <= DeliveryStep.atStore.index ? DriveTarget.store : DriveTarget.customer;

/// Development only: drive the simulated position to the next stop in a
/// straight line, one location ping every 10 s (so the trip is recorded).
class _SimulatedDriveCard extends StatelessWidget {
  final RiderOrder order;
  const _SimulatedDriveCard({required this.order});

  void _start(BuildContext context, LatLng target, DriveTarget kind, {required bool fast}) {
    final location = RiderLocationService();
    final started = location.startDrive(target: target, targetKind: kind, orderId: order.id, fast: fast);
    if (!started) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
          content: Text(location.driveBlocker ??
              'You are already at the ${kind == DriveTarget.store ? 'store' : 'customer'}.'),
          behavior: SnackBarBehavior.floating,
        ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final location = RiderLocationService();
    return ListenableBuilder(
      listenable: Listenable.merge([location, AppConfig.notifier]),
      builder: (context, _) {
        final step = order.step;
        if (!location.manualAllowed || step == DeliveryStep.delivered || step == DeliveryStep.closed) {
          return const SizedBox.shrink();
        }
        final kind = _driveTargetFor(order);
        final target = kind == DriveTarget.store ? order.storePoint : order.customerPoint;
        if (target == null) return const SizedBox.shrink();
        final place = kind == DriveTarget.store ? 'store' : 'customer';
        final drive = location.drive;
        final driving = drive != null && drive.orderId == order.id;

        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          decoration: BoxDecoration(
            color: AppColors.reservedAmber.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.reservedAmber.withValues(alpha: 0.6)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Icon(Icons.route, color: AppColors.reservedAmber, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text('Simulate drive to the $place',
                        style: GoogleFonts.poppins(
                            fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                  ),
                  Text('DEV',
                      style: GoogleFonts.poppins(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1,
                          color: AppColors.reservedAmber)),
                ],
              ),
              const SizedBox(height: 6),
              if (driving) ..._driving(location, drive, place) else ..._idle(context, location, target, kind),
            ],
          ),
        );
      },
    );
  }

  List<Widget> _driving(RiderLocationService location, SimulatedDrive drive, String place) {
    return [
      Text(
        '${SimulatedDrive.formatDistance(drive.remainingMeters)} to the $place · '
        '${SimulatedDrive.formatEta(drive.eta)} · ${drive.speedKmh.round()} km/h',
        style: GoogleFonts.poppins(fontSize: 12, color: AppColors.textSecondary),
      ),
      const SizedBox(height: 8),
      ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: LinearProgressIndicator(
          value: drive.progress,
          minHeight: 6,
          color: AppColors.reservedAmber,
          backgroundColor: AppColors.reservedAmber.withValues(alpha: 0.2),
        ),
      ),
      const SizedBox(height: 8),
      Row(
        children: [
          FilterChip(
            label: Text('Fast ×${SimulatedDrive.fastMultiplier}', style: GoogleFonts.poppins(fontSize: 12)),
            avatar: const Icon(Icons.fast_forward, size: 16),
            selected: drive.fast,
            showCheckmark: false,
            onSelected: location.setDriveFast,
          ),
          const Spacer(),
          OutlinedButton.icon(
            onPressed: location.stopDrive,
            icon: const Icon(Icons.stop, size: 18),
            label: const Text('Stop'),
            style: OutlinedButton.styleFrom(foregroundColor: AppColors.error),
          ),
        ],
      ),
    ];
  }

  List<Widget> _idle(BuildContext context, RiderLocationService location, LatLng target, DriveTarget kind) {
    final blocker = location.driveBlocker;
    final payoutNote = kind == DriveTarget.store
        ? 'The ride to the store is not part of the payout.'
        : 'This distance counts toward your payout.';
    return [
      Text(
        blocker ??
            'Moves your simulated position in a straight line, sending it every '
                '${RiderLocationService.sendInterval.inSeconds} s. $payoutNote',
        style: GoogleFonts.poppins(fontSize: 12, color: AppColors.textSecondary),
      ),
      const SizedBox(height: 8),
      if (!location.simulate)
        OutlinedButton.icon(
          onPressed: () => location.setSimulate(true),
          icon: const Icon(Icons.science_outlined, size: 18),
          label: const Text('Use simulated location'),
        )
      else
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: blocker == null ? () => _start(context, target, kind, fast: false) : null,
                icon: const Icon(Icons.play_arrow, size: 18),
                label: Text('${SimulatedDrive.normalKmh.round()} km/h'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: blocker == null ? () => _start(context, target, kind, fast: true) : null,
                icon: const Icon(Icons.fast_forward, size: 18),
                label: const Text('Fast ×${SimulatedDrive.fastMultiplier}'),
              ),
            ),
          ],
        ),
    ];
  }
}

class _PartyCard extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final String name;
  final String? address;
  final String? phone;

  const _PartyCard({
    required this.icon,
    required this.color,
    required this.label,
    required this.name,
    this.address,
    this.phone,
  });

  @override
  Widget build(BuildContext context) {
    final hasPhone = phone != null && phone!.trim().isNotEmpty;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(backgroundColor: color.withValues(alpha: 0.12), child: Icon(icon, color: color, size: 20)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: GoogleFonts.poppins(
                          fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 0.8, color: color)),
                  Text(name,
                      style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                  if (address != null)
                    Text(address!, style: GoogleFonts.poppins(fontSize: 13, color: AppColors.textSecondary)),
                  if (hasPhone) ...[
                    const SizedBox(height: 4),
                    // Tap the number to call (copied instead where calling isn't available)
                    InkWell(
                      onTap: () => ContactLauncher.call(context, phone),
                      borderRadius: BorderRadius.circular(6),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.phone, size: 14, color: AppColors.secondary),
                            const SizedBox(width: 4),
                            Text(phone!,
                                style: GoogleFonts.poppins(
                                    fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.secondary)),
                          ],
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (hasPhone)
              IconButton.filledTonal(
                tooltip: 'Call $name',
                icon: const Icon(Icons.call, size: 20),
                color: color,
                onPressed: () => ContactLauncher.call(context, phone),
              ),
          ],
        ),
      ),
    );
  }
}

class _PrimaryAction extends StatelessWidget {
  final RiderOrder order;
  final bool busy;
  const _PrimaryAction({required this.order, required this.busy});

  @override
  Widget build(BuildContext context) {
    final (String label, IconData icon, String hint) = switch (order.step) {
      DeliveryStep.headingToStore => ('Arrived at store', Icons.storefront, 'Tap when you reach the store.'),
      DeliveryStep.atStore => ('Picked up', Icons.inventory_2, 'Collect the order, then tap Picked up.'),
      DeliveryStep.pickedUp => ('On the way', Icons.delivery_dining, 'Start the trip to the customer.'),
      DeliveryStep.onTheWay => (
          'Confirm delivery',
          Icons.check_circle,
          'Hand over the order. Your location is checked against the customer pin.'
        ),
      DeliveryStep.delivered => ('Delivered', Icons.check, 'This delivery is complete.'),
      DeliveryStep.closed => ('Closed', Icons.block, 'This order is ${order.statusText.toLowerCase()}.'),
    };
    final enabled = order.step != DeliveryStep.delivered && order.step != DeliveryStep.closed;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 12, offset: const Offset(0, -2))],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(hint,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w500, color: AppColors.textSecondary)),
              const SizedBox(height: 8),
              VendraButton(
                text: label,
                icon: icon,
                isLoading: busy,
                onPressed: enabled ? () => context.read<DeliveryBloc>().add(DeliveryAdvanceRequested()) : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
