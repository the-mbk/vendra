// ══════════════════════════════════════════════════════════════
// Vendra App - Store Reviews Screen (SRDS §2.3)
// Every review of a store's products, newest first, each labelled with
// the product it's about, under the store's rating summary. Pages load
// with infinite scroll; pull to refresh starts over.
// ══════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:vendra_customer/vendra_core.dart';

import '../bloc/product_reviews_bloc.dart';
import '../bloc/store_reviews_bloc.dart';
import '../widgets/rating_summary.dart';

class StoreReviewsScreen extends StatelessWidget {
  final int vendorId;
  final String storeName;
  final String? logoUrl;
  final double? averageRating;
  final int ratingCount;

  /// Reviews per star from the store page (5 → 1)
  final Map<int, int> distribution;

  const StoreReviewsScreen({
    super.key,
    required this.vendorId,
    required this.storeName,
    this.logoUrl,
    this.averageRating,
    this.ratingCount = 0,
    this.distribution = const {},
  });

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => StoreReviewsBloc(vendorId: vendorId)..add(const LoadStoreReviews()),
      child: _StoreReviewsView(screen: this),
    );
  }
}

class _StoreReviewsView extends StatefulWidget {
  final StoreReviewsScreen screen;
  const _StoreReviewsView({required this.screen});

  @override
  State<_StoreReviewsView> createState() => _StoreReviewsViewState();
}

class _StoreReviewsViewState extends State<_StoreReviewsView> {
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
    final s = context.read<StoreReviewsBloc>().state;
    if (!s.hasMore || s.loadingMore) return;
    if (_scroll.position.extentAfter < 400) context.read<StoreReviewsBloc>().add(const LoadMoreStoreReviews());
  }

  @override
  Widget build(BuildContext context) {
    final store = widget.screen;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text('Store reviews', style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
      ),
      body: BlocBuilder<StoreReviewsBloc, ProductReviewsState>(
        builder: (context, state) {
          // A short first page may not fill the screen, so nothing would scroll
          if (state.hasMore && !state.loadingMore) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) _maybeLoadMore();
            });
          }

          final header = Container(
            color: AppColors.surface,
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    StoreLogo(storeName: store.storeName, logoUrl: store.logoUrl, size: 36),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(store.storeName,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w600)),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                RatingSummary(
                  average: store.averageRating,
                  count: store.ratingCount,
                  distribution: store.distribution,
                  emptyText: 'No reviews yet. Customers can rate what they buy here once it\'s delivered.',
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
                    onPressed: () => context.read<StoreReviewsBloc>().add(const LoadStoreReviews()),
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
                  Icon(Icons.rate_review_outlined, size: 56, color: AppColors.textLight),
                  const SizedBox(height: 12),
                  Text('No reviews yet', style: GoogleFonts.poppins(color: AppColors.textSecondary)),
                ],
              ),
            );
          } else {
            body = Container(
              color: AppColors.surface,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                children: [
                  for (var i = 0; i < state.reviews.length; i++) ...[
                    if (i > 0) const Divider(height: 1),
                    ReviewTile(review: state.reviews[i], showProduct: true),
                  ],
                ],
              ),
            );
          }

          return RefreshIndicator(
            color: AppColors.primary,
            onRefresh: () async => context.read<StoreReviewsBloc>().add(const LoadStoreReviews()),
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
