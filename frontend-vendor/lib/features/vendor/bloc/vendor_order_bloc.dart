// ══════════════════════════════════════════════════════════════
// Vendra App - Vendor Order BLoC
// Two lists (see VendorOrderLists):
//   active   every in-progress order — GET /api/vendor/orders?scope=active
//   history  delivered / cancelled — ?scope=history, paged (load more on scroll)
// Approve/reject pending orders, the packing checklist (tick a line or scan
// a unit, FR07), packed → ready. Self-pickup handover needs the customer's
// code and is done by the handover dialog (widgets/handover_code_dialog.dart).
// Stays live: an `order:update` socket event or an order notification
// (new order, rider accepted, dispute raised, escrow released…) re-reads
// just that order via GET /api/vendor/orders/:id and moves it between the
// lists by status, instead of refetching everything (FR07 / FR09).
// ══════════════════════════════════════════════════════════════

import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:vendra_vendor/vendra_core.dart';
import '../models/vendor_order_lists.dart';

// Events
abstract class VendorOrderEvent extends Equatable {
  const VendorOrderEvent();
  @override
  List<Object?> get props => [];
}

/// Loads the active orders and the first history page
class FetchVendorOrders extends VendorOrderEvent {
  /// Silent refetches keep the current lists on screen (no spinner)
  final bool silent;
  const FetchVendorOrders({this.silent = false});
  @override
  List<Object?> get props => [silent];
}

/// Next page of delivered / cancelled orders
class LoadMoreVendorOrderHistory extends VendorOrderEvent {
  const LoadMoreVendorOrderHistory();
}

/// Re-read one order (after a socket event, a notification or an action)
class RefreshVendorOrder extends VendorOrderEvent {
  final int orderId;
  const RefreshVendorOrder(this.orderId);
  @override
  List<Object?> get props => [orderId];
}

/// Forget the loaded orders (a staff member who can't see orders switched in)
class ClearVendorOrders extends VendorOrderEvent {
  const ClearVendorOrders();
}

/// Packing checklist: tick / untick every unit of one line
class PackOrderItem extends VendorOrderEvent {
  final int orderId;
  final int itemId;
  final bool packed;
  const PackOrderItem({required this.orderId, required this.itemId, required this.packed});
  @override
  List<Object?> get props => [orderId, itemId, packed];
}

/// Packing checklist: a scanned barcode packs one unit of that line
class ScanPackOrder extends VendorOrderEvent {
  final int orderId;
  final String barcode;
  const ScanPackOrder({required this.orderId, required this.barcode});
  @override
  List<Object?> get props => [orderId, barcode];
}

class ApproveVendorOrder extends VendorOrderEvent {
  final int orderId;
  const ApproveVendorOrder({required this.orderId});
  @override
  List<Object?> get props => [orderId];
}

class RejectVendorOrder extends VendorOrderEvent {
  final int orderId;
  const RejectVendorOrder({required this.orderId});
  @override
  List<Object?> get props => [orderId];
}

class MarkOrderPreparing extends VendorOrderEvent {
  final int orderId;
  const MarkOrderPreparing({required this.orderId});
  @override
  List<Object?> get props => [orderId];
}

class MarkOrderReadyForPickup extends VendorOrderEvent {
  final int orderId;
  /// Delivery orders are broadcast to nearby riders; self-pickup waits for the customer
  final bool isDelivery;
  const MarkOrderReadyForPickup({required this.orderId, this.isDelivery = false});
  @override
  List<Object?> get props => [orderId];
}

// States
abstract class VendorOrderState extends Equatable {
  const VendorOrderState();
  @override
  List<Object?> get props => [];
}

class VendorOrderInitial extends VendorOrderState {}
class VendorOrderLoading extends VendorOrderState {}

/// The lists live on the bloc (activeOrders / historyOrders); the revision
/// changes with every update so each one rebuilds the screen.
class VendorOrderLoaded extends VendorOrderState {
  final int revision;
  const VendorOrderLoaded({required this.revision});
  @override
  List<Object?> get props => [revision];
}

class VendorOrderError extends VendorOrderState {
  final String message;
  const VendorOrderError({required this.message});
  @override
  List<Object?> get props => [message];
}

