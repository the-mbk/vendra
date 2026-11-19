// ══════════════════════════════════════════════════════════════
// Vendra Rider App - Home BLoC
// Online/offline status, today's earnings, and incoming delivery
// tasks (live via task:new / task:taken, plus pull-to-refresh).
// Also the admin approval gate: a pending or rejected rider can't go
// online; a rejected one resubmits documents (PUT /api/rider/documents).
// The status refreshes on a rider_approved / rider_rejected notification.
// ══════════════════════════════════════════════════════════════

import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
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

/// Send new or corrected documents for the admin review
class RiderDocumentsSubmitted extends RiderHomeEvent {
  final String cnic;
  final String vehicleType;
  final String? licenseNumber;
  final String? vehicleNumber;
  const RiderDocumentsSubmitted({
    required this.cnic,
    required this.vehicleType,
    this.licenseNumber,
    this.vehicleNumber,
  });
  @override
  List<Object?> get props => [cnic, vehicleType, licenseNumber, vehicleNumber];
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
  final String? reason; // not_approved | offline | busy | no_location
  final int? activeOrderId;
  final double? radiusKm;
  final RiderEarnings? earnings;
  final int? acceptingId;

  /// pending | approved | rejected (documents checked by an admin)
  final String approvalStatus;
  final String? rejectionReason;
  final RiderDocuments documents;
  final bool savingDocuments;

  /// The last document submission's error (shown on the form)
  final String? documentsError;

