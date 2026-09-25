// ══════════════════════════════════════════════════════════════
// Order tracking (FR03/FR04/FR07/FR08)
// - Live map: store, the customer's drop-off pin, the rider's position
//   (rider:location events) and the trip path so far
// - Status timeline incl. ready_for_pickup (finding / assigned rider),
//   picked and on_the_way
// - Rider details, escrow state, dispute status / "Report an issue"
// - Self-pickup confirmations
// ══════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';

import 'package:vendra_customer/vendra_core.dart';
import '../../../config/app_routes.dart';
import '../bloc/order_bloc.dart';
import '../bloc/order_tracking_bloc.dart';
import '../widgets/order_status_widgets.dart';
import 'report_issue_screen.dart';

class OrderTrackingScreen extends StatelessWidget {
  final int orderId;

  /// Shown immediately while the tracking data loads (optional)
  final OrderModel? initialOrder;

  const OrderTrackingScreen({super.key, required this.orderId, this.initialOrder});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => OrderTrackingBloc(orderId: orderId, initialOrder: initialOrder)..add(const LoadOrderTracking()),
      child: const _OrderTrackingView(),
    );
  }
}

class _OrderTrackingView extends StatelessWidget {
  const _OrderTrackingView();

  static final _time = DateFormat('d MMM, h:mm a');

