// ══════════════════════════════════════════════════════════════
// Vendra Rider App - Home BLoC
// Online/offline status, today's earnings, and incoming delivery
// tasks (live via task:new / task:taken, plus pull-to-refresh).
// ══════════════════════════════════════════════════════════════

import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:latlong2/latlong.dart';
import 'package:vendra_rider/vendra_core.dart';

import '../models/rider_models.dart';
import '../services/rider_location_service.dart';

// ── Events ───────────────────────────────────────────────────

abstract class RiderHomeEvent extends Equatable {
  const RiderHomeEvent();
  @override
  List<Object?> get props => [];
}

/// Home opened (after login / app start): profile, tasks, earnings; resumes an active delivery
class RiderHomeStarted extends RiderHomeEvent {}

/// Pull-to-refresh, or back from a delivery. [done] completes when finished.
class RiderHomeRefreshed extends RiderHomeEvent {
  final Completer<void>? done;
  const RiderHomeRefreshed({this.done});
}

/// task:new from the socket (or the fallback poll)
class RiderTasksRefreshed extends RiderHomeEvent {}

/// task:taken from the socket
class RiderTaskTaken extends RiderHomeEvent {
  final int orderId;
  const RiderTaskTaken(this.orderId);
  @override
  List<Object?> get props => [orderId];
}

class RiderOnlineToggled extends RiderHomeEvent {
  final bool online;
  const RiderOnlineToggled(this.online);
  @override
  List<Object?> get props => [online];
}

class RiderTaskAccepted extends RiderHomeEvent {
  final int orderId;
  const RiderTaskAccepted(this.orderId);
  @override
  List<Object?> get props => [orderId];
}

/// Decline only hides the task on this device
class RiderTaskDeclined extends RiderHomeEvent {
  final int orderId;
  const RiderTaskDeclined(this.orderId);
  @override
  List<Object?> get props => [orderId];
}

// ── State ────────────────────────────────────────────────────

class HomeMessage {
  final int id;
  final String text;
  final bool isError;
  const HomeMessage(this.id, this.text, {this.isError = false});
}

class RiderHomeState extends Equatable {
  final bool loading;
  final String? loadError;
  final bool isOnline;
  final bool togglingStatus;
  final String? vehicleType;
  final List<RiderOrder> allTasks;
  final Set<int> declined;
  final String? reason; // offline | busy | no_location
  final int? activeOrderId;
  final double? radiusKm;
  final RiderEarnings? earnings;
  final int? acceptingId;

  /// One-shot UI effects, keyed by an increasing id
  final HomeMessage? message;
  final int openDeliveryNonce;
  final int? openDeliveryId;

  const RiderHomeState({
    this.loading = true,
    this.loadError,
    this.isOnline = false,
    this.togglingStatus = false,
    this.vehicleType,
    this.allTasks = const [],
    this.declined = const {},
    this.reason,
    this.activeOrderId,
    this.radiusKm,
    this.earnings,
    this.acceptingId,
    this.message,
    this.openDeliveryNonce = 0,
    this.openDeliveryId,
  });

  List<RiderOrder> get tasks => allTasks.where((t) => !declined.contains(t.id)).toList();

  RiderHomeState copyWith({
    bool? loading,
    String? loadError,
    bool clearLoadError = false,
    bool? isOnline,
    bool? togglingStatus,
    String? vehicleType,
    List<RiderOrder>? allTasks,
    Set<int>? declined,
    String? reason,
    bool clearReason = false,
    int? activeOrderId,
    bool clearActiveOrder = false,
    double? radiusKm,
    RiderEarnings? earnings,
    int? acceptingId,
    bool clearAccepting = false,
    HomeMessage? message,
    int? openDeliveryId,
    int? openDeliveryNonce,
  }) {
    return RiderHomeState(
      loading: loading ?? this.loading,
      loadError: clearLoadError ? null : (loadError ?? this.loadError),
      isOnline: isOnline ?? this.isOnline,
      togglingStatus: togglingStatus ?? this.togglingStatus,
      vehicleType: vehicleType ?? this.vehicleType,
      allTasks: allTasks ?? this.allTasks,
      declined: declined ?? this.declined,
      reason: clearReason ? null : (reason ?? this.reason),
      activeOrderId: clearActiveOrder ? null : (activeOrderId ?? this.activeOrderId),
      radiusKm: radiusKm ?? this.radiusKm,
      earnings: earnings ?? this.earnings,
      acceptingId: clearAccepting ? null : (acceptingId ?? this.acceptingId),
      message: message ?? this.message,
      openDeliveryId: openDeliveryId ?? this.openDeliveryId,
      openDeliveryNonce: openDeliveryNonce ?? this.openDeliveryNonce,
    );
  }

