// ══════════════════════════════════════════════════════════════
// Vendra App - Product Detail Screen
// Replicates the Stitch product detail design.
// - Photo gallery (cover first) with page dots; tap for full-screen
//   pinch-zoom (FR06)
// - Live public stock via realtime stock:update events, with the dual
//   inventory explainer (FR01)
// - Escrow trust badge (FR03)
// - The store selling it: logo, name, address/distance and "Visit store"
//   (pops back instead when the page was opened from that store's page)
// - Rating summary, latest reviews and "See all reviews" (SRDS §2.3), plus
//   "Write a review" when the customer has a delivered order with this
//   product still to review (opens the order review sheet)
// Details come from GET /api/products/:id (ProductDetailBloc).
// ══════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:vendra_customer/vendra_core.dart';
import '../../../core/services/customer_location_storage.dart';
import '../bloc/cart_bloc.dart';
import '../bloc/product_detail_bloc.dart';
import '../services/catalog_api.dart';
import '../widgets/order_review.dart';
import '../widgets/product_gallery.dart';
import '../widgets/rating_summary.dart';
import '../widgets/store_widgets.dart';
import '../widgets/trust_badges.dart';
import 'cart_screen.dart';
import 'product_reviews_screen.dart';
import 'store_screen.dart';

class ProductDetailScreen extends StatelessWidget {
  final ProductModel product;

  /// Opened from this product's own store page: "Visit store" goes back to it
  /// instead of opening the store a second time
  final bool openedFromStore;

  const ProductDetailScreen({super.key, required this.product, this.openedFromStore = false});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => ProductDetailBloc(product: product)..add(const LoadProductDetail()),
      child: _ProductDetailView(openedFromStore: openedFromStore),
    );
  }
}

class _ProductDetailView extends StatelessWidget {
  final bool openedFromStore;
  const _ProductDetailView({required this.openedFromStore});

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
                  color: AppColors.surface,
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
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
                // The store selling it
                _ProductStoreCard(product: product, openedFromStore: openedFromStore),

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
              color: AppColors.surface,
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
                        side: BorderSide(color: AppColors.secondary, width: 1.5),
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
      color: AppColors.surface,
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
              emptyText: state.reviewOrderId != null
                  ? 'No reviews yet. You bought this, so yours can be the first.'
                  : 'No reviews yet. Customers who buy this can rate it once it\'s delivered.',
            ),
            if (state.reviewOrderId != null) ...[
              const SizedBox(height: 12),
              _WriteReviewButton(
                orderId: state.reviewOrderId!,
                onReviewed: () => context.read<ProductDetailBloc>().add(const LoadProductDetail()),
              ),
            ],
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

/// "Sold by": the store's logo, name, where it is and a way into it
class _ProductStoreCard extends StatefulWidget {
  final ProductModel product;
  final bool openedFromStore;
  const _ProductStoreCard({required this.product, required this.openedFromStore});

  @override
  State<_ProductStoreCard> createState() => _ProductStoreCardState();
}

class _ProductStoreCardState extends State<_ProductStoreCard> {
  /// km from the customer's delivery location (null until known)
  double? _distanceKm;

  @override
  void initState() {
    super.initState();
    _loadDistance();
  }

  Future<void> _loadDistance() async {
    final p = widget.product;
    if (p.vendorLat == null || p.vendorLng == null) return;
    try {
      final loc = await CustomerLocationStorage.load();
      if (!mounted) return;
      setState(() => _distanceKm = haversineKm(loc.lat, loc.lng, p.vendorLat!, p.vendorLng!));
    } catch (_) {
      // The distance is only a nice-to-have
    }
  }

  void _visitStore() {
    if (widget.openedFromStore && Navigator.canPop(context)) {
      Navigator.pop(context);
      return;
    }
    final p = widget.product;
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => StoreScreen(vendorId: p.vendorId, storeName: p.storeName ?? 'Store')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.product;
    final name = p.storeName ?? 'Store';
    final address = (p.storeAddress ?? '').trim();
    final where = [
      if (_distanceKm != null) '${distanceLabel(_distanceKm!)} away',
      if (address.isNotEmpty) address,
    ].join(' · ');
    return Material(
      color: AppColors.surface,
      child: InkWell(
        onTap: _visitStore,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 16, 14),
          child: Row(
            children: [
              StoreLogo(storeName: name, logoUrl: p.storeLogoUrl, size: 48),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Sold by', style: GoogleFonts.poppins(fontSize: 11, color: AppColors.textSecondary)),
                    Text(name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                    if (where.isNotEmpty)
                      Row(
                        children: [
                          Icon(Icons.location_on_outlined, size: 13, color: AppColors.textSecondary),
                          const SizedBox(width: 2),
                          Expanded(
                            child: Text(where,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: GoogleFonts.poppins(fontSize: 12, color: AppColors.textSecondary)),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton(
                onPressed: _visitStore,
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.secondary,
                  side: BorderSide(color: AppColors.secondary),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  minimumSize: const Size(0, 36),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  textStyle: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w600),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                child: const Text('Visit store', maxLines: 1),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Loads the order the customer can review this product with, then opens
/// the order review sheet; [onReviewed] runs once something was saved
class _WriteReviewButton extends StatefulWidget {
  final int orderId;
  final VoidCallback onReviewed;
  const _WriteReviewButton({required this.orderId, required this.onReviewed});

  @override
  State<_WriteReviewButton> createState() => _WriteReviewButtonState();
}

class _WriteReviewButtonState extends State<_WriteReviewButton> {
  bool _opening = false;

  Future<void> _open() async {
    setState(() => _opening = true);
    final OrderModel order;
    try {
      order = await CatalogApi.instance.order(widget.orderId);
    } catch (e) {
      if (!mounted) return;
      setState(() => _opening = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text("Couldn't open your order. ${ApiService.getErrorMessage(e)}"),
        behavior: SnackBarBehavior.floating,
      ));
      return;
    }
    if (!mounted) return;
    setState(() => _opening = false);
    if (await showOrderReviewSheet(context, order)) widget.onReviewed();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: _opening ? null : _open,
        icon: _opening
            ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
            : const Icon(Icons.rate_review_outlined, size: 18),
        label: const Text('Write a review'),
        style: ElevatedButton.styleFrom(
          backgroundColor: starColor,
          foregroundColor: AppColors.textPrimary,
          padding: const EdgeInsets.symmetric(vertical: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
    );
  }
}
