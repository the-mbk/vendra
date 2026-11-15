// ══════════════════════════════════════════════════════════════
// Vendra App - Product Reviews Screen (FR06 / SRDS §2.3)
// Every review of one product, newest first, with the rating summary on
// top. Pages load with infinite scroll; pull to refresh starts over.
// ══════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:vendra_customer/vendra_core.dart';

import '../bloc/product_detail_bloc.dart';
import '../bloc/product_reviews_bloc.dart';
import '../widgets/rating_summary.dart';

class ProductReviewsScreen extends StatelessWidget {
  final ProductModel product;

  /// The breakdown from the product page, when it has loaded
  final ProductDetails? details;

  const ProductReviewsScreen({super.key, required this.product, this.details});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => ProductReviewsBloc(productId: product.id)..add(const LoadProductReviews()),
      child: _ProductReviewsView(product: product, details: details),
    );
  }
}

class _ProductReviewsView extends StatefulWidget {
  final ProductModel product;
  final ProductDetails? details;
  const _ProductReviewsView({required this.product, this.details});

  @override
  State<_ProductReviewsView> createState() => _ProductReviewsViewState();
}

class _ProductReviewsViewState extends State<_ProductReviewsView> {
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_maybeLoadMore);
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _maybeLoadMore() {
    if (!_scroll.hasClients) return;
    final s = context.read<ProductReviewsBloc>().state;
    if (!s.hasMore || s.loadingMore) return;
    if (_scroll.position.extentAfter < 400) context.read<ProductReviewsBloc>().add(const LoadMoreProductReviews());
  }

  @override
  Widget build(BuildContext context) {
    final product = widget.details?.product ?? widget.product;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text('Reviews', style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
      ),
      body: BlocBuilder<ProductReviewsBloc, ProductReviewsState>(
        builder: (context, state) {
          // A short first page may not fill the screen, so nothing would scroll
          if (state.hasMore && !state.loadingMore) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) _maybeLoadMore();
            });
          }

          final header = Container(
            color: Colors.white,
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(product.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w600)),
                const SizedBox(height: 12),
                RatingSummary(
                  average: product.averageRating,
                  count: widget.details?.totalRatings ?? product.ratingCount,
                  distribution: widget.details?.distribution ?? const {},
                ),
              ],
            ),
          );

          Widget body;
          if (state.loading) {
            body = const Padding(
              padding: EdgeInsets.all(32),
              child: Center(child: CircularProgressIndicator(color: AppColors.primary)),
            );
          } else if (state.error != null && state.reviews.isEmpty) {
            body = Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  Text(state.error!, textAlign: TextAlign.center),
                  TextButton(
                    onPressed: () => context.read<ProductReviewsBloc>().add(const LoadProductReviews()),
                    child: const Text('Retry'),
                  ),
                ],
              ),
            );
          } else if (state.reviews.isEmpty) {
            body = Padding(
              padding: const EdgeInsets.only(top: 48),
              child: Column(
                children: [
                  Icon(Icons.rate_review_outlined, size: 56, color: Colors.grey.shade300),
                  const SizedBox(height: 12),
                  Text('No reviews yet', style: GoogleFonts.poppins(color: AppColors.textSecondary)),
                ],
              ),
            );
          } else {
            body = Container(
              color: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                children: [
                  for (var i = 0; i < state.reviews.length; i++) ...[
                    if (i > 0) const Divider(height: 1),
                    ReviewTile(review: state.reviews[i]),
                  ],
                ],
              ),
            );
          }

          return RefreshIndicator(
            color: AppColors.primary,
            onRefresh: () async => context.read<ProductReviewsBloc>().add(const LoadProductReviews()),
            child: ListView(
              controller: _scroll,
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                header,
                const SizedBox(height: 8),
                body,
                if (state.loadingMore)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: Center(
                      child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2)),
                    ),
                  ),
                const SizedBox(height: 24),
              ],
            ),
          );
        },
      ),
    );
  }
}
