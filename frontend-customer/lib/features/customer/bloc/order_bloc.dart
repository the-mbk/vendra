// ══════════════════════════════════════════════════════════════
// Vendra App - Order BLoC
// Customer order list (FR03/FR04/FR07) + self-pickup confirmations.
// The list is paged (GET /api/customer/orders?limit=&offset=, newest
// first) and grows with infinite scroll. When the server pushes an
// order:update (status, rider, escrow or dispute change) only that order
// is refetched (GET /api/customer/orders/:id) and replaced in place, or
// inserted at the top if it is new.
// ══════════════════════════════════════════════════════════════

import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:vendra_customer/vendra_core.dart';

abstract class OrderEvent extends Equatable {
  const OrderEvent();
  @override
  List<Object?> get props => [];
}

/// Loads the first page (first open, pull-to-refresh, after checkout…)
class FetchCustomerOrders extends OrderEvent {
  final bool silent;
  const FetchCustomerOrders({this.silent = false});
  @override
  List<Object?> get props => [silent];
}

/// Appends the next page when the list is scrolled near its end
class LoadMoreCustomerOrders extends OrderEvent {
  const LoadMoreCustomerOrders();
}

/// Refetches one order after a realtime order:update
class _OrderChanged extends OrderEvent {
  final int orderId;
  const _OrderChanged(this.orderId);
  @override
  List<Object?> get props => [orderId];
}

class CustomerMarkPickedUp extends OrderEvent {
  final int orderId;
  const CustomerMarkPickedUp({required this.orderId});
  @override
  List<Object?> get props => [orderId];
}

class CustomerConfirmDelivered extends OrderEvent {
  final int orderId;
  const CustomerConfirmDelivered({required this.orderId});
  @override
  List<Object?> get props => [orderId];
}

class ClearOrderFeedback extends OrderEvent {}

abstract class OrderState extends Equatable {
  const OrderState();
  @override
  List<Object?> get props => [];
}

class OrderInitial extends OrderState {}

class OrderLoading extends OrderState {}

class OrdersLoaded extends OrderState {
  final List<OrderModel> orders;
  final String? feedback;
  final bool feedbackIsError;

  /// Paging: the server has more orders starting at [nextOffset]
  final bool hasMore;
  final int nextOffset;

  /// A "load more" request is in flight (shows the small loader at the end)
  final bool loadingMore;

  const OrdersLoaded({
    required this.orders,
    this.feedback,
    this.feedbackIsError = false,
    this.hasMore = false,
    this.nextOffset = 0,
    this.loadingMore = false,
  });

  OrdersLoaded copyWith({
    List<OrderModel>? orders,
    String? feedback,
    bool? feedbackIsError,
    bool clearFeedback = false,
    bool? hasMore,
    int? nextOffset,
    bool? loadingMore,
  }) =>
      OrdersLoaded(
        orders: orders ?? this.orders,
        feedback: clearFeedback ? null : (feedback ?? this.feedback),
        feedbackIsError: clearFeedback ? false : (feedbackIsError ?? this.feedbackIsError),
        hasMore: hasMore ?? this.hasMore,
        nextOffset: nextOffset ?? this.nextOffset,
        loadingMore: loadingMore ?? this.loadingMore,
      );

  OrdersLoaded copyWithoutFeedback() => copyWith(clearFeedback: true);

  OrderModel? byId(int id) {
    for (final o in orders) {
      if (o.id == id) return o;
    }
    return null;
  }

  @override
  List<Object?> get props => [
        orders
            .map((o) => '${o.id}:${o.status}:${o.escrowStatus}:${o.rider?.id}:'
                '${o.latestDispute?.status}:${o.latestDispute?.resolution}:${o.escrowReleaseDueAt}')
            .join('|'),
        feedback,
        feedbackIsError,
        hasMore,
        nextOffset,
        loadingMore,
      ];
}

class OrderError extends OrderState {
  final String message;
  const OrderError({required this.message});
  @override
  List<Object?> get props => [message];
}

class _OrdersPage {
  final List<OrderModel> orders;
  final PageMeta meta;
  const _OrdersPage(this.orders, this.meta);
}

class OrderBloc extends Bloc<OrderEvent, OrderState> {
  static const pageSize = 20;

  final ApiService _api = ApiService();
  StreamSubscription<OrderUpdateEvent>? _updatesSub;

  /// Bumped whenever the list restarts from page 1, so a slow "load more"
  /// for the previous list can't append stale rows.
  int _generation = 0;

  OrderBloc() : super(OrderInitial()) {
    on<FetchCustomerOrders>(_onFetchOrders);
    on<LoadMoreCustomerOrders>(_onLoadMore);
    on<_OrderChanged>(_onOrderChanged);
    on<CustomerMarkPickedUp>(_onCustomerMarkPickedUp);
    on<CustomerConfirmDelivered>(_onCustomerConfirmDelivered);
    on<ClearOrderFeedback>(_onClearFeedback);

    // Server-pushed changes (vendor accepted, rider assigned, delivered, escrow released…)
    _updatesSub = RealtimeService().orderUpdates.listen((e) {
      if (isClosed) return;
      if (state is OrdersLoaded) {
        add(_OrderChanged(e.orderId));
      } else if (state is OrderError) {
        add(const FetchCustomerOrders(silent: true));
      }
    });
  }