  @override
  List<Object?> get props => [
        loading,
        loadError,
        isOnline,
        togglingStatus,
        vehicleType,
        allTasks.map((t) => t.id).join(','),
        declined.join(','),
        reason,
        activeOrderId,
        radiusKm,
        earnings?.today,
        earnings?.todayCount,
        earnings?.week,
        acceptingId,
        message?.id,
        openDeliveryNonce,
      ];
}

// ── BLoC ─────────────────────────────────────────────────────

class RiderHomeBloc extends Bloc<RiderHomeEvent, RiderHomeState> {
  final ApiService _api = ApiService();
  final RiderLocationService _location = RiderLocationService();
  final List<StreamSubscription<dynamic>> _subs = [];
  Timer? _poll;
  int _messageId = 0;

  RiderHomeBloc() : super(const RiderHomeState()) {
    on<RiderHomeStarted>(_onStarted);
    on<RiderHomeRefreshed>(_onRefreshed);
    on<RiderTasksRefreshed>(_onTasksRefreshed);
    on<RiderTaskTaken>(_onTaskTaken);
    on<RiderOnlineToggled>(_onToggled);
    on<RiderTaskAccepted>(_onAccepted);
    on<RiderTaskDeclined>(_onDeclined);

    final rt = RealtimeService();
    _subs.add(rt.newTasks.listen((_) => add(RiderTasksRefreshed())));
    _subs.add(rt.takenTasks.listen((id) => add(RiderTaskTaken(id))));
  }

  HomeMessage _msg(String text, {bool isError = false}) => HomeMessage(++_messageId, text, isError: isError);

  Future<void> _onStarted(RiderHomeStarted event, Emitter<RiderHomeState> emit) async {
    emit(const RiderHomeState(loading: true));
    await _location.init();
    try {
      final res = await _api.get(ApiConfig.riderProfile);
      final profile = RiderProfile.fromJson(Map<String, dynamic>.from(res.data['data']));
      _location.rememberServerPosition(profile.currentLat, profile.currentLng);
      if (profile.isOnline) _location.start();
      _setPolling(profile.isOnline);
      emit(state.copyWith(
        isOnline: profile.isOnline,
        vehicleType: profile.vehicleType,
        activeOrderId: profile.activeOrderId,
      ));
      await _loadTasks(emit);
      await _loadEarnings(emit);
      emit(state.copyWith(loading: false, clearLoadError: true));
      // Resume an in-progress delivery straight away
      if (profile.activeOrderId != null) {
        emit(state.copyWith(openDeliveryId: profile.activeOrderId, openDeliveryNonce: state.openDeliveryNonce + 1));
      }
    } catch (e) {
      emit(state.copyWith(loading: false, loadError: ApiService.getErrorMessage(e)));
    }
  }

  Future<void> _onRefreshed(RiderHomeRefreshed event, Emitter<RiderHomeState> emit) async {
    try {
      final res = await _api.get(ApiConfig.riderProfile);
      final profile = RiderProfile.fromJson(Map<String, dynamic>.from(res.data['data']));
      emit(state.copyWith(isOnline: profile.isOnline, clearLoadError: true, loading: false));
      await _loadTasks(emit);
      await _loadEarnings(emit);
    } catch (e) {
      emit(state.copyWith(loading: false, message: _msg(ApiService.getErrorMessage(e), isError: true)));
    } finally {
      event.done?.complete();
    }
  }

  Future<void> _onTasksRefreshed(RiderTasksRefreshed event, Emitter<RiderHomeState> emit) async {
    try {
      await _loadTasks(emit);
    } catch (_) {
      // Silent: realtime/poll refreshes shouldn't spam errors
    }
  }