class VendorOrderActionSuccess extends VendorOrderState {
  final String message;
  const VendorOrderActionSuccess({required this.message});
  @override
  List<Object?> get props => [message, identityHashCode(this)];
}

class VendorOrderActionError extends VendorOrderState {
  final String message;
  /// API error code: WRONG_ITEM, ALREADY_PACKED, PACKING_INCOMPLETE, STAFF_FORBIDDEN…
  final String? code;
  /// PACKING_INCOMPLETE: "2 × Milk" lines still to pack
  final List<String> missing;
  const VendorOrderActionError({required this.message, this.code, this.missing = const []});

  factory VendorOrderActionError.from(Object e) {
    final data = ApiService.getErrorData(e);
    return VendorOrderActionError(
      message: ApiService.getErrorMessage(e),
      code: data?['code'] as String?,
      missing: (data?['missing'] as List? ?? const [])
          .whereType<Map>()
          .map((m) => '${toInt(m['missing'])} × ${m['product_name'] ?? 'item'}')
          .toList(),
    );
  }

  @override
  List<Object?> get props => [message, code, identityHashCode(this)];
}

// BLoC
class VendorOrderBloc extends Bloc<VendorOrderEvent, VendorOrderState> {
  static const int historyPageSize = 20;

  final ApiService _api = ApiService();
  StreamSubscription<OrderUpdateEvent>? _orderSub;
  StreamSubscription<NotificationModel>? _notificationSub;
  Timer? _refreshDebounce;
  final Set<int> _pendingRefresh = {};

  final VendorOrderLists _lists = VendorOrderLists();
  bool _hasLoaded = false;
  bool _loadingMoreHistory = false;
  String? _historyError;
  int _revision = 0;

  /// Checklist lines with a pack request in flight, and orders being scanned
  final Set<int> _packingItems = {};
  final Set<int> _scanningOrders = {};
  bool isPackingItem(int itemId) => _packingItems.contains(itemId);
  bool isScanningOrder(int orderId) => _scanningOrders.contains(orderId);

  /// Orders re-read while a full fetch is in flight are newer than its
  /// snapshot, so they are re-applied on top of it (null = removed)
  Map<int, OrderModel?>? _refreshedDuringFetch;

  /// Every in-progress order (not paged — the dashboard counts come from here)
  List<OrderModel> get activeOrders => _lists.active;

  /// Delivered / cancelled orders loaded so far, newest first
  List<OrderModel> get historyOrders => _lists.history;
  bool get hasMoreHistory => _lists.historyHasMore;
  bool get isLoadingMoreHistory => _loadingMoreHistory;

  /// Why the last "load more" failed, if it did
  String? get historyError => _historyError;
  bool get hasLoaded => _hasLoaded;

  VendorOrderBloc() : super(VendorOrderInitial()) {
    on<FetchVendorOrders>(_onFetch);
    on<LoadMoreVendorOrderHistory>(_onLoadMore);
    on<RefreshVendorOrder>((event, emit) => _refreshOrder(event.orderId, emit));
    on<ApproveVendorOrder>(_onApprove);
    on<RejectVendorOrder>(_onReject);
    on<MarkOrderPreparing>(_onPrepare);
    on<MarkOrderReadyForPickup>(_onReadyPickup);
    on<ClearVendorOrders>(_onClear);
    on<PackOrderItem>(_onPackItem);
    on<ScanPackOrder>(_onScanPack);

    // One order change usually arrives as both an order:update and a
    // notification — debounce so each order is re-read once.
    _orderSub = RealtimeService().orderUpdates.listen((e) => _scheduleRefresh(e.orderId));
    _notificationSub = RealtimeService().notifications.listen((n) {
      if (n.orderId != null) _scheduleRefresh(n.orderId!);
    });
    // Events sent while the socket was down are lost — catch up on reconnect
    RealtimeService().connected.addListener(_onConnectionChanged);
  }

  void _onConnectionChanged() {
    if (RealtimeService().connected.value && _hasLoaded && !isClosed) {
      add(const FetchVendorOrders(silent: true));
    }
  }

