// ══════════════════════════════════════════════════════════════
// Vendra App - Product Detail BLoC (FR01/FR06)
// GET /api/products/:id → the product with its photo gallery (images,
// cover first), rating breakdown (ratingDistribution) and latestReviews.
// The screen opens straight away with the product from the list; the
// details fill in when they arrive. Public stock stays live through
// realtime stock:update events.
// It also asks GET /api/customer/products/:id/review-order whether the
// customer has a delivered order with this product still to review
// (reviewOrderId → the page's "Write a review" button).
// ══════════════════════════════════════════════════════════════

import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:vendra_customer/vendra_core.dart';

import '../services/catalog_api.dart';

/// The extra product-page data from GET /api/products/:id
class ProductDetails {
  final ProductModel product;
  final List<String> images;

  /// Number of reviews per star, 5 → 1 (every key present)
  final Map<int, int> distribution;
  final List<ReviewModel> latestReviews;

  const ProductDetails({
    required this.product,
    this.images = const [],
    this.distribution = const {5: 0, 4: 0, 3: 0, 2: 0, 1: 0},
    this.latestReviews = const [],
  });

  factory ProductDetails.fromJson(Map<String, dynamic> json) {
    final product = ProductModel.fromJson(json);
    final rawImages = json['images'];
    final images = rawImages is List
        ? rawImages.map((u) => u?.toString() ?? '').where((u) => u.isNotEmpty).toSet().toList()
        : product.allImages;

    final distribution = ratingDistributionFrom(json['ratingDistribution']);

    final reviews = (json['latestReviews'] as List<dynamic>? ?? const [])
        .whereType<Map>()
        .map((r) => ReviewModel.fromJson(Map<String, dynamic>.from(r)))
        .toList();

    return ProductDetails(product: product, images: images, distribution: distribution, latestReviews: reviews);
  }

  /// Reviews counted in the breakdown (falls back to the product's count)
  int get totalRatings {
    final sum = distribution.values.fold(0, (a, b) => a + b);
    return sum > 0 ? sum : product.ratingCount;
  }

  ProductDetails withProduct(ProductModel p) =>
      ProductDetails(product: p, images: images, distribution: distribution, latestReviews: latestReviews);
}

/// Reviews per star (5 → 1, every key present) from an API
/// `ratingDistribution`; JSON object keys arrive as strings ("5": 12)
Map<int, int> ratingDistributionFrom(dynamic raw) {
  final distribution = {5: 0, 4: 0, 3: 0, 2: 0, 1: 0};
  if (raw is Map) {
    raw.forEach((k, v) {
      final star = toIntOrNull(k);
      if (star != null && distribution.containsKey(star)) distribution[star] = toInt(v);
    });
  }
  return distribution;
}

/// Share of reviews with [star] stars (0..1) for the breakdown bars
double ratingFraction(Map<int, int> distribution, int star) {
  final total = distribution.values.fold(0, (a, b) => a + b);
  if (total == 0) return 0;
  return (distribution[star] ?? 0) / total;
}

// ── Events ──
abstract class ProductDetailEvent extends Equatable {
  const ProductDetailEvent();
  @override
  List<Object?> get props => [];
}

class LoadProductDetail extends ProductDetailEvent {
  const LoadProductDetail();
}

class _StockChanged extends ProductDetailEvent {
  final int publicStock;
  const _StockChanged(this.publicStock);
  @override
  List<Object?> get props => [publicStock];
}

// ── State ──
class ProductDetailState extends Equatable {
  /// Always set: the list's copy until the details arrive, then the fresh one
  final ProductModel product;
  final ProductDetails? details;
  final bool loading;
  final String? error;

  /// The customer's delivered order with this product that they haven't
  /// reviewed yet (null: nothing to review, or not known yet)
  final int? reviewOrderId;

  const ProductDetailState({required this.product, this.details, this.loading = false, this.error, this.reviewOrderId});

  /// Photos to swipe through (cover first)
  List<String> get images => details?.images ?? product.allImages;

  @override
  List<Object?> get props =>
      [product.publicStock, product.averageRating, product.ratingCount, details, loading, error, reviewOrderId];
}

// ── BLoC ──
class ProductDetailBloc extends Bloc<ProductDetailEvent, ProductDetailState> {
  StreamSubscription<StockUpdateEvent>? _stockSub;

  ProductDetailBloc({required ProductModel product}) : super(ProductDetailState(product: product, loading: true)) {
    on<LoadProductDetail>(_onLoad);
    on<_StockChanged>(_onStock);
    _stockSub = RealtimeService()
        .stockUpdates
        .where((e) => e.productId == product.id)
        .listen((e) => add(_StockChanged(e.publicStock)));
  }

  Future<void> _onLoad(LoadProductDetail event, Emitter<ProductDetailState> emit) async {
    final api = CatalogApi.instance;
    emit(ProductDetailState(
        product: state.product, details: state.details, loading: true, reviewOrderId: state.reviewOrderId));
    // Asked alongside the details; any failure just means no "Write a review"
    final reviewOrder = api.reviewOrderId(state.product.id).then<int?>((id) => id, onError: (_) => null);
    try {
      final details = ProductDetails.fromJson(await api.product(state.product.id));
      emit(ProductDetailState(product: details.product, details: details, reviewOrderId: await reviewOrder));
    } catch (e) {
      emit(ProductDetailState(
        product: state.product,
        details: state.details,
        error: ApiService.getErrorMessage(e),
        reviewOrderId: await reviewOrder,
      ));
    }
  }

  void _onStock(_StockChanged event, Emitter<ProductDetailState> emit) {
    final product = state.product.withStock(publicStock: event.publicStock);
    emit(ProductDetailState(
      product: product,
      details: state.details?.withProduct(product),
      loading: state.loading,
      error: state.error,
      reviewOrderId: state.reviewOrderId,
    ));
  }

  @override
  Future<void> close() {
    _stockSub?.cancel();
    return super.close();
  }
}