  /// Bumped when documents were saved (the form closes)
  final int documentsSavedNonce;

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
    this.approvalStatus = 'approved',
    this.rejectionReason,
    this.documents = const RiderDocuments(),
    this.savingDocuments = false,
    this.documentsError,
    this.documentsSavedNonce = 0,
    this.message,
    this.openDeliveryNonce = 0,
    this.openDeliveryId,
  });

  List<RiderOrder> get tasks => allTasks.where((t) => !declined.contains(t.id)).toList();

  /// Only an approved rider may go online and take deliveries
  bool get isApproved => approvalStatus == 'approved';
  bool get isPendingApproval => approvalStatus == 'pending';
  bool get isRejected => approvalStatus == 'rejected';

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
    String? approvalStatus,
    String? rejectionReason,
    bool clearRejectionReason = false,
    RiderDocuments? documents,
    bool? savingDocuments,
    String? documentsError,
    bool clearDocumentsError = false,
    int? documentsSavedNonce,
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
      approvalStatus: approvalStatus ?? this.approvalStatus,
      rejectionReason: clearRejectionReason ? null : (rejectionReason ?? this.rejectionReason),
      documents: documents ?? this.documents,
      savingDocuments: savingDocuments ?? this.savingDocuments,
      documentsError: clearDocumentsError ? null : (documentsError ?? this.documentsError),
      documentsSavedNonce: documentsSavedNonce ?? this.documentsSavedNonce,
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
        earnings?.averageRating,
        acceptingId,
        approvalStatus,
        rejectionReason,
        documents.cnic,
        documents.licenseNumber,
        documents.vehicleNumber,
        savingDocuments,
        documentsError,
        documentsSavedNonce,
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
    on<RiderDocumentsSubmitted>(_onDocumentsSubmitted);

    final rt = RealtimeService();
    _subs.add(rt.newTasks.listen((_) => add(RiderTasksRefreshed())));
    _subs.add(rt.takenTasks.listen((id) => add(RiderTaskTaken(id))));
    // An admin approved or rejected the documents: reload the profile
    _subs.add(rt.notifications
        .where((n) => n.type == 'rider_approved' || n.type == 'rider_rejected')
        .listen((_) => add(const RiderHomeRefreshed())));
  }

  /// Approval status, documents and vehicle from a profile response
  RiderHomeState _withProfile(RiderProfile profile) => state.copyWith(
        isOnline: profile.isOnline,
        vehicleType: profile.vehicleType,
        approvalStatus: profile.approvalStatus,
        rejectionReason: profile.rejectionReason,
        clearRejectionReason: profile.rejectionReason == null,
        documents: profile.documents,
      );

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
      emit(_withProfile(profile).copyWith(activeOrderId: profile.activeOrderId));
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
      emit(_withProfile(profile).copyWith(clearLoadError: true, loading: false));
      if (!profile.isOnline && _location.isTracking) {
        // Taken offline elsewhere (e.g. documents rejected)
        _location.stop();
        _setPolling(false);
      }
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
    final notApproved = result.reason == 'not_approved';
    if ((result.reason == 'offline' || notApproved) && _location.isTracking) {
      // The server has us offline (e.g. changed elsewhere) — stop sending location
      _location.stop();
      _setPolling(false);
    }
    if (notApproved && state.isApproved) {
      // Approval was withdrawn since the profile loaded: learn pending vs rejected (and why)
      try {
        final res = await _api.get(ApiConfig.riderProfile);
        emit(_withProfile(RiderProfile.fromJson(Map<String, dynamic>.from(res.data['data']))));
      } catch (_) {
        emit(state.copyWith(approvalStatus: 'pending'));
      }
    } else if (!notApproved && !state.isApproved) {
      // Tasks report not_approved before anything else, so any other answer means approved
      emit(state.copyWith(approvalStatus: 'approved', clearRejectionReason: true));
    }
    emit(state.copyWith(
      allTasks: result.tasks,
      reason: result.reason,
      clearReason: result.reason == null,
      activeOrderId: result.activeOrderId,
      clearActiveOrder: result.activeOrderId == null,
      radiusKm: result.radiusKm,
      // reason 'offline' / 'not_approved' means the server has us offline
      isOnline: result.reason == 'offline' || notApproved ? false : null,
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
    if (event.online && !state.isApproved) {
      emit(state.copyWith(
        message: _msg(
          state.isRejected
              ? 'Your documents were not approved. Update them and wait for the review.'
              : 'Your documents are being reviewed. You can go online once an admin approves you.',
          isError: true,
        ),
      ));
      return;
    }
    emit(state.copyWith(togglingStatus: true));
    try {
      if (event.online) {
        // A refused manual position switches the app to GPS; then try once more with GPS
        for (var attempt = 0;; attempt++) {
          final LocationFix fix;
          try {
            fix = await _location.currentFix(fresh: true);
          } on LocationUnavailable catch (e) {
            emit(state.copyWith(togglingStatus: false, message: _msg(e.message, isError: true)));
            return;
          }
          try {
            await _api.put(ApiConfig.riderStatus, data: {'isOnline': true, ...fix.toJson()});
            break;
          } catch (e) {
            if (attempt == 0 && fix.manual && _location.handleManualRejected(e)) continue;
            rethrow;
          }
        }
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
      if (ApiService.getErrorCode(e) == 'RIDER_NOT_APPROVED') {
        // 403 { approvalStatus }: the server's message says why (pending, or rejected + reason)
        final status = ApiService.getErrorData(e)?['approvalStatus'] as String?;
        emit(state.copyWith(
          togglingStatus: false,
          isOnline: false,
          approvalStatus: status ?? (state.isApproved ? 'pending' : null),
          message: _msg(ApiService.getErrorMessage(e), isError: true),
        ));
        add(const RiderHomeRefreshed()); // the rejection reason and documents
        return;
      }
      // 409: "Finish your active delivery before going offline."
      emit(state.copyWith(togglingStatus: false, message: _msg(ApiService.getErrorMessage(e), isError: true)));
    }
  }

  Future<void> _onDocumentsSubmitted(RiderDocumentsSubmitted event, Emitter<RiderHomeState> emit) async {
    if (state.savingDocuments) return;
    emit(state.copyWith(savingDocuments: true, clearDocumentsError: true));
    try {
      final res = await _api.put(ApiConfig.riderDocuments, data: {
        'cnic': event.cnic,
        'vehicleType': event.vehicleType,
        if (event.licenseNumber != null) 'licenseNumber': event.licenseNumber,
        if (event.vehicleNumber != null) 'vehicleNumber': event.vehicleNumber,
      });
      final profile = RiderProfile.fromJson(Map<String, dynamic>.from(res.data['data']));
      if (!profile.isOnline && _location.isTracking) {
        // Sent back for review: the server took us offline
        _location.stop();
        _setPolling(false);
      }
      emit(_withProfile(profile).copyWith(
        savingDocuments: false,
        documentsSavedNonce: state.documentsSavedNonce + 1,
        message: _msg(res.data['message'] ?? 'Documents saved'),
      ));
      try {
        await _loadTasks(emit);
      } catch (_) {}
    } catch (e) {
      // 400: what's wrong with a document · 409: active delivery
      emit(state.copyWith(savingDocuments: false, documentsError: ApiService.getErrorMessage(e)));
    }
  }

  Future<void> _onAccepted(RiderTaskAccepted event, Emitter<RiderHomeState> emit) async {
    if (state.acceptingId != null) return;
    emit(state.copyWith(acceptingId: event.orderId));
    try {
      final res = await _api.post(ApiConfig.acceptTask(event.orderId));
      _location.deliveryStarted(); // 10 s location updates from now on (PR 03)
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