  void _scheduleRefresh(int orderId) {
    if (!_hasLoaded) return;
    _pendingRefresh.add(orderId);
    _refreshDebounce?.cancel();
    _refreshDebounce = Timer(const Duration(milliseconds: 400), () {
      final ids = _pendingRefresh.toList();
      _pendingRefresh.clear();
      if (isClosed) return;
      for (final id in ids) {
        add(RefreshVendorOrder(id));
      }
    });
  }

  @override
  Future<void> close() {
    _orderSub?.cancel();
    _notificationSub?.cancel();
    _refreshDebounce?.cancel();
    RealtimeService().connected.removeListener(_onConnectionChanged);
    return super.close();
  }

  void _emitLoaded(Emitter<VendorOrderState> emit) {
    _revision++;
    emit(VendorOrderLoaded(revision: _revision));
  }

  static List<OrderModel> _parseList(dynamic data) => (data as List)
      .map((j) => OrderModel.fromJson(Map<String, dynamic>.from(j as Map)))
      .toList();

  Future<void> _onFetch(FetchVendorOrders event, Emitter<VendorOrderState> emit) async {
    if (!event.silent) {
      // A full (non-silent) load starts clean, e.g. after signing in as another vendor
      _lists.clear();
      _hasLoaded = false;
      _historyError = null;
    }
    if (!_hasLoaded) emit(VendorOrderLoading());
    _refreshedDuringFetch ??= {};
    try {
      final results = await Future.wait([
        _api.get(ApiConfig.vendorOrders, queryParams: {'scope': 'active'}),
        _api.get(ApiConfig.vendorOrders,
            queryParams: {'scope': 'history', 'limit': historyPageSize, 'offset': 0}),
      ]);
      final activeBody = results[0].data;
      final historyBody = results[1].data;
      if (activeBody['success'] != true || historyBody['success'] != true) {
        _refreshedDuringFetch = null;
        if (event.silent && _hasLoaded) return;
        emit(VendorOrderError(
            message: activeBody['message'] ?? historyBody['message'] ?? 'Failed to load orders'));
        return;
      }

      _lists.active = _parseList(activeBody['data']);
      _lists.setHistoryFirstPage(_parseList(historyBody['data']), PageMeta.fromResponse(historyBody));
      _historyError = null;
      _hasLoaded = true;

      final newer = _refreshedDuringFetch ?? const <int, OrderModel?>{};
      _refreshedDuringFetch = null;
      newer.forEach((id, order) => order == null ? _lists.remove(id) : _lists.upsert(order));

      _emitLoaded(emit);
    } catch (e) {
      _refreshedDuringFetch = null;
      if (event.silent && _hasLoaded) return; // keep the last good lists
      emit(VendorOrderError(message: ApiService.getErrorMessage(e)));
    }
  }

  Future<void> _onLoadMore(LoadMoreVendorOrderHistory event, Emitter<VendorOrderState> emit) async {
    if (!_hasLoaded || !_lists.historyHasMore || _loadingMoreHistory) return;
    _loadingMoreHistory = true;
    _historyError = null;
    _emitLoaded(emit);
    try {
      final response = await _api.get(ApiConfig.vendorOrders, queryParams: {
        'scope': 'history',
        'limit': historyPageSize,
        'offset': _lists.historyNextOffset ?? _lists.history.length,
      });
      if (response.data['success'] == true) {
        _lists.appendHistoryPage(_parseList(response.data['data']), PageMeta.fromResponse(response.data));
      } else {
        _historyError = response.data['message'] ?? "Couldn't load more orders";
      }
    } catch (e) {
      _historyError = ApiService.getErrorMessage(e);
    } finally {
      _loadingMoreHistory = false;
      _emitLoaded(emit);
    }
  }

  /// GET /api/vendor/orders/:id and put the order in the right list
  Future<void> _refreshOrder(int orderId, Emitter<VendorOrderState> emit) async {
    if (!_hasLoaded) return;
    try {
      final response = await _api.get(ApiConfig.vendorOrder(orderId));
      if (response.data['success'] != true) return;
      final order = OrderModel.fromJson(Map<String, dynamic>.from(response.data['data'] as Map));
      _refreshedDuringFetch?[order.id] = order;
      _lists.upsert(order);
      _emitLoaded(emit);
    } catch (e) {
      if (e is DioException && e.response?.statusCode == 404) {
        // Not (or no longer) one of this store's orders
        _refreshedDuringFetch?[orderId] = null;
        _lists.remove(orderId);
        _emitLoaded(emit);
      }
      // Network errors: keep what we have; the next event or a pull-to-refresh catches up
    }
  }

