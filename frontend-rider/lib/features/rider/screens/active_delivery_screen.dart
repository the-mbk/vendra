// ══════════════════════════════════════════════════════════════
// Vendra Rider App - Active Delivery
// Map (store, customer pin + 200 m geofence, live rider position),
// store/customer details (tap a phone number to call), and one primary button that walks the
// delivery: Arrived at store → Picked up → On the way → Confirm delivery.
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

  Future<void> _onState(BuildContext context, DeliveryState state) async {
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
                      style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
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
            Text(t, style: GoogleFonts.poppins(fontSize: 10)),
          ]),
        );
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.9), borderRadius: BorderRadius.circular(8)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        item(AppColors.secondary, 'Store'),
        item(AppColors.success, 'Customer'),
        item(AppColors.primary, 'You'),
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
    return Row(
      children: [
        for (var i = 0; i < _labels.length; i++) ...[
          Expanded(
            child: Column(
              children: [
                Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    color: i <= current ? AppColors.primary : Colors.grey.shade300,
                    shape: BoxShape.circle,
                  ),
                  child: i <= current ? const Icon(Icons.check, size: 14, color: Colors.white) : null,
                ),
                const SizedBox(height: 4),
                Text(_labels[i],
                    textAlign: TextAlign.center,
                    style: GoogleFonts.poppins(
                        fontSize: 10,
                        fontWeight: i == current ? FontWeight.w700 : FontWeight.w400,
                        color: i <= current ? AppColors.textPrimary : AppColors.textLight)),
              ],
            ),
          ),
        ],
      ],
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
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)),
      child: Row(
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 8),
          Expanded(
              child: Text(text, style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w600, color: color))),
        ],
      ),
    );
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
                          fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 0.8, color: AppColors.textLight)),
                  Text(name, style: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w600)),
                  if (address != null)
                    Text(address!, style: GoogleFonts.poppins(fontSize: 12, color: AppColors.textSecondary)),
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
                  style: GoogleFonts.poppins(fontSize: 12, color: AppColors.textSecondary)),
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
