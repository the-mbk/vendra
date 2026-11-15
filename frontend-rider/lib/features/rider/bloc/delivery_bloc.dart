// ══════════════════════════════════════════════════════════════
// Vendra Rider App - Active Delivery BLoC
// Walks the delivery: arrived at store → picked up (both checked against
// the store location, pickup geofence) → on the way →
// confirm delivery (geofenced, SSR02, plus the customer's 4-digit
// handover code so a spoofed GPS position alone can't finish it).
// The deliver response carries the itemised payout slip (FR04);
// escrow release starts (FR03).
// ══════════════════════════════════════════════════════════════

import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:vendra_rider/vendra_core.dart';

import '../models/handover_code.dart';
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

/// The single primary button: performs the next step. On the way, when the
/// order needs a handover code, this only asks for it (awaitingCode).
class DeliveryAdvanceRequested extends DeliveryEvent {}

/// The customer's code was entered: confirm the delivery with it
class DeliveryCodeSubmitted extends DeliveryEvent {
  final String code;
  const DeliveryCodeSubmitted(this.code);
  @override
  List<Object?> get props => [code];
}

/// The code dialog was closed without confirming
class DeliveryCodeCancelled extends DeliveryEvent {}

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

  /// The handover code dialog is open (the screen shows / closes it)
  final bool awaitingCode;

  /// Why the last code was refused (wrong, attempts left, locked until…)
  final HandoverCodeFeedback? codeFeedback;

  const DeliveryState({
    this.loading = true,
    this.loadError,
    this.order,
    this.busy = false,
    this.geofenceMeters = 200,
    this.message,
    this.result,
    this.awaitingCode = false,
    this.codeFeedback,
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
    bool? awaitingCode,
    HandoverCodeFeedback? codeFeedback,
    bool clearCodeFeedback = false,
  }) {
    return DeliveryState(
      loading: loading ?? this.loading,
      loadError: clearLoadError ? null : (loadError ?? this.loadError),
      order: clearOrder ? null : (order ?? this.order),
      busy: busy ?? this.busy,
      geofenceMeters: geofenceMeters ?? this.geofenceMeters,
      message: message ?? this.message,
      result: result ?? this.result,
      awaitingCode: awaitingCode ?? this.awaitingCode,
      codeFeedback: clearCodeFeedback ? null : (codeFeedback ?? this.codeFeedback),
    );
  }

  @override
  List<Object?> get props => [
        loading,
        loadError,
        order?.id,
        order?.status,
        order?.arrivedAt,
        order?.otpRequired,
        busy,
        geofenceMeters,
        message?.id,
        result?.orderId,
        awaitingCode,
        codeFeedback?.id,
      ];
}

// ── BLoC ─────────────────────────────────────────────────────

class DeliveryBloc extends Bloc<DeliveryEvent, DeliveryState> {
  final ApiService _api = ApiService();
  final RiderLocationService _location = RiderLocationService();
  StreamSubscription<OrderUpdateEvent>? _orderSub;
  int _messageId = 0;
  int? _orderId;