  @override
  Widget build(BuildContext context) {
    return BlocListener<OrderBloc, OrderState>(
      // After a pickup confirmation from this screen, reload tracking
      listenWhen: (_, c) => c is OrdersLoaded && c.feedback != null,
      listener: (context, _) => context.read<OrderTrackingBloc>().add(const LoadOrderTracking(silent: true)),
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          title: Text('Track Order', style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
          centerTitle: true,
          actions: [
            IconButton(
              tooltip: 'Refresh',
              icon: const Icon(Icons.refresh),
              onPressed: () => context.read<OrderTrackingBloc>().add(const LoadOrderTracking(silent: true)),
            ),
          ],
        ),
        body: BlocBuilder<OrderTrackingBloc, OrderTrackingState>(
          builder: (context, state) {
            final order = state.order;
            if (order == null) {
              if (state.error != null) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(state.error!, textAlign: TextAlign.center),
                        TextButton(
                          onPressed: () => context.read<OrderTrackingBloc>().add(const LoadOrderTracking()),
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  ),
                );
              }
              return const Center(child: CircularProgressIndicator(color: AppColors.primary));
            }

            return RefreshIndicator(
              color: AppColors.primary,
              onRefresh: () async => context.read<OrderTrackingBloc>().add(const LoadOrderTracking(silent: true)),
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                children: [
                  _header(order),
                  const SizedBox(height: 16),
                  if (_hasMap(order)) ...[
                    _TrackingMap(
                      store: _latLng(order.vendorLat, order.vendorLng),
                      customer: order.isDelivery ? _latLng(order.customerLat, order.customerLng) : null,
                      rider: _showRider(order) ? state.riderPosition : null,
                      path: _showRider(order) ? state.path : const [],
                      storeName: order.storeName,
                      enRoute: order.status == 'picked' || order.status == 'on_the_way',
                    ),
                    const SizedBox(height: 16),
                  ],
                  if (order.isDelivery && order.rider != null && order.status != 'cancelled') ...[
                    RiderInfoCard(rider: order.rider!, lastSeen: _showRider(order) ? state.riderSeenAt : null),
                    const SizedBox(height: 16),
                  ],
                  EscrowStatusCard(order: order),
                  const SizedBox(height: 16),
                  _timeline(order),
                  const SizedBox(height: 16),
                  _customerActions(context, order),
                  OrderDisputeSection(
                    order: order,
                    onReport: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => ReportIssueScreen(order: order)),
                    ).then((submitted) {
                      if (submitted == true && context.mounted) {
                        context.read<OrderTrackingBloc>().add(const LoadOrderTracking(silent: true));
                      }
                    }),
                    onViewDisputes: () => Navigator.pushNamed(context, AppRoutes.myDisputes),
                  ),
                  const SizedBox(height: 16),
                  _summary(order),
                  const SizedBox(height: 24),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  static LatLng? _latLng(double? lat, double? lng) => lat != null && lng != null ? LatLng(lat, lng) : null;

  static bool _hasMap(OrderModel o) =>
      o.status != 'cancelled' && (o.vendorLat != null || (o.isDelivery && o.customerLat != null));

  /// The rider's live position matters from assignment until delivery
  static bool _showRider(OrderModel o) =>
      o.isDelivery && o.rider != null && const ['ready_for_pickup', 'picked', 'on_the_way'].contains(o.status);

  String _timingLine(OrderModel o) {
    if (o.status == 'cancelled') return 'This order was cancelled and refunded';
    if (o.status == 'delivered') {
      return o.deliveredAt != null ? 'Delivered ${_time.format(o.deliveredAt!)}' : 'Delivered';
    }
    if (!o.isDelivery) return 'Collect from ${o.storeName ?? 'the store'} once it is ready';
    switch (o.status) {
      case 'on_the_way':
        return o.estimatedMinutes != null ? 'Arriving in about ${o.estimatedMinutes} min' : 'Your rider is on the way';
      case 'picked':
        return 'Rider has your order and is setting off';
      case 'ready_for_pickup':
        return o.rider == null ? 'Looking for a nearby rider…' : '${o.rider!.name ?? 'Rider'} is heading to the store';
      default:
        return o.estimatedMinutes != null
            ? 'About ${o.estimatedMinutes} min after the rider picks up'
            : 'The store is preparing your order';
    }
  }

  Widget _header(OrderModel order) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppColors.secondary, Color(0xFF1A6DB5)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text('Order Number', style: GoogleFonts.poppins(fontSize: 12, color: Colors.white70))),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(order.isDelivery ? Icons.local_shipping_outlined : Icons.storefront_outlined,
                        size: 14, color: Colors.white),
                    const SizedBox(width: 4),
                    Text(order.statusText,
                        style: GoogleFonts.poppins(fontSize: 11, color: Colors.white, fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '#VDR-${order.id.toString().padLeft(5, '0')}',
            style: GoogleFonts.poppins(fontSize: 28, fontWeight: FontWeight.w700, color: Colors.white),
          ),
          if (order.storeName != null)
            Text(order.storeName!, style: GoogleFonts.poppins(fontSize: 13, color: Colors.white70)),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                const Icon(Icons.schedule, size: 18, color: AppColors.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(_timingLine(order),
                      style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.white)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _timeline(OrderModel order) {
    if (order.status == 'cancelled') {
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: cardDecoration(),
        child: Row(
          children: [
            const Icon(Icons.cancel_outlined, color: AppColors.stockRed),
            const SizedBox(width: 12),
            Expanded(child: Text(order.statusText, style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w600))),
          ],
        ),
      );
    }

    String? at(DateTime? t) => t == null ? null : _time.format(t);
    final placedAt = order.createdAt != null ? DateTime.tryParse(order.createdAt!)?.toLocal() : null;

    final List<_TimelineStep> steps;
    final int current;
    if (order.isDelivery) {
      final riderName = order.rider?.name ?? 'Your rider';
      steps = [
        _TimelineStep('Order placed', at(placedAt) ?? 'Payment held in escrow.'),
        const _TimelineStep('Confirmed by store', 'The store accepted your order.'),
        const _TimelineStep('Packed', 'Your items are packed.'),
        order.rider == null
            ? const _TimelineStep('Finding a rider', 'Ready at the store — nearby riders have been notified.')
            : _TimelineStep('Rider assigned', '$riderName is heading to the store${order.assignedAt != null ? ' · ${at(order.assignedAt)}' : ''}.'),
        _TimelineStep('Picked up', at(order.pickedAt) ?? 'Rider collects your order from the store.'),
        const _TimelineStep('On the way', 'Rider is heading to your pin.'),
        _TimelineStep('Delivered', at(order.deliveredAt) ?? 'Rider confirms at your location.'),
      ];
      const index = {'pending': 0, 'confirmed': 1, 'packed': 2, 'ready_for_pickup': 3, 'picked': 4, 'on_the_way': 5};
      current = order.status == 'delivered' ? steps.length : (index[order.status] ?? 0);
    } else {
      steps = [
        _TimelineStep('Order placed', at(placedAt) ?? 'Payment held in escrow.'),
        const _TimelineStep('Confirmed by store', 'The store accepted your order.'),
        const _TimelineStep('Packed', 'Your items are packed.'),
        const _TimelineStep('Ready for pickup', 'Head to the store to collect your order.'),
        _TimelineStep('Collected', at(order.pickedAt) ?? 'Mark it once you have your bags.'),
        _TimelineStep('Received', at(order.deliveredAt) ?? 'Confirm you received everything.'),
      ];
      const index = {'pending': 0, 'confirmed': 1, 'packed': 2, 'ready_for_pickup': 3, 'picked': 5};
      current = order.status == 'delivered' ? steps.length : (index[order.status] ?? 0);
    }

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Progress', style: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w600)),
          const SizedBox(height: 12),
          for (var i = 0; i < steps.length; i++)
            _timelineRow(steps[i], done: i < current, active: i == current, isLast: i == steps.length - 1),
        ],
      ),
    );
  }

  Widget _timelineRow(_TimelineStep step, {required bool done, required bool active, required bool isLast}) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 32,
            child: Column(
              children: [
                Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    color: done ? AppColors.secondary : (active ? AppColors.primary : Colors.grey.shade200),
                    shape: BoxShape.circle,
                  ),
                  child: done
                      ? const Icon(Icons.check, color: Colors.white, size: 14)
                      : active
                          ? Container(
                              margin: const EdgeInsets.all(6),
                              decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                            )
                          : null,
                ),
                if (!isLast)
                  Expanded(
                    child: Container(width: 2, color: done ? AppColors.secondary : Colors.grey.shade200),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: isLast ? 0 : 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    step.title,
                    style: GoogleFonts.poppins(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: active ? AppColors.primary : (done ? AppColors.textPrimary : AppColors.textLight),
                    ),
                  ),
                  Text(step.subtitle, style: GoogleFonts.poppins(fontSize: 12, color: AppColors.textSecondary)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _customerActions(BuildContext context, OrderModel order) {
    if (order.isDelivery) return const SizedBox.shrink();
    if (order.status != 'ready_for_pickup' && order.status != 'picked') return const SizedBox.shrink();

    final bloc = context.read<OrderBloc>();
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(order.status == 'picked' ? 'Almost done' : 'Confirm pickup',
              style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          if (order.status == 'ready_for_pickup') ...[
            OutlinedButton.icon(
              onPressed: () => bloc.add(CustomerMarkPickedUp(orderId: order.id)),
              icon: const Icon(Icons.inventory_2_outlined),
              label: const Text('Mark as Picked Up'),
            ),
            const SizedBox(height: 8),
          ],
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.secondary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            onPressed: () => bloc.add(CustomerConfirmDelivered(orderId: order.id)),
            icon: const Icon(Icons.done_all),
            label: const Text('I received my order'),
          ),
        ],
      ),
    );
  }

  Widget _summary(OrderModel order) {
    Widget row(String label, String value, {bool bold = false}) => Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(label,
                  style: GoogleFonts.poppins(
                      fontSize: bold ? 15 : 13,
                      fontWeight: bold ? FontWeight.w600 : FontWeight.w400,
                      color: bold ? AppColors.textPrimary : AppColors.textSecondary)),
              Text(value,
                  style: GoogleFonts.poppins(
                      fontSize: bold ? 20 : 13,
                      fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
                      color: bold ? AppColors.primary : AppColors.textPrimary)),
            ],
          ),
        );

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Order summary', style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w600)),
          const SizedBox(height: 12),
          ...order.items.map((item) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text('${item.quantity}×',
                          style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.primary)),
                    ),
                    const SizedBox(width: 12),
                    Expanded(child: Text(item.productName ?? '', style: GoogleFonts.poppins(fontSize: 14))),
                    Text('Rs. ${item.total.toStringAsFixed(0)}',
                        style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w500)),
                  ],
                ),
              )),
          const Divider(height: 20),
          row('Subtotal', 'Rs. ${order.subtotal.toStringAsFixed(0)}'),
          row(order.isDelivery ? 'Delivery fee' : 'Self pickup',
              order.isDelivery ? 'Rs. ${order.deliveryFee.toStringAsFixed(0)}' : 'Free'),
          const Divider(height: 20),
          row('Total charged', 'Rs. ${order.totalAmount.toStringAsFixed(0)}', bold: true),
          if (order.isDelivery && order.deliveryAddress != null) ...[
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.place_outlined, size: 16, color: AppColors.textSecondary),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(order.deliveryAddress!,
                      style: GoogleFonts.poppins(fontSize: 12, color: AppColors.textSecondary)),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _TimelineStep {
  final String title;
  final String subtitle;
  const _TimelineStep(this.title, this.subtitle);
}

