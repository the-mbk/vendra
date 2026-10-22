// ══════════════════════════════════════════════════════════════
// Vendra Rider App - Earnings BLoC
// Earnings totals, paged delivery history, wallet transactions, and
// the balance after a withdrawal.
// ══════════════════════════════════════════════════════════════

import 'dart:async';

import 'package:dio/dio.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:vendra_rider/vendra_core.dart';

import '../models/rider_models.dart';

// Events
abstract class EarningsEvent extends Equatable {
  const EarningsEvent();
  @override
  List<Object?> get props => [];
}

/// Loads totals, wallet and the first page of delivery history
/// (so a refresh always resets history to page 1).
class EarningsRequested extends EarningsEvent {
  /// Completes when the load finishes (for pull-to-refresh)
  final Completer<void>? done;
  const EarningsRequested({this.done});
}

/// Next page of delivery history (infinite scroll). Ignored while a page is
/// loading or when there are no more.
class EarningsHistoryMoreRequested extends EarningsEvent {
  const EarningsHistoryMoreRequested();
}

/// A withdrawal was sent: show the [walletBalance] the API returned right
/// away, refresh the withdrawal list, then reload the wallet rows.
class EarningsWithdrawalCompleted extends EarningsEvent {
  final double? walletBalance;
  const EarningsWithdrawalCompleted({this.walletBalance});
  @override
  List<Object?> get props => [walletBalance];
}

// States
abstract class EarningsState extends Equatable {
  const EarningsState();
  @override
  List<Object?> get props => [];
}

class EarningsInitial extends EarningsState {}

class EarningsLoading extends EarningsState {}

class EarningsLoaded extends EarningsState {
  final RiderEarnings earnings;
  final WalletSummary wallet;

  /// Delivery history loaded so far (GET /api/rider/orders?scope=history is paged)
  final List<RiderOrder> history;
  final PageMeta historyMeta;
  final bool loadingMoreHistory;

  /// Set when the last "load more" failed; the list shows a retry row
  final String? historyError;

  /// Bumped after each withdrawal (refresh key for the withdrawal list)
  final int withdrawalsVersion;

  const EarningsLoaded({
    required this.earnings,
    required this.history,
    required this.wallet,
    this.historyMeta = const PageMeta(),
    this.loadingMoreHistory = false,
    this.historyError,
    this.withdrawalsVersion = 0,
  });

  bool get hasMoreHistory => historyMeta.hasMore && historyMeta.nextOffset != null;

  EarningsLoaded copyWith({
    RiderEarnings? earnings,
    WalletSummary? wallet,
    int? withdrawalsVersion,
    List<RiderOrder>? history,
    PageMeta? historyMeta,
    bool? loadingMoreHistory,
    String? historyError,
    bool clearHistoryError = false,
  }) =>
      EarningsLoaded(
        earnings: earnings ?? this.earnings,
        wallet: wallet ?? this.wallet,
        withdrawalsVersion: withdrawalsVersion ?? this.withdrawalsVersion,
        history: history ?? this.history,
        historyMeta: historyMeta ?? this.historyMeta,
        loadingMoreHistory: loadingMoreHistory ?? this.loadingMoreHistory,
        historyError: clearHistoryError ? null : (historyError ?? this.historyError),
      );

  @override
  List<Object?> get props => [
        earnings.allTime,
        earnings.today,
        earnings.walletBalance,
        history.map((o) => '${o.id}:${o.status}').join(','),
        historyMeta.hasMore,
        historyMeta.nextOffset,
        loadingMoreHistory,
        historyError,
        wallet.transactions.length,
        wallet.transactions.isEmpty ? null : wallet.transactions.first.id,
        wallet.balance,
        withdrawalsVersion,
      ];
}

class EarningsError extends EarningsState {
  final String message;
  const EarningsError(this.message);
  @override
  List<Object?> get props => [message];
}

class EarningsBloc extends Bloc<EarningsEvent, EarningsState> {
  static const historyPageSize = 20;

  final ApiService _api = ApiService();