  /// Runs one workflow step, reports it, then re-reads that order.
  /// The order is re-read on failure too (e.g. 409: someone else already moved it).
  Future<void> _runAction(
    Emitter<VendorOrderState> emit, {
    required int orderId,
    required Future<Response> Function() request,
    required String successMessage,
    required String failureMessage,
  }) async {
    try {
      final response = await request();
      if (response.data['success'] == true) {
        emit(VendorOrderActionSuccess(message: successMessage));
      } else {
        emit(VendorOrderActionError(message: response.data['message'] ?? failureMessage));
      }
    } catch (e) {
      emit(VendorOrderActionError.from(e));
    }
    await _refreshOrder(orderId, emit);
  }

  void _onClear(ClearVendorOrders event, Emitter<VendorOrderState> emit) {
    _lists.clear();
    _hasLoaded = false;
    _historyError = null;
    _pendingRefresh.clear();
    emit(VendorOrderInitial());
  }

  /// PUT …/items/:itemId/pack — the order is then re-read for the new counts
  Future<void> _onPackItem(PackOrderItem event, Emitter<VendorOrderState> emit) async {
    if (!_packingItems.add(event.itemId)) return;
    _emitLoaded(emit);
    try {
      await _api.put(ApiConfig.packOrderItem(event.orderId, event.itemId), data: {'packed': event.packed});
    } catch (e) {
      emit(VendorOrderActionError.from(e));
    } finally {
      _packingItems.remove(event.itemId);
    }
    await _refreshOrder(event.orderId, emit);
    _emitLoaded(emit);
  }

  /// POST …/scan — 422 WRONG_ITEM (not in this order), 409 ALREADY_PACKED
  Future<void> _onScanPack(ScanPackOrder event, Emitter<VendorOrderState> emit) async {
    final code = event.barcode.trim();
    if (code.isEmpty || !_scanningOrders.add(event.orderId)) return;
    _emitLoaded(emit);
    try {
      final response = await _api.post(ApiConfig.scanPackOrder(event.orderId), data: {'barcode': code});
      // e.g. "Milk 1L: 2/3 packed."
      emit(VendorOrderActionSuccess(message: response.data['message'] ?? 'Packed one item.'));
    } catch (e) {
      emit(VendorOrderActionError.from(e));
    } finally {
      _scanningOrders.remove(event.orderId);
    }
    await _refreshOrder(event.orderId, emit);
    _emitLoaded(emit);
  }

  Future<void> _onApprove(ApproveVendorOrder event, Emitter<VendorOrderState> emit) => _runAction(
        emit,
        orderId: event.orderId,
        request: () => _api.put(ApiConfig.approveOrder(event.orderId)),
        successMessage: 'Order approved! ✅',
        failureMessage: 'Failed to approve',
      );

  Future<void> _onReject(RejectVendorOrder event, Emitter<VendorOrderState> emit) => _runAction(
        emit,
        orderId: event.orderId,
        request: () => _api.put(ApiConfig.rejectOrder(event.orderId)),
        successMessage: 'Order rejected. Stock released.',
        failureMessage: 'Failed to reject',
      );

  Future<void> _onPrepare(MarkOrderPreparing event, Emitter<VendorOrderState> emit) => _runAction(
        emit,
        orderId: event.orderId,
        request: () => _api.put(ApiConfig.prepareOrder(event.orderId)),
        successMessage: 'Order packed. Mark it ready when it can be collected.',
        failureMessage: 'Failed to update order',
      );

  Future<void> _onReadyPickup(MarkOrderReadyForPickup event, Emitter<VendorOrderState> emit) => _runAction(
        emit,
        orderId: event.orderId,
        request: () => _api.put(ApiConfig.readyForPickupOrder(event.orderId)),
        successMessage: event.isDelivery
            ? 'Ready for pickup — nearby riders have been notified.'
            : 'Ready for pickup — the customer has been notified to collect it.',
        failureMessage: 'Failed to update order',
      );
}
