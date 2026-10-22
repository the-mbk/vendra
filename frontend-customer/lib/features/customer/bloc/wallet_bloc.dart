// ══════════════════════════════════════════════════════════════
// Vendra App - Wallet BLoC
// GET /api/wallet → balance + ledger (card top-ups, escrow holds, refunds,
// withdrawals). Card top-ups and withdrawals run in the shared card flows
// (they need sheets/dialogs); afterwards the screen sends WalletChanged so
// the ledger reloads and the outcome is shown once.
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

/// Money moved outside the bloc (card top-up, withdrawal): reload and show [feedback]
class WalletChanged extends WalletEvent {
  final String? feedback;
  final bool isError;
  const WalletChanged({this.feedback, this.isError = false});
  @override
  List<Object?> get props => [feedback, isError, identityHashCode(this)];
}

// ── State ──
class WalletState extends Equatable {
  final WalletSummary? summary;
  final bool loading;
  final String? error;

  /// One-shot message after a top-up or withdrawal (success or failure)
  final String? feedback;
  final bool feedbackIsError;

  /// Bumped after each change so the withdrawal history reloads too
  final int revision;

  const WalletState({
    this.summary,
    this.loading = false,
    this.error,
    this.feedback,
    this.feedbackIsError = false,
    this.revision = 0,
  });

  @override
  List<Object?> get props => [
        summary?.balance,
        summary?.transactions.length,
        summary?.transactions.isNotEmpty == true ? summary!.transactions.first.id : null,
        loading,
        error,
        feedback,
        feedbackIsError,
        revision,
      ];
}

// ── BLoC ──
class WalletBloc extends Bloc<WalletEvent, WalletState> {
  final ApiService _api = ApiService();
  StreamSubscription<OrderUpdateEvent>? _updatesSub;
  StreamSubscription<NotificationModel>? _notifSub;

  /// Notifications that mean the balance changed without an order update
  static const _walletNotifications = {
    'wallet_topup',
    'payment_order_failed',
    'withdrawal_paid',
    'withdrawal_failed',
    'withdrawal_reversal',
  };

  WalletBloc() : super(const WalletState(loading: true)) {
    on<FetchWallet>(_onFetch);
    on<WalletChanged>(_onChanged);
    // Cancellations and dispute refunds credit the wallet and push an order:update
    _updatesSub = RealtimeService().orderUpdates.listen((_) => add(const FetchWallet(silent: true)));
    // Card top-ups confirmed by webhook, bounced withdrawals returning money…
    _notifSub = RealtimeService().notifications.listen((n) {
      if (_walletNotifications.contains(n.type)) add(const FetchWallet(silent: true));
    });
  }

  Future<WalletSummary> _load() async {
    final res = await _api.get(ApiConfig.wallet);
    return WalletSummary.fromJson(Map<String, dynamic>.from(res.data['data'] as Map));
  }

  Future<void> _onFetch(FetchWallet event, Emitter<WalletState> emit) async {
    if (!event.silent) emit(WalletState(summary: state.summary, loading: true, revision: state.revision));
    try {
      emit(WalletState(summary: await _load(), revision: state.revision));
    } catch (e) {
      emit(WalletState(summary: state.summary, error: ApiService.getErrorMessage(e), revision: state.revision));
    }
  }

  Future<void> _onChanged(WalletChanged event, Emitter<WalletState> emit) async {
    WalletSummary? summary = state.summary;
    try {
      summary = await _load();
    } catch (_) {
      // Keep the old ledger; the feedback still matters more
    }
    emit(WalletState(
      summary: summary,
      feedback: event.feedback,
      feedbackIsError: event.isError,
      revision: state.revision + 1,
    ));
  }

  @override
  Future<void> close() {
    _updatesSub?.cancel();
    _notifSub?.cancel();
    return super.close();
  }
}
