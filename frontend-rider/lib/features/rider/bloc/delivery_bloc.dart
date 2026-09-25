// ══════════════════════════════════════════════════════════════
// Vendra Rider App - Active Delivery BLoC
// Walks the delivery: arrived at store → picked up → on the way →
// confirm delivery (geofenced, SSR02). The deliver response carries
// the GPS-based payout breakdown (FR04); escrow release starts (FR03).
// ══════════════════════════════════════════════════════════════

import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:latlong2/latlong.dart';
import 'package:vendra_rider/vendra_core.dart';

import '../models/rider_models.dart';
import '../services/rider_location_service.dart';

// ── Events ───────────────────────────────────────────────────

abstract class DeliveryEvent extends Equatable {
  const DeliveryEvent();
  @override
  List<Object?> get props => [];
}

/// Load the rider's active delivery (optionally a specific order id)
class DeliveryLoadRequested extends DeliveryEvent {
  final int? orderId;
  const DeliveryLoadRequested({this.orderId});
  @override
  List<Object?> get props => [orderId];
}

/// The single primary button: performs the next step
class DeliveryAdvanceRequested extends DeliveryEvent {}

// ── State ────────────────────────────────────────────────────

class DeliveryMessage {
  final int id;
  final String text;
  final bool isError;
  const DeliveryMessage(this.id, this.text, {this.isError = false});
}

class DeliveryState extends Equatable {
  final bool loading;
  final String? loadError;
  final RiderOrder? order;
  final bool busy;
  final double geofenceMeters;
  final DeliveryMessage? message;
  final DeliveryResult? result;

  const DeliveryState({
    this.loading = true,
    this.loadError,
    this.order,
    this.busy = false,
    this.geofenceMeters = 200,
    this.message,
    this.result,
  });

  DeliveryState copyWith({
    bool? loading,
    String? loadError,
    bool clearLoadError = false,
    RiderOrder? order,
    bool clearOrder = false,
    bool? busy,
    double? geofenceMeters,
    DeliveryMessage? message,
    DeliveryResult? result,
  }) {
    return DeliveryState(
      loading: loading ?? this.loading,
      loadError: clearLoadError ? null : (loadError ?? this.loadError),
      order: clearOrder ? null : (order ?? this.order),
      busy: busy ?? this.busy,
      geofenceMeters: geofenceMeters ?? this.geofenceMeters,
      message: message ?? this.message,
      result: result ?? this.result,
    );
  }

  @override
  List<Object?> get props => [
        loading,
        loadError,
        order?.id,
        order?.status,
        order?.arrivedAt,
        busy,
        geofenceMeters,
        message?.id,
        result?.orderId,
      ];
}

// ── BLoC ─────────────────────────────────────────────────────

class DeliveryBloc extends Bloc<DeliveryEvent, DeliveryState> {
  final ApiService _api = ApiService();
  final RiderLocationService _location = RiderLocationService();
  StreamSubscription<OrderUpdateEvent>? _orderSub;
  int _messageId = 0;
  int? _orderId;

  DeliveryBloc() : super(const DeliveryState()) {
    on<DeliveryLoadRequested>(_onLoad);
    on<DeliveryAdvanceRequested>(_onAdvance);

    // Status changed elsewhere (e.g. order cancelled by admin) → reload
    _orderSub = RealtimeService().orderUpdates.listen((u) {
      if (u.orderId == _orderId && state.result == null && !state.busy) {
        add(DeliveryLoadRequested(orderId: _orderId));
      }
    });
  }

  DeliveryMessage _msg(String text, {bool isError = false}) => DeliveryMessage(++_messageId, text, isError: isError);

