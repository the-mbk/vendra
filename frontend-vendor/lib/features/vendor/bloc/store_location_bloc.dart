// ══════════════════════════════════════════════════════════════
// Vendra Vendor App - Store location BLoC
// Holds the store's live location plus any change waiting for admin
// approval (or the reason the last one was rejected), so the home
// card and the location screen show the same thing.
// ══════════════════════════════════════════════════════════════

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:vendra_vendor/vendra_core.dart';

import '../models/store_location_status.dart';

// ── Events ──
abstract class StoreLocationEvent {
  const StoreLocationEvent();
}

/// Re-read the status from /api/auth/me
class StoreLocationRequested extends StoreLocationEvent {
  const StoreLocationRequested();
}

/// A location call (save / withdraw) already returned the new status
class StoreLocationReplaced extends StoreLocationEvent {
  final StoreLocationStatus status;
  const StoreLocationReplaced(this.status);
}

// ── State ──
class StoreLocationState {
  final StoreLocationStatus? status; // null until first loaded
  final bool isLoading;

  const StoreLocationState({this.status, this.isLoading = false});
}

class StoreLocationBloc extends Bloc<StoreLocationEvent, StoreLocationState> {
  final ApiService _api = ApiService();

  StoreLocationBloc() : super(const StoreLocationState()) {
    on<StoreLocationRequested>(_onRequested);
    on<StoreLocationReplaced>((event, emit) => emit(StoreLocationState(status: event.status)));
  }

  Future<void> _onRequested(StoreLocationRequested event, Emitter<StoreLocationState> emit) async {
    emit(StoreLocationState(status: state.status, isLoading: true));
    try {
      final response = await _api.get(ApiConfig.me);
      if (response.data['success'] == true && response.data['data'] is Map<String, dynamic>) {
        emit(StoreLocationState(status: StoreLocationStatus.fromMe(response.data['data'])));
        return;
      }
    } catch (_) {
      // Keep what we had; the next refresh will catch up.
    }
    emit(StoreLocationState(status: state.status));
  }
}
