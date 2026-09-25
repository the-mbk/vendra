// ══════════════════════════════════════════════════════════════
// Vendra App - Wallet BLoC
// GET /api/wallet → balance + ledger (top-ups, escrow holds, refunds)
// POST /api/customer/wallet/topup → simulated deposit
// ══════════════════════════════════════════════════════════════

import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:vendra_customer/vendra_core.dart';

// ── Events ──
abstract class WalletEvent extends Equatable {
  const WalletEvent();
  @override
  List<Object?> get props => [];
}

class FetchWallet extends WalletEvent {
  final bool silent;
  const FetchWallet({this.silent = false});
  @override
  List<Object?> get props => [silent];
}

class WalletTopUpRequested extends WalletEvent {
  final double amount;
  const WalletTopUpRequested(this.amount);
  @override
  List<Object?> get props => [amount];
}

// ── State ──
class WalletState extends Equatable {
  final WalletSummary? summary;
  final bool loading;
  final bool toppingUp;
  final String? error;

  /// One-shot message after a top-up (success or failure)
  final String? feedback;
  final bool feedbackIsError;

  const WalletState({
    this.summary,
    this.loading = false,
    this.toppingUp = false,
    this.error,
    this.feedback,
    this.feedbackIsError = false,
  });

  @override
  List<Object?> get props => [
        summary?.balance,
        summary?.transactions.length,
        summary?.transactions.isNotEmpty == true ? summary!.transactions.first.id : null,
        loading,
        toppingUp,
        error,
        feedback,
        feedbackIsError,
      ];
}

// ── BLoC ──
class WalletBloc extends Bloc<WalletEvent, WalletState> {
  final ApiService _api = ApiService();
  StreamSubscription<OrderUpdateEvent>? _updatesSub;

  WalletBloc() : super(const WalletState(loading: true)) {
    on<FetchWallet>(_onFetch);
    on<WalletTopUpRequested>(_onTopUp);
    // Cancellations and dispute refunds credit the wallet and push an order:update
    _updatesSub = RealtimeService().orderUpdates.listen((_) => add(const FetchWallet(silent: true)));
  }

  Future<WalletSummary> _load() async {
    final res = await _api.get(ApiConfig.wallet);
    return WalletSummary.fromJson(Map<String, dynamic>.from(res.data['data'] as Map));
  }

  Future<void> _onFetch(FetchWallet event, Emitter<WalletState> emit) async {
    if (!event.silent) emit(WalletState(summary: state.summary, loading: true));
    try {
      emit(WalletState(summary: await _load()));
    } catch (e) {
      emit(WalletState(summary: state.summary, error: ApiService.getErrorMessage(e)));
    }
  }

  Future<void> _onTopUp(WalletTopUpRequested event, Emitter<WalletState> emit) async {
    emit(WalletState(summary: state.summary, toppingUp: true));
    try {
      final res = await _api.post(ApiConfig.walletTopup, data: {'amount': event.amount});
      if (res.data['success'] != true) {
        emit(WalletState(
          summary: state.summary,
          feedback: res.data['message']?.toString() ?? 'Top up failed',
          feedbackIsError: true,
        ));
        return;
      }
      emit(WalletState(
        summary: await _load(),
        feedback: 'Rs. ${event.amount.toStringAsFixed(0)} added to your wallet',
      ));
    } catch (e) {
      emit(WalletState(summary: state.summary, feedback: ApiService.getErrorMessage(e), feedbackIsError: true));
    }
  }

  @override
  Future<void> close() {
    _updatesSub?.cancel();
    return super.close();
  }
}
