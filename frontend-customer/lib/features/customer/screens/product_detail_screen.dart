// ══════════════════════════════════════════════════════════════
// Vendra App - Product Detail Screen
// Replicates the Stitch product detail design.
// - Photo gallery (cover first) with page dots; tap for full-screen
//   pinch-zoom (FR06)
// - Live public stock via realtime stock:update events, with the dual
//   inventory explainer (FR01)
// - Escrow trust badge (FR03)
// - Rating summary, latest reviews and "See all reviews" (SRDS §2.3)
// Details come from GET /api/products/:id (ProductDetailBloc).
// ══════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:vendra_customer/vendra_core.dart';
import '../bloc/cart_bloc.dart';
import '../bloc/product_detail_bloc.dart';
import '../widgets/product_gallery.dart';
import '../widgets/rating_summary.dart';
import '../widgets/trust_badges.dart';
import 'cart_screen.dart';
import 'product_reviews_screen.dart';

class ProductDetailScreen extends StatelessWidget {
  final ProductModel product;

  const ProductDetailScreen({super.key, required this.product});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => ProductDetailBloc(product: product)..add(const LoadProductDetail()),
      child: const _ProductDetailView(),
    );
  }
}

class _ProductDetailView extends StatelessWidget {
  const _ProductDetailView();

  /// Adds one unit unless the cart already holds every available unit
  bool _addToCart(BuildContext context, ProductModel product) {
    final inCart = context.read<CartBloc>().state.quantityOf(product.id);
    if (product.isOutOfStock || inCart >= product.publicStock) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(product.isOutOfStock
            ? '${product.name} is sold out right now'
            : 'Your cart already has all ${product.publicStock} available'),
        behavior: SnackBarBehavior.floating,
      ));
      return false;
    }
    context.read<CartBloc>().add(AddToCart(product: product));
    return true;
  }

  Widget _stockBadge(ProductModel product) {
    final soldOut = product.isOutOfStock;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: soldOut ? AppColors.stockRed : AppColors.stockGreen,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(soldOut ? Icons.remove_shopping_cart_outlined : Icons.check_circle, color: Colors.white, size: 14),
          const SizedBox(width: 4),
          Text(soldOut ? 'Sold out' : 'In Stock',
              style: GoogleFonts.poppins(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ProductDetailBloc, ProductDetailState>(
      builder: (context, state) {
        final product = state.product;
        return Scaffold(
          backgroundColor: AppColors.background,
          appBar: AppBar(
            title: Text('Product Details', style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
            actions: [
              IconButton(icon: const Icon(Icons.share_outlined), onPressed: () {}),
              IconButton(icon: const Icon(Icons.favorite_border), onPressed: () {}),
            ],
          ),
          body: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Photos: swipe between them, tap to zoom
                ProductGallery(
                  product: product,
                  images: state.images,
                  overlays: [Positioned(top: 16, left: 16, child: _stockBadge(product))],
                ),

                // Product Info
                Container(
                  color: Colors.white,
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Vendor info
                      Row(
                        children: [
                          const Icon(Icons.storefront_outlined, size: 16, color: AppColors.textSecondary),
                          const SizedBox(width: 6),
                          Text('Sold by ', style: GoogleFonts.poppins(fontSize: 13, color: AppColors.textSecondary)),
                          Expanded(
                            child: Text(
                              product.storeName ?? 'Vendor',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.poppins(
                                  fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.secondary),
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 8),

                      // Product name
                      Text(
                        product.name,
                        style: GoogleFonts.poppins(fontSize: 22, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
                      ),

                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 10,
                        runSpacing: 6,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          if (product.ratingCount > 0)
                            RatingBadge(average: product.averageRating, count: product.ratingCount, fontSize: 13),
                          if (product.categoryName != null)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: AppColors.secondary.withValues(alpha: 0.08),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(product.categoryName!,
                                  style: GoogleFonts.poppins(
                                      fontSize: 11, fontWeight: FontWeight.w500, color: AppColors.secondary)),
                            ),
                        ],
                      ),

                      const SizedBox(height: 16),

                      // Price
                      Text(
                        formatRupees(product.price),
                        style: GoogleFonts.poppins(fontSize: 28, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
                      ),

                      const SizedBox(height: 16),

                      // Live stock: follows the store's shelf in real time (FR01)
                      LiveStockIndicator(product: product),

                      const SizedBox(height: 12),

                      // Escrow (FR03)
                      const EscrowTrustBadge(),

                      // Description
                      if (product.description != null && product.description!.isNotEmpty) ...[
                        const SizedBox(height: 20),
                        Text('Description', style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w600)),
                        const SizedBox(height: 8),
                        Text(product.description!,
                            style: GoogleFonts.poppins(fontSize: 13, color: AppColors.textSecondary, height: 1.5)),
                      ],
                    ],
                  ),
                ),

                const SizedBox(height: 8),
                _reviewsSection(context, state),
                const SizedBox(height: 24),
              ],
            ),
          ),

          // Bottom action buttons
          bottomNavigationBar: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 10, offset: const Offset(0, -4))],
            ),
            child: SafeArea(
              child: Row(
                children: [
                  // Add to Cart
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: product.isOutOfStock
                          ? null
                          : () {
                              if (!_addToCart(context, product)) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('${product.name} added to cart'),
                                  backgroundColor: AppColors.success,
                                  behavior: SnackBarBehavior.floating,
                                  duration: const Duration(seconds: 1),
                                ),
                              );
                            },
                      icon: const Icon(Icons.shopping_cart_outlined),
                      label: const Text('Add to Cart', maxLines: 1),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.secondary,
                        side: const BorderSide(color: AppColors.secondary, width: 1.5),
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Buy Now
                  Expanded(
                    child: ElevatedButton(
                      onPressed: product.isOutOfStock
                          ? null
                          : () {
                              final inCart = context.read<CartBloc>().state.quantityOf(product.id);
                              if (inCart == 0) _addToCart(context, product);
                              openStoreCart(context, product.vendorId);
                            },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: Text(product.isOutOfStock ? 'Sold out' : 'Buy Now'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  /// Rating summary, the latest reviews and the link to all of them
  Widget _reviewsSection(BuildContext context, ProductDetailState state) {
    final product = state.product;
    final details = state.details;
    final count = details?.totalRatings ?? product.ratingCount;
    return Container(
      width: double.infinity,
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Ratings & reviews', style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w600)),
          const SizedBox(height: 12),
          if (details == null && state.loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Center(child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))),
            )
          else if (details == null && state.error != null)
            Row(
              children: [
                Expanded(
                  child: Text("Couldn't load reviews. ${state.error}",
                      style: GoogleFonts.poppins(fontSize: 12, color: AppColors.textSecondary)),
                ),
                TextButton(
                  onPressed: () => context.read<ProductDetailBloc>().add(const LoadProductDetail()),
                  child: const Text('Retry'),
                ),
              ],
            )
          else ...[
            RatingSummary(
              average: product.averageRating,
              count: count,
              distribution: details?.distribution ?? const {},
            ),
            if (details != null && details.latestReviews.isNotEmpty) ...[
              const Divider(height: 24),
              for (var i = 0; i < details.latestReviews.length; i++) ...[
                if (i > 0) const Divider(height: 1),
                ReviewTile(review: details.latestReviews[i]),
              ],
            ],
            if (count > 0)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => ProductReviewsScreen(product: product, details: details)),
                  ),
                  child: Text('See all reviews ($count) ›'),
                ),
              )
            else
              const SizedBox(height: 8),
          ],
        ],
      ),
    );
  }
}
