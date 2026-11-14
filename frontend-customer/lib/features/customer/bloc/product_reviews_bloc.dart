// ══════════════════════════════════════════════════════════════
// Vendra App - Product Reviews BLoC (SRDS §2.3)
// GET /api/products/:id/reviews?limit=&offset= (paged, newest first).
// The list grows with infinite scroll while meta.hasMore is true.
// ══════════════════════════════════════════════════════════════

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:vendra_customer/vendra_core.dart';

// ── Events ──
abstract class ProductReviewsEvent extends Equatable {
  const ProductReviewsEvent();
  @override
  List<Object?> get props => [];
}

/// First page (open, pull-to-refresh)
class LoadProductReviews extends ProductReviewsEvent {
  const LoadProductReviews();
}

/// Next page, when the list is scrolled near its end
class LoadMoreProductReviews extends ProductReviewsEvent {
  const LoadMoreProductReviews();
}

// ── State ──
class ProductReviewsState extends Equatable {
  final List<ReviewModel> reviews;
  final bool loading;
  final bool loadingMore;
  final bool hasMore;
  final int nextOffset;
  final String? error;

  const ProductReviewsState({
    this.reviews = const [],
    this.loading = false,
    this.loadingMore = false,
    this.hasMore = false,
    this.nextOffset = 0,
    this.error,
  });

  ProductReviewsState copyWith({
    List<ReviewModel>? reviews,
    bool? loading,
    bool? loadingMore,
    bool? hasMore,
    int? nextOffset,
    String? error,
    bool clearError = false,
  }) =>
      ProductReviewsState(
        reviews: reviews ?? this.reviews,
        loading: loading ?? this.loading,
        loadingMore: loadingMore ?? this.loadingMore,
        hasMore: hasMore ?? this.hasMore,
        nextOffset: nextOffset ?? this.nextOffset,
        error: clearError ? null : (error ?? this.error),
      );

  @override
  List<Object?> get props => [reviews.map((r) => r.id).join(','), loading, loadingMore, hasMore, nextOffset, error];
}

// ── BLoC ──
class ProductReviewsBloc extends Bloc<ProductReviewsEvent, ProductReviewsState> {
  static const pageSize = 20;

  final int productId;
  final ApiService _api = ApiService();

  ProductReviewsBloc({required this.productId}) : super(const ProductReviewsState(loading: true)) {
    on<LoadProductReviews>(_onLoad);
    on<LoadMoreProductReviews>(_onLoadMore);
  }

  Future<(List<ReviewModel>, PageMeta)> _page(int offset) async {
    final res = await _api.get(ApiConfig.productReviews(productId), queryParams: {'limit': pageSize, 'offset': offset});
    if (res.data['success'] != true) throw Exception(res.data['message'] ?? 'Could not load reviews');
    final reviews = (res.data['data'] as List<dynamic>? ?? const [])
        .whereType<Map>()
        .map((r) => ReviewModel.fromJson(Map<String, dynamic>.from(r)))
        .toList();
    return (reviews, PageMeta.fromResponse(res.data));
  }

  Future<void> _onLoad(LoadProductReviews event, Emitter<ProductReviewsState> emit) async {
    emit(state.copyWith(loading: state.reviews.isEmpty, clearError: true));
    try {
      final (reviews, meta) = await _page(0);
      emit(ProductReviewsState(
        reviews: reviews,
        hasMore: meta.hasMore,
        nextOffset: meta.nextOffset ?? reviews.length,
      ));
    } catch (e) {
      emit(state.copyWith(loading: false, error: ApiService.getErrorMessage(e)));
    }
  }

  Future<void> _onLoadMore(LoadMoreProductReviews event, Emitter<ProductReviewsState> emit) async {
    if (!state.hasMore || state.loadingMore || state.loading) return;
    emit(state.copyWith(loadingMore: true));
    try {
      final (page, meta) = await _page(state.nextOffset);
      final known = state.reviews.map((r) => r.id).toSet();
      emit(state.copyWith(
        reviews: [...state.reviews, ...page.where((r) => !known.contains(r.id))],
        hasMore: meta.hasMore && page.isNotEmpty,
        nextOffset: meta.nextOffset ?? state.nextOffset + page.length,
        loadingMore: false,
      ));
    } catch (_) {
      // Stop auto-loading after a failure; pull-to-refresh starts over
      emit(state.copyWith(loadingMore: false, hasMore: false));
    }
  }
}