  Future<void> _onLoad(DeliveryLoadRequested event, Emitter<DeliveryState> emit) async {
    _orderId = event.orderId ?? _orderId;
    if (state.order == null) emit(state.copyWith(loading: true, clearLoadError: true));
    try {
      if (state.loading) {
        try {
          final cfg = await _api.get(ApiConfig.publicConfig);
          emit(state.copyWith(geofenceMeters: toDouble(cfg.data['data']['geofenceMeters'], 200)));
        } catch (_) {}
      }
      final order = await _fetchActive();
      _orderId = order?.id ?? _orderId;
      emit(state.copyWith(loading: false, clearLoadError: true, order: order, clearOrder: order == null));
    } catch (e) {
      emit(state.copyWith(loading: false, loadError: ApiService.getErrorMessage(e)));
    }
  }

  Future<RiderOrder?> _fetchActive() async {
    final res = await _api.get(ApiConfig.riderOrders, queryParams: {'scope': 'active'});
    final list = (res.data['data'] as List<dynamic>)
        .map((o) => RiderOrder.fromJson(Map<String, dynamic>.from(o)))
        .toList();
    if (list.isEmpty) return null;
    return list.firstWhere((o) => o.id == _orderId, orElse: () => list.first);
  }

  Future<void> _onAdvance(DeliveryAdvanceRequested event, Emitter<DeliveryState> emit) async {
    final order = state.order;
    if (order == null || state.busy) return;
    emit(state.copyWith(busy: true));
    try {
      switch (order.step) {
        case DeliveryStep.headingToStore:
          await _api.post(ApiConfig.riderArrived(order.id));
          await _reload(emit, 'Arrival recorded — waiting time is being tracked');
          break;
        case DeliveryStep.atStore:
          await _api.post(ApiConfig.riderPicked(order.id));
          await _reload(emit, 'Order picked up');
          break;
        case DeliveryStep.pickedUp:
          await _api.post(ApiConfig.riderOnTheWay(order.id));
          await _reload(emit, 'On the way — the customer can track you live');
          break;
        case DeliveryStep.onTheWay:
          await _deliver(order, emit);
          break;
        case DeliveryStep.delivered:
        case DeliveryStep.closed:
          emit(state.copyWith(busy: false));
          break;
      }
    } catch (e) {
      emit(state.copyWith(busy: false, message: _msg(ApiService.getErrorMessage(e), isError: true)));
      // The server may have moved on (e.g. order cancelled) — resync
      try {
        final fresh = await _fetchActive();
        emit(state.copyWith(order: fresh, clearOrder: fresh == null));
      } catch (_) {}
    }
  }

  Future<void> _reload(Emitter<DeliveryState> emit, String message) async {
    final fresh = await _fetchActive();
    emit(state.copyWith(busy: false, order: fresh, clearOrder: fresh == null, message: _msg(message)));
  }

  Future<void> _deliver(RiderOrder order, Emitter<DeliveryState> emit) async {
    final LatLng point;
    try {
      point = await _location.currentPosition(fresh: true);
    } on LocationUnavailable catch (e) {
      emit(state.copyWith(busy: false, message: _msg(e.message, isError: true)));
      return;
    }
    try {
      final res = await _api.post(
        ApiConfig.riderDeliver(order.id),
        data: {'lat': point.latitude, 'lng': point.longitude},
      );
      final result = DeliveryResult.fromJson(Map<String, dynamic>.from(res.data['data']));
      emit(state.copyWith(busy: false, result: result));
    } catch (e) {
      if (ApiService.getErrorCode(e) == 'OUTSIDE_GEOFENCE') {
        final data = ApiService.getErrorData(e) ?? const {};
        final away = toInt(data['distanceMeters']);
        final limit = toInt(data['geofenceMeters'], state.geofenceMeters.round());
        emit(state.copyWith(
          busy: false,
          message: _msg('You are $away m away — move within $limit m of the customer to confirm delivery.',
              isError: true),
        ));
        return;
      }
      rethrow;
    }
  }

  @override
  Future<void> close() {
    _orderSub?.cancel();
    return super.close();
  }
}
