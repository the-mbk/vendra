// ══════════════════════════════════════════════════════════════
// Vendra App - Customer Product BLoC
// Fetches, searches and filters (by category) marketplace products (FR06).
// GET /api/products is paged: the first page loads with the filters and
// LoadMoreProducts appends the next one (infinite scroll) while the
// server reports hasMore. Public stock stays live from the realtime
// socket (FR01/PR01):
//   stock:update   → patch the visible stock, drop products that hit 0
//   catalog:update → refetch page 1 with the current filters
// ══════════════════════════════════════════════════════════════

import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:vendra_customer/vendra_core.dart';

// ── Events ──
abstract class CustomerProductEvent extends Equatable {
  const CustomerProductEvent();
  @override
  List<Object?> get props => [];
}

/// Loads the first page for these filters (a new search/category starts over)
class FetchProducts extends CustomerProductEvent {
  final String? search;
  final int? vendorId;
  final int? categoryId;

  /// Refresh in place (no loading shimmer), e.g. after a catalog change
  final bool silent;

  const FetchProducts({this.search, this.vendorId, this.categoryId, this.silent = false});

  FetchProducts asSilent() => FetchProducts(search: search, vendorId: vendorId, categoryId: categoryId, silent: true);

  @override
  List<Object?> get props => [search, vendorId, categoryId, silent];
}

/// Appends the next page of the current query (infinite scroll)
class LoadMoreProducts extends CustomerProductEvent {
  const LoadMoreProducts();
}

class _StockChanged extends CustomerProductEvent {
  final int productId;
  final int publicStock;
  const _StockChanged(this.productId, this.publicStock);
  @override
  List<Object?> get props => [productId, publicStock];
}

class _CatalogChanged extends CustomerProductEvent {
  const _CatalogChanged();
}

// ── States ──
abstract class CustomerProductState extends Equatable {
  const CustomerProductState();
  @override
  List<Object?> get props => [];
}

class CustomerProductInitial extends CustomerProductState {}
class CustomerProductLoading extends CustomerProductState {}

class CustomerProductLoaded extends CustomerProductState {
  final List<ProductModel> products;
  final String? search;
  final int? categoryId;

  /// Paging: the server has more products starting at [nextOffset]
  final bool hasMore;
  final int nextOffset;

  /// A "load more" request is in flight (shows the small loader at the end)
  final bool loadingMore;

  const CustomerProductLoaded({
    required this.products,
    this.search,
    this.categoryId,
    this.hasMore = false,
    this.nextOffset = 0,
    this.loadingMore = false,
  });

  CustomerProductLoaded copyWith({
    List<ProductModel>? products,
    bool? hasMore,
    int? nextOffset,
    bool? loadingMore,
  }) =>
      CustomerProductLoaded(
        products: products ?? this.products,
        search: search,
        categoryId: categoryId,
        hasMore: hasMore ?? this.hasMore,
        nextOffset: nextOffset ?? this.nextOffset,
        loadingMore: loadingMore ?? this.loadingMore,
      );

  CustomerProductLoaded withProducts(List<ProductModel> next) => copyWith(products: next);

  @override
  List<Object?> get props => [
        // Stock is part of the signature so live updates rebuild the list
        products.map((p) => '${p.id}:${p.publicStock}').join(','),
        search,
        categoryId,
        hasMore,
        nextOffset,
        loadingMore,
      ];
}

class CustomerProductError extends CustomerProductState {
  final String message;
  const CustomerProductError({required this.message});
  @override
  List<Object?> get props => [message];
}

// ── BLoC ──
class CustomerProductBloc extends Bloc<CustomerProductEvent, CustomerProductState> {
  static const pageSize = 20;

  final ApiService _api = ApiService();

  FetchProducts _lastQuery = const FetchProducts();

  /// Bumped whenever the list restarts from page 1, so a slow "load more"
  /// for the previous filters can't append stale rows.
  int _generation = 0;

  /// Products removed from the list because they sold out — if one comes back
  /// in stock we refetch, since the list no longer holds its details.
  final Set<int> _soldOut = {};

  StreamSubscription<StockUpdateEvent>? _stockSub;
  StreamSubscription<void>? _catalogSub;
  Timer? _refetchTimer;