// ══════════════════════════════════════
// Live map: store · customer pin · rider + trip path
// ══════════════════════════════════════

class _TrackingMap extends StatefulWidget {
  final LatLng? store;
  final LatLng? customer;
  final LatLng? rider;
  final List<LatLng> path;
  final String? storeName;

  /// Rider has the parcel — draw the remaining leg rider → customer
  final bool enRoute;

  const _TrackingMap({
    required this.store,
    required this.customer,
    required this.rider,
    required this.path,
    required this.storeName,
    required this.enRoute,
  });

  @override
  State<_TrackingMap> createState() => _TrackingMapState();
}

class _TrackingMapState extends State<_TrackingMap> {
  final _controller = MapController();
  bool _mapReady = false;

  List<LatLng> get _points => [
        if (widget.store != null) widget.store!,
        if (widget.customer != null) widget.customer!,
        if (widget.rider != null) widget.rider!,
      ];

  CameraFit get _fit => CameraFit.coordinates(
        coordinates: _points,
        padding: const EdgeInsets.all(48),
        maxZoom: 16,
      );

  @override
  void didUpdateWidget(covariant _TrackingMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Bring the rider into view the first time a live position arrives
    if (oldWidget.rider == null && widget.rider != null && _mapReady) {
      _controller.fitCamera(_fit);
    }
  }