  /// Bumped by every full reload so a "load more" that was in flight during
  /// a refresh doesn't append a stale page to the fresh list
  int _generation = 0;

  /// Survives full reloads so the withdrawal list's refresh key only moves on a withdrawal
  int _withdrawalsVersion = 0;

  EarningsBloc() : super(EarningsInitial()) {
    on<EarningsRequested>(_onRequested);
    on<EarningsHistoryMoreRequested>(_onHistoryMore);
    on<EarningsWithdrawalCompleted>(_onWithdrawal);
  }

  Future<Response> _historyPage(int offset) => _api.get(ApiConfig.riderOrders,
      queryParams: {'scope': 'history', 'limit': historyPageSize, 'offset': offset});

  static List<RiderOrder> _orders(dynamic body) => (body['data'] as List<dynamic>? ?? const [])
      .map((o) => RiderOrder.fromJson(Map<String, dynamic>.from(o)))
      .toList();

  Future<void> _onRequested(EarningsRequested event, Emitter<EarningsState> emit) async {
    final generation = ++_generation;
    if (state is! EarningsLoaded) emit(EarningsLoading());
    try {
      final results = await Future.wait([
        _api.get(ApiConfig.riderEarnings),
        _historyPage(0),
        _api.get(ApiConfig.wallet),
      ]);
      if (generation != _generation) return; // a newer reload is on its way
      emit(EarningsLoaded(
        earnings: RiderEarnings.fromJson(Map<String, dynamic>.from(results[0].data['data'])),
        history: _orders(results[1].data),
        historyMeta: PageMeta.fromResponse(results[1].data),
        wallet: WalletSummary.fromJson(Map<String, dynamic>.from(results[2].data['data'])),
        withdrawalsVersion: _withdrawalsVersion,
      ));
    } catch (e) {
      if (generation != _generation) return;
      emit(EarningsError(ApiService.getErrorMessage(e)));
    } finally {
      event.done?.complete();
    }
  }

  void _onWithdrawal(EarningsWithdrawalCompleted event, Emitter<EarningsState> emit) {
    _withdrawalsVersion++;
    final current = state;
    final balance = event.walletBalance;
    if (current is EarningsLoaded) {
      final e = current.earnings;
      emit(current.copyWith(
        withdrawalsVersion: _withdrawalsVersion,
        wallet: balance == null ? null : WalletSummary(balance: balance, transactions: current.wallet.transactions),
        earnings: balance == null
            ? null
            : RiderEarnings(
                today: e.today,
                todayCount: e.todayCount,
                week: e.week,
                weekCount: e.weekCount,
                allTime: e.allTime,
                allTimeCount: e.allTimeCount,
                totalKm: e.totalKm,
                walletBalance: balance,
                recent: e.recent,
              ),
      ));
    }
    // The new "Withdrawal" wallet row
    add(const EarningsRequested());
  }

  Future<void> _onHistoryMore(EarningsHistoryMoreRequested event, Emitter<EarningsState> emit) async {
    final current = state;
    if (current is! EarningsLoaded || current.loadingMoreHistory || !current.hasMoreHistory) return;
    final generation = _generation;
    emit(current.copyWith(loadingMoreHistory: true, clearHistoryError: true));
    try {
      final response = await _historyPage(current.historyMeta.nextOffset!);
      final latest = state;
      if (generation != _generation || latest is! EarningsLoaded) return;
      // A delivery finished meanwhile shifts offsets by one: skip rows we already have
      final seen = latest.history.map((o) => o.id).toSet();
      final next = _orders(response.data).where((o) => seen.add(o.id));
      emit(latest.copyWith(
        history: [...latest.history, ...next],
        historyMeta: PageMeta.fromResponse(response.data),
        loadingMoreHistory: false,
      ));
    } catch (e) {
      final latest = state;
      if (generation != _generation || latest is! EarningsLoaded) return;
      emit(latest.copyWith(loadingMoreHistory: false, historyError: ApiService.getErrorMessage(e)));
    }
  }
}
