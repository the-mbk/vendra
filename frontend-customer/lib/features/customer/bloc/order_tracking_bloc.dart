// ══════════════════════════════════════════════════════════════
// Vendra App - Order Tracking BLoC (FR04/FR07)
// GET /api/customer/orders/:id/tracking → order + rider position + trip path.
// Live updates:
//   rider:location (this order) → move the rider marker, extend the path
//   order:update   (this order) → reload (status, rider, escrow changed)
// One order at a time: while this bloc is open it asks the server for this
// order's rider pings only (RealtimeService.trackOrder). Other active orders
// send nothing. Tracking pauses while the app is in the background and
// catches up (silent reload) when it comes back.
// ══════════════════════════════════════════════════════════════

import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:latlong2/latlong.dart';
import 'package:vendra_customer/vendra_core.dart';

// ── Events ──
abstract class OrderTrackingEvent extends Equatable {
  const OrderTrackingEvent();
  @override
  List<Object?> get props => [];
}

class LoadOrderTracking extends OrderTrackingEvent {
  final bool silent;
  const LoadOrderTracking({this.silent = false});
  @override
  List<Object?> get props => [silent];
}

/// The app went to the background (stop pings) or came back (resume and catch up)
class TrackingPaused extends OrderTrackingEvent {
  const TrackingPaused();
}

class TrackingResumed extends OrderTrackingEvent {
  const TrackingResumed();
}

class _RiderMoved extends OrderTrackingEvent {
  final RiderLocationEvent location;
  const _RiderMoved(this.location);
  @override
  List<Object?> get props => [location.lat, location.lng, location.at];
}

// ── State ──
class OrderTrackingState extends Equatable {
  final OrderModel? order;
  final LatLng? riderPosition;
  final DateTime? riderSeenAt;
  final List<LatLng> path;
  final bool loading;
  final String? error;

  const OrderTrackingState({
    this.order,
    this.riderPosition,
    this.riderSeenAt,
    this.path = const [],
    this.loading = false,
    this.error,
  });

  OrderTrackingState copyWith({
    OrderModel? order,
    LatLng? riderPosition,
    DateTime? riderSeenAt,
    List<LatLng>? path,
    bool? loading,
    String? error,
    bool clearError = false,
  }) {
    return OrderTrackingState(
      order: order ?? this.order,
      riderPosition: riderPosition ?? this.riderPosition,
      riderSeenAt: riderSeenAt ?? this.riderSeenAt,
      path: path ?? this.path,
      loading: loading ?? this.loading,
      error: clearError ? null : (error ?? this.error),
    );
  }

  @override
  List<Object?> get props => [
        order == null
            ? null
            : '${order!.status}:${order!.escrowStatus}:${order!.rider?.id}:${order!.latestDispute?.status}:'
                '${order!.latestDispute?.resolution}:${order!.escrowReleaseDueAt}',
        riderPosition,
        riderSeenAt,
        path.length,
        loading,
        error,
      ];
}

// ── BLoC ──
class OrderTrackingBloc extends Bloc<OrderTrackingEvent, OrderTrackingState> {
  final int orderId;
  final ApiService _api = ApiService();
  StreamSubscription<RiderLocationEvent>? _riderSub;
  StreamSubscription<OrderUpdateEvent>? _orderSub;

  OrderTrackingBloc({required this.orderId, OrderModel? initialOrder})
      : super(OrderTrackingState(order: initialOrder, loading: true)) {
    on<LoadOrderTracking>(_onLoad);
    on<_RiderMoved>(_onRiderMoved);
    on<TrackingPaused>((_, __) => RealtimeService().untrackOrder(orderId));
    on<TrackingResumed>((_, __) {
      RealtimeService().trackOrder(orderId);
      add(const LoadOrderTracking(silent: true));
    });

    RealtimeService().trackOrder(orderId);
    _riderSub = RealtimeService()
        .riderLocations
        .where((e) => e.orderId == orderId)
        .listen((e) => add(_RiderMoved(e)));
    _orderSub = RealtimeService()
        .orderUpdates
        .where((e) => e.orderId == orderId)
        .listen((_) => add(const LoadOrderTracking(silent: true)));
  }

  Future<void> _onLoad(LoadOrderTracking event, Emitter<OrderTrackingState> emit) async {
    if (!event.silent) emit(state.copyWith(loading: true, clearError: true));
    try {
      final res = await _api.get(ApiConfig.orderTracking(orderId));
      final data = Map<String, dynamic>.from(res.data['data'] as Map);
      final order = OrderModel.fromJson(Map<String, dynamic>.from(data['order'] as Map));

      LatLng? rider;
      DateTime? seenAt;
      final loc = data['riderLocation'];
      if (loc is Map) {
        rider = LatLng(toDouble(loc['lat']), toDouble(loc['lng']));
        seenAt = toDate(loc['at']);
      }
      final path = (data['path'] as List<dynamic>? ?? const [])
          .whereType<Map>()
          .map((p) => LatLng(toDouble(p['lat']), toDouble(p['lng'])))
          .toList();

      emit(OrderTrackingState(
        order: order,
        riderPosition: rider,
        riderSeenAt: seenAt,
        path: path,
      ));
    } catch (e) {
      emit(state.copyWith(loading: false, error: ApiService.getErrorMessage(e)));
    }
  }

  void _onRiderMoved(_RiderMoved event, Emitter<OrderTrackingState> emit) {
    final point = LatLng(event.location.lat, event.location.lng);
    emit(state.copyWith(
      riderPosition: point,
      riderSeenAt: event.location.at ?? DateTime.now(),
      path: [...state.path, point],
    ));
  }

  @override
  Future<void> close() {
    RealtimeService().untrackOrder(orderId);
    _riderSub?.cancel();
    _orderSub?.cancel();
    return super.close();
  }
}