  Future<_OrdersPage> _loadPage(int offset) async {
    final response = await _api.get(
      ApiConfig.customerOrders,
      queryParams: {'limit': pageSize, 'offset': offset},
    );
    if (response.data['success'] != true) {
      throw Exception(response.data['message'] ?? 'Failed to load orders');
    }
    final orders = (response.data['data'] as List)
        .map((json) => OrderModel.fromJson(Map<String, dynamic>.from(json)))
        .toList();
    return _OrdersPage(orders, PageMeta.fromResponse(response.data));
  }

  Future<OrderModel> _loadOrder(int id) async {
    final response = await _api.get(ApiConfig.customerOrder(id));
    if (response.data['success'] != true) {
      throw Exception(response.data['message'] ?? 'Failed to load order');
    }
    return OrderModel.fromJson(Map<String, dynamic>.from(response.data['data']));
  }

  static OrdersLoaded _firstPageState(_OrdersPage page, {String? feedback}) => OrdersLoaded(
        orders: page.orders,
        feedback: feedback,
        hasMore: page.meta.hasMore,
        nextOffset: page.meta.nextOffset ?? page.orders.length,
      );

  /// Replaces [order] in the list, or puts it first when the list doesn't
  /// have it yet (a brand-new order — the list is newest first).
  static List<OrderModel> _upsert(List<OrderModel> orders, OrderModel order) {
    final next = List<OrderModel>.from(orders);
    final index = next.indexWhere((o) => o.id == order.id);
    if (index >= 0) {
      next[index] = order;
    } else {
      next.insert(0, order);
    }
    return next;
  }

  Future<void> _onFetchOrders(FetchCustomerOrders event, Emitter<OrderState> emit) async {
    final generation = ++_generation;
    if (!event.silent) emit(OrderLoading());
    try {
      final page = await _loadPage(0);
      if (generation != _generation) return;
      emit(_firstPageState(page));
    } catch (e) {
      if (generation != _generation) return;
      // Keep showing the current list if a background refresh fails
      if (!event.silent || state is! OrdersLoaded) {
        emit(OrderError(message: ApiService.getErrorMessage(e)));
      }
    }
  }

  Future<void> _onLoadMore(LoadMoreCustomerOrders event, Emitter<OrderState> emit) async {
    final s = state;
    if (s is! OrdersLoaded || !s.hasMore || s.loadingMore) return;
    final generation = _generation;
    emit(s.copyWith(loadingMore: true));
    try {
      final page = await _loadPage(s.nextOffset);
      final current = state;
      if (generation != _generation || current is! OrdersLoaded) return;
      // A new order inserted at the top meanwhile shifts offsets — skip duplicates
      final known = current.orders.map((o) => o.id).toSet();
      emit(current.copyWith(
        orders: [...current.orders, ...page.orders.where((o) => !known.contains(o.id))],
        hasMore: page.meta.hasMore && page.orders.isNotEmpty,
        nextOffset: page.meta.nextOffset ?? current.nextOffset + page.orders.length,
        loadingMore: false,
      ));
    } catch (_) {
      final current = state;
      if (generation != _generation || current is! OrdersLoaded) return;
      // Stop auto-loading after a failure; pull-to-refresh starts over
      emit(current.copyWith(loadingMore: false, hasMore: false));
    }
  }

  Future<void> _onOrderChanged(_OrderChanged event, Emitter<OrderState> emit) async {
    try {
      final order = await _loadOrder(event.orderId);
      final current = state;
      if (current is OrdersLoaded) emit(current.copyWith(orders: _upsert(current.orders, order)));
    } catch (_) {
      // Missed this update; the next refresh picks it up
    }
  }

  void _onClearFeedback(ClearOrderFeedback event, Emitter<OrderState> emit) {
    final s = state;
    if (s is OrdersLoaded) emit(s.copyWithoutFeedback());
  }

  Future<void> _runAction(
    Emitter<OrderState> emit,
    int orderId,
    String path, {
    required String successMessage,
    required String failMessage,
  }) async {
    void fail(String msg) {
      final current = state;
      if (current is OrdersLoaded) {
        emit(current.copyWith(feedback: msg, feedbackIsError: true));
      } else {
        emit(OrderError(message: msg));
      }
    }

    try {
      final response = await _api.post(path);
      if (response.data['success'] != true) {
        fail(response.data['message']?.toString() ?? failMessage);
        return;
      }
      if (state is OrdersLoaded) {
        // Refresh just this order, keeping the pages already loaded
        final order = await _loadOrder(orderId);
        final current = state;
        if (current is OrdersLoaded) {
          emit(current.copyWith(
            orders: _upsert(current.orders, order),
            feedback: successMessage,
            feedbackIsError: false,
          ));
          return;
        }
      }
      final generation = ++_generation;
      final page = await _loadPage(0);
      if (generation == _generation) emit(_firstPageState(page, feedback: successMessage));
    } catch (e) {
      fail(ApiService.getErrorMessage(e));
    }
  }

  Future<void> _onCustomerMarkPickedUp(CustomerMarkPickedUp event, Emitter<OrderState> emit) =>
      _runAction(emit, event.orderId, ApiConfig.customerMarkPickedUp(event.orderId),
          successMessage: 'Marked as picked up.', failMessage: 'Could not update order');

  Future<void> _onCustomerConfirmDelivered(CustomerConfirmDelivered event, Emitter<OrderState> emit) =>
      _runAction(emit, event.orderId, ApiConfig.customerConfirmReceived(event.orderId),
          successMessage: 'Order received. Payment is released to the store after the dispute window.',
          failMessage: 'Could not complete order');

  @override
  Future<void> close() {
    _updatesSub?.cancel();
    return super.close();
  }
}
