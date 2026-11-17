// ══════════════════════════════════════════════════════════════
// Vendra App - Store Reviews BLoC (SRDS §2.3)
// GET /api/vendors/:id/reviews?limit=&offset= (paged, newest first): the
// reviews of every product the store sells. The list grows with infinite
// scroll while meta.hasMore is true. Same state as the product reviews.
// ══════════════════════════════════════════════════════════════

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:vendra_customer/vendra_core.dart';

import '../services/catalog_api.dart';
import 'product_reviews_bloc.dart';

// ── Events ──
abstract class StoreReviewsEvent extends Equatable {
  const StoreReviewsEvent();
  @override
  List<Object?> get props => [];
}

/// First page (open, pull-to-refresh)
class LoadStoreReviews extends StoreReviewsEvent {
  const LoadStoreReviews();
}

/// Next page, when the list is scrolled near its end
class LoadMoreStoreReviews extends StoreReviewsEvent {
  const LoadMoreStoreReviews();
}

// ── BLoC ── (state: the paged review list shared with product reviews)
class StoreReviewsBloc extends Bloc<StoreReviewsEvent, ProductReviewsState> {
  static const pageSize = 20;

  final int vendorId;

  StoreReviewsBloc({required this.vendorId}) : super(const ProductReviewsState(loading: true)) {
    on<LoadStoreReviews>(_onLoad);
    on<LoadMoreStoreReviews>(_onLoadMore);
  }

  Future<(List<ReviewModel>, PageMeta)> _page(int offset) =>
      CatalogApi.instance.storeReviews(vendorId, limit: pageSize, offset: offset);

  Future<void> _onLoad(LoadStoreReviews event, Emitter<ProductReviewsState> emit) async {
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

  Future<void> _onLoadMore(LoadMoreStoreReviews event, Emitter<ProductReviewsState> emit) async {
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