  DeliveryBloc() : super(DeliveryState(geofenceMeters: AppConfig.current.geofenceMeters.toDouble())) {
    on<DeliveryLoadRequested>(_onLoad);
    on<DeliveryAdvanceRequested>(_onAdvance);
    on<DeliveryCodeSubmitted>(_onCodeSubmitted);
    on<DeliveryCodeCancelled>(_onCodeCancelled);

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
        // Retries the platform config if the startup load failed (never throws)
        final cfg = await AppConfig.ensureLoaded();
        emit(state.copyWith(geofenceMeters: cfg.geofenceMeters.toDouble()));
      }
      final order = await _fetchActive();
      _orderId = order?.id ?? _orderId;
      emit(state.copyWith(
        loading: false,
        clearLoadError: true,
        order: order,
        clearOrder: order == null,
        // Cancelled (or otherwise moved on) while the code dialog was open: close it
        awaitingCode: state.awaitingCode && order?.step == DeliveryStep.onTheWay,
      ));
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
          if (await _atStore(ApiConfig.riderArrived(order.id), emit)) {
            await _reload(emit, 'Arrival recorded — waiting time is being tracked');
          }
          break;
        case DeliveryStep.atStore:
          if (await _atStore(ApiConfig.riderPicked(order.id), emit)) {
            await _reload(emit, 'Order picked up');
          }
          break;
        case DeliveryStep.pickedUp:
          await _api.post(ApiConfig.riderOnTheWay(order.id));
          await _reload(emit, 'On the way — the customer can track you live');
          break;
        case DeliveryStep.onTheWay:
          if (order.otpRequired) {
            // Ask for the customer's code first; a lockout stays visible until it ends
            final feedback = state.codeFeedback;
            emit(state.copyWith(
              busy: false,
              awaitingCode: true,
              clearCodeFeedback: feedback == null || !feedback.isLocked(),
            ));
          } else {
            await _deliver(order, emit); // an order from before handover codes
          }
          break;
        case DeliveryStep.delivered:
        case DeliveryStep.closed:
          emit(state.copyWith(busy: false));
          break;
      }
    } catch (e) {
      await _failed(e, emit);
    }
  }

  Future<void> _onCodeSubmitted(DeliveryCodeSubmitted event, Emitter<DeliveryState> emit) async {
    final order = state.order;
    if (order == null || state.busy || !state.awaitingCode) return;
    emit(state.copyWith(busy: true));
    try {
      await _deliver(order, emit, otp: event.code);
    } catch (e) {
      await _failed(e, emit);
    }
  }

  void _onCodeCancelled(DeliveryCodeCancelled event, Emitter<DeliveryState> emit) {
    if (state.busy) return;
    final feedback = state.codeFeedback;
    emit(state.copyWith(awaitingCode: false, clearCodeFeedback: feedback == null || !feedback.isLocked()));
  }

  /// Unexpected error: show it, close the code dialog, and resync
  Future<void> _failed(Object e, Emitter<DeliveryState> emit) async {
    emit(state.copyWith(busy: false, awaitingCode: false, message: _msg(ApiService.getErrorMessage(e), isError: true)));
    // The server may have moved on (e.g. order cancelled) — resync
    try {
      final fresh = await _fetchActive();
      emit(state.copyWith(order: fresh, clearOrder: fresh == null));
    } catch (_) {}
  }

  Future<void> _reload(Emitter<DeliveryState> emit, String message) async {
    final fresh = await _fetchActive();
    emit(state.copyWith(busy: false, order: fresh, clearOrder: fresh == null, message: _msg(message)));
  }

  /// Arrived / picked up: the server checks the rider is near the store (pickup
  /// geofence). False when it said no (or there was no fix); the rider was told why.
  Future<bool> _atStore(String path, Emitter<DeliveryState> emit) async {
    final LocationFix fix;
    try {
      fix = await _location.currentFix(fresh: true);
    } on LocationUnavailable catch (e) {
      emit(state.copyWith(busy: false, message: _msg(e.message, isError: true)));
      return false;
    }
    try {
      await _api.post(path, data: fix.toJson());
      return true;
    } catch (e) {
      if (_location.handleManualRejected(e)) {
        emit(state.copyWith(busy: false));
        return false;
      }
      if (ApiService.getErrorCode(e) == 'OUTSIDE_PICKUP_GEOFENCE') {
        final data = ApiService.getErrorData(e) ?? const {};
        final away = toInt(data['distanceMeters']);
        final limit = toInt(data['geofenceMeters']);
        emit(state.copyWith(
          busy: false,
          message: _msg('You are $away m from the store — move within $limit m of it to continue.', isError: true),
        ));
        return false;
      }
      rethrow;
    }
  }

  /// Geofence first (server order), then the handover code. Code problems keep
  /// the dialog open with the reason; anything else closes it.
  Future<void> _deliver(RiderOrder order, Emitter<DeliveryState> emit, {String? otp}) async {
    final LocationFix fix;
    try {
      fix = await _location.currentFix(fresh: true);
    } on LocationUnavailable catch (e) {
      emit(state.copyWith(busy: false, awaitingCode: false, message: _msg(e.message, isError: true)));
      return;
    }
    try {
      final res = await _api.post(ApiConfig.riderDeliver(order.id), data: {
        ...fix.toJson(),
        if (otp != null) 'otp': otp,
      });
      final result = DeliveryResult.fromJson(Map<String, dynamic>.from(res.data['data']));
      _location.stopDrive();
      emit(state.copyWith(busy: false, awaitingCode: false, clearCodeFeedback: true, result: result));
    } catch (e) {
      // Manual position refused: the service switched to GPS and told the rider — tap again
      if (_location.handleManualRejected(e)) {
        emit(state.copyWith(busy: false, awaitingCode: false));
        return;
      }
      final feedback = HandoverCodeFeedback.fromError(
        ++_messageId,
        code: ApiService.getErrorCode(e),
        data: ApiService.getErrorData(e),
        message: ApiService.getErrorMessage(e),
      );
      if (feedback != null) {
        // OTP_REQUIRED (the order list was stale) / WRONG_OTP / OTP_LOCKED
        emit(state.copyWith(busy: false, awaitingCode: true, codeFeedback: feedback));
        return;
      }
      if (ApiService.getErrorCode(e) == 'OUTSIDE_GEOFENCE') {
        final data = ApiService.getErrorData(e) ?? const {};
        final away = toInt(data['distanceMeters']);
        final limit = toInt(data['geofenceMeters'], state.geofenceMeters.round());
        emit(state.copyWith(
          busy: false,
          awaitingCode: false,
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