  Future<void> _onTaskTaken(RiderTaskTaken event, Emitter<RiderHomeState> emit) async {
    if (event.orderId == state.activeOrderId) return; // we took it
    emit(state.copyWith(allTasks: state.allTasks.where((t) => t.id != event.orderId).toList()));
  }

  Future<void> _loadTasks(Emitter<RiderHomeState> emit) async {
    final res = await _api.get(ApiConfig.riderTasks);
    final result = RiderTasksResult.fromJson(Map<String, dynamic>.from(res.data['data']));
    if (result.reason == 'offline' && _location.isTracking) {
      // The server has us offline (e.g. changed elsewhere) — stop sending location
      _location.stop();
      _setPolling(false);
    }
    emit(state.copyWith(
      allTasks: result.tasks,
      reason: result.reason,
      clearReason: result.reason == null,
      activeOrderId: result.activeOrderId,
      clearActiveOrder: result.activeOrderId == null,
      radiusKm: result.radiusKm,
      // reason 'offline' means the server has us offline
      isOnline: result.reason == 'offline' ? false : null,
    ));
  }

  Future<void> _loadEarnings(Emitter<RiderHomeState> emit) async {
    try {
      final res = await _api.get(ApiConfig.riderEarnings);
      emit(state.copyWith(earnings: RiderEarnings.fromJson(Map<String, dynamic>.from(res.data['data']))));
    } catch (_) {}
  }

  Future<void> _onToggled(RiderOnlineToggled event, Emitter<RiderHomeState> emit) async {
    if (state.togglingStatus || event.online == state.isOnline) return;
    emit(state.copyWith(togglingStatus: true));
    try {
      if (event.online) {
        final LatLng point;
        try {
          point = await _location.currentPosition(fresh: true);
        } on LocationUnavailable catch (e) {
          emit(state.copyWith(togglingStatus: false, message: _msg(e.message, isError: true)));
          return;
        }
        await _api.put(ApiConfig.riderStatus,
            data: {'isOnline': true, 'lat': point.latitude, 'lng': point.longitude});
        _location.start();
        _setPolling(true);
        emit(state.copyWith(isOnline: true, togglingStatus: false, message: _msg('You are online')));
      } else {
        await _api.put(ApiConfig.riderStatus, data: {'isOnline': false});
        _location.stop();
        _setPolling(false);
        emit(state.copyWith(isOnline: false, togglingStatus: false, message: _msg('You are offline')));
      }
      await _loadTasks(emit);
    } catch (e) {
      // 409: "Finish your active delivery before going offline."
      emit(state.copyWith(togglingStatus: false, message: _msg(ApiService.getErrorMessage(e), isError: true)));
    }
  }

  Future<void> _onAccepted(RiderTaskAccepted event, Emitter<RiderHomeState> emit) async {
    if (state.acceptingId != null) return;
    emit(state.copyWith(acceptingId: event.orderId));
    try {
      final res = await _api.post(ApiConfig.acceptTask(event.orderId));
      emit(state.copyWith(
        clearAccepting: true,
        activeOrderId: event.orderId,
        allTasks: const [],
        reason: 'busy',
        message: _msg(res.data['message'] ?? 'Delivery accepted'),
        openDeliveryId: event.orderId,
        openDeliveryNonce: state.openDeliveryNonce + 1,
      ));
    } catch (e) {
      final taken = ApiService.getErrorCode(e) == 'TASK_TAKEN';
      emit(state.copyWith(
        clearAccepting: true,
        allTasks: taken ? state.allTasks.where((t) => t.id != event.orderId).toList() : null,
        message: _msg(
          taken ? 'Another rider accepted this delivery first.' : ApiService.getErrorMessage(e),
          isError: true,
        ),
      ));
      try {
        await _loadTasks(emit);
      } catch (_) {}
    }
  }

  void _onDeclined(RiderTaskDeclined event, Emitter<RiderHomeState> emit) {
    emit(state.copyWith(declined: {...state.declined, event.orderId}));
  }

  /// Fallback refresh in case a socket event is missed
  void _setPolling(bool on) {
    _poll?.cancel();
    _poll = on ? Timer.periodic(const Duration(seconds: 30), (_) => add(RiderTasksRefreshed())) : null;
  }

  @override
  Future<void> close() {
    _poll?.cancel();
    for (final s in _subs) {
      s.cancel();
    }
    return super.close();
  }
}