  @override
  Widget build(BuildContext context) {
    final points = _points;
    if (points.isEmpty) return const SizedBox.shrink();
    final legStart = widget.enRoute ? (widget.rider ?? widget.store) : widget.store;

    return Container(
      decoration: cardDecoration(),
      padding: const EdgeInsets.all(8),
      child: Column(
        children: [
          SizedBox(
            height: 260,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Stack(
                children: [
                  FlutterMap(
                    mapController: _controller,
                    options: MapOptions(
                      initialCenter: points.first,
                      initialZoom: 14,
                      initialCameraFit: points.length > 1 ? _fit : null,
                      onMapReady: () => _mapReady = true,
                    ),
                    children: [
                      TileLayer(
                        urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                        userAgentPackageName: 'com.vendra.app',
                      ),
                      PolylineLayer(
                        polylines: [
                          // Planned / remaining leg to the customer's pin
                          if (legStart != null && widget.customer != null)
                            Polyline(
                              points: [legStart, widget.customer!],
                              color: AppColors.secondary.withValues(alpha: 0.6),
                              strokeWidth: 3,
                              pattern: const StrokePattern.dotted(),
                            ),
                          // Where the rider has actually driven
                          if (widget.path.length > 1)
                            Polyline(points: widget.path, color: AppColors.primary, strokeWidth: 4),
                        ],
                      ),
                      MarkerLayer(
                        markers: [
                          if (widget.store != null)
                            _marker(widget.store!, Icons.storefront, AppColors.secondary, widget.storeName ?? 'Store'),
                          if (widget.customer != null)
                            _marker(widget.customer!, Icons.home_rounded, AppColors.pakistanGreen, 'Your drop-off pin'),
                          if (widget.rider != null)
                            _marker(widget.rider!, Icons.delivery_dining, AppColors.primary, 'Rider', large: true),
                        ],
                      ),
                    ],
                  ),
                  Positioned(
                    right: 8,
                    top: 8,
                    child: IconButton.filled(
                      tooltip: 'Show everything',
                      style: IconButton.styleFrom(backgroundColor: Colors.white, foregroundColor: AppColors.textPrimary),
                      onPressed: () {
                        if (_points.length > 1) {
                          _controller.fitCamera(_fit);
                        } else {
                          _controller.move(_points.first, 15);
                        }
                      },
                      icon: const Icon(Icons.center_focus_strong_outlined, size: 20),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 14,
            runSpacing: 4,
            alignment: WrapAlignment.center,
            children: [
              if (widget.store != null) _legend(Icons.storefront, AppColors.secondary, 'Store'),
              if (widget.customer != null) _legend(Icons.home_rounded, AppColors.pakistanGreen, 'You'),
              if (widget.rider != null) _legend(Icons.delivery_dining, AppColors.primary, 'Rider (live)'),
              if (widget.path.length > 1) _legend(Icons.timeline, AppColors.primary, 'Trip so far'),
            ],
          ),
        ],
      ),
    );
  }

  Marker _marker(LatLng point, IconData icon, Color color, String label, {bool large = false}) {
    final size = large ? 44.0 : 36.0;
    return Marker(
      point: point,
      width: size,
      height: size,
      child: Tooltip(
        message: label,
        child: Container(
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 2),
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.25), blurRadius: 6)],
          ),
          child: Icon(icon, color: Colors.white, size: size * 0.55),
        ),
      ),
    );
  }

  Widget _legend(IconData icon, Color color, String label) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Text(label, style: GoogleFonts.poppins(fontSize: 11, color: AppColors.textSecondary)),
        ],
      );
}