  CustomerProductBloc() : super(CustomerProductInitial()) {
    on<FetchProducts>(_onFetch);
    on<LoadMoreProducts>(_onLoadMore);
    on<_StockChanged>(_onStockChanged);
    on<_CatalogChanged>((_, __) => _scheduleRefetch());

    _stockSub = RealtimeService().stockUpdates.listen((e) => add(_StockChanged(e.productId, e.publicStock)));
    _catalogSub = RealtimeService().catalogUpdates.listen((_) => add(const _CatalogChanged()));
  }

  Future<(List<ProductModel>, PageMeta)> _loadPage(FetchProducts query, int offset) async {
    final queryParams = <String, dynamic>{'limit': pageSize, 'offset': offset};
    if (query.search != null && query.search!.isNotEmpty) {
      queryParams['search'] = query.search;
    }
    if (query.vendorId != null) {
      queryParams['vendor_id'] = query.vendorId;
    }
    if (query.categoryId != null) {
      queryParams['category_id'] = query.categoryId;
    }

    final response = await _api.get(ApiConfig.products, queryParams: queryParams);
    if (response.data['success'] != true) {
      throw Exception(response.data['message'] ?? 'Failed to load products');
    }
    final products = (response.data['data'] as List)
        .map((json) => ProductModel.fromJson(Map<String, dynamic>.from(json)))
        .where((p) => p.publicStock > 0)
        .toList();
    return (products, PageMeta.fromResponse(response.data));
  }

  Future<void> _onFetch(FetchProducts event, Emitter<CustomerProductState> emit) async {
    _lastQuery = event;
    final generation = ++_generation;
    if (!event.silent) emit(CustomerProductLoading());
    try {
      final (products, meta) = await _loadPage(event, 0);
      if (generation != _generation) return;
      _soldOut.clear();
      emit(CustomerProductLoaded(
        products: products,
        search: event.search,
        categoryId: event.categoryId,
        hasMore: meta.hasMore,
        nextOffset: meta.nextOffset ?? products.length,
      ));
    } catch (e) {
      if (generation != _generation) return;
      // A failed background refresh keeps the list the customer is looking at
      if (!event.silent || state is! CustomerProductLoaded) {
        emit(CustomerProductError(message: ApiService.getErrorMessage(e)));
      }
    }
  }

  Future<void> _onLoadMore(LoadMoreProducts event, Emitter<CustomerProductState> emit) async {
    final s = state;
    if (s is! CustomerProductLoaded || !s.hasMore || s.loadingMore) return;
    final generation = _generation;
    emit(s.copyWith(loadingMore: true));
    try {
      final (products, meta) = await _loadPage(_lastQuery, s.nextOffset);
      final current = state;
      if (generation != _generation || current is! CustomerProductLoaded) return;
      final known = current.products.map((p) => p.id).toSet();
      emit(current.copyWith(
        products: [...current.products, ...products.where((p) => !known.contains(p.id))],
        hasMore: meta.hasMore && products.isNotEmpty,
        nextOffset: meta.nextOffset ?? current.nextOffset + products.length,
        loadingMore: false,
      ));
    } catch (_) {
      final current = state;
      if (generation != _generation || current is! CustomerProductLoaded) return;
      // Stop auto-loading after a failure; pull-to-refresh starts over
      emit(current.copyWith(loadingMore: false, hasMore: false));
    }
  }

  void _onStockChanged(_StockChanged event, Emitter<CustomerProductState> emit) {
    final s = state;
    if (s is! CustomerProductLoaded) return;

    final index = s.products.indexWhere((p) => p.id == event.productId);
    if (index < 0) {
      if (event.publicStock > 0 && _soldOut.remove(event.productId)) _scheduleRefetch();
      return;
    }

    final next = List<ProductModel>.from(s.products);
    if (event.publicStock <= 0) {
      next.removeAt(index);
      _soldOut.add(event.productId);
      // The server only lists in-stock products, so everything after this one
      // moved up a place — step the next page back to avoid skipping a product.
      emit(s.copyWith(products: next, nextOffset: s.nextOffset > 0 ? s.nextOffset - 1 : 0));
    } else {
      next[index] = next[index].withStock(publicStock: event.publicStock);
      emit(s.withProducts(next));
    }
  }

  /// Debounced so a burst of catalog events triggers a single request
  void _scheduleRefetch() {
    _refetchTimer?.cancel();
    _refetchTimer = Timer(const Duration(milliseconds: 400), () {
      if (!isClosed) add(_lastQuery.asSilent());
    });
  }

  @override
  Future<void> close() {
    _stockSub?.cancel();
    _catalogSub?.cancel();
    _refetchTimer?.cancel();
    return super.close();
  }
}
