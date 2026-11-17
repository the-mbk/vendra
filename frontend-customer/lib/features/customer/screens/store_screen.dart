// ══════════════════════════════════════════════════════════════
// Vendra App - Store Screen
// The store's cover photo and logo (initials / gradient when it has none),
// its details, products, reviews and location on a real map.
// Product stock is live (stock:update); sold-out items drop off and
// catalog:update reloads the store's products (FR01/PR01).
// Shows the store's rating (averageRating / ratingCount), each product's
// RatingBadge and a "Store reviews" section: the 5 → 1 breakdown, the
// latest reviews (with the product each is about) and "See all reviews"
// (SRDS §2.3). Products open their page with openedFromStore, so its
// "Visit store" comes back here instead of stacking another store page.
// ══════════════════════════════════════════════════════════════

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:latlong2/latlong.dart';
import 'package:vendra_customer/vendra_core.dart';
import '../../../core/services/customer_location_storage.dart';
import '../bloc/cart_bloc.dart';
import '../bloc/product_detail_bloc.dart' show ratingDistributionFrom;
import '../services/catalog_api.dart';
import '../widgets/rating_summary.dart';
import '../widgets/store_widgets.dart';
import '../widgets/trust_badges.dart';
import 'cart_screen.dart';
import 'product_detail_screen.dart';
import 'store_reviews_screen.dart';

class StoreScreen extends StatefulWidget {
  final int vendorId;
  final String storeName;
  final ProductModel? highlightProduct;

  const StoreScreen({
    super.key,
    required this.vendorId,
    required this.storeName,
    this.highlightProduct,
  });

  @override
  State<StoreScreen> createState() => _StoreScreenState();
}

class _StoreScreenState extends State<StoreScreen> {
  bool _loading = true;
  String? _error;
  Map<String, dynamic>? _vendorData;
  List<ProductModel> _products = [];
  double _customerLat = CustomerLocationStorage.defaultLat;
  double _customerLng = CustomerLocationStorage.defaultLng;

  List<ReviewModel> _latestReviews = const [];

  StreamSubscription<StockUpdateEvent>? _stockSub;
  StreamSubscription<void>? _catalogSub;
  final Set<int> _soldOut = {};

  @override
  void initState() {
    super.initState();
    _loadVendorDetails();
    _loadCustomerLocation();

    _stockSub = RealtimeService().stockUpdates.where((e) => e.vendorId == widget.vendorId).listen(_onStock);
    _catalogSub = RealtimeService().catalogUpdates.listen((_) => _loadVendorDetails(silent: true));
  }

  @override
  void dispose() {
    _stockSub?.cancel();
    _catalogSub?.cancel();
    super.dispose();
  }

  void _onStock(StockUpdateEvent e) {
    if (!mounted || _loading) return;
    final index = _products.indexWhere((p) => p.id == e.productId);
    if (index < 0) {
      // A product that sold out earlier is back — reload to get its details
      if (e.publicStock > 0 && _soldOut.remove(e.productId)) _loadVendorDetails(silent: true);
      return;
    }
    setState(() {
      if (e.publicStock <= 0) {
        _products.removeAt(index);
        _soldOut.add(e.productId);
      } else {
        _products[index] = _products[index].withStock(publicStock: e.publicStock);
      }
    });
  }

  Future<void> _loadCustomerLocation() async {
    final loc = await CustomerLocationStorage.load();
    if (!mounted) return;
    setState(() {
      _customerLat = loc.lat;
      _customerLng = loc.lng;
    });
  }

  Future<void> _loadVendorDetails({bool silent = false}) async {
    if (!silent) setState(() { _loading = true; _error = null; });
    try {
      final data = await CatalogApi.instance.store(widget.vendorId);
      _vendorData = data;
      _products = (data['products'] as List<dynamic>? ?? const [])
          .whereType<Map>()
          .map((json) => ProductModel.fromJson(Map<String, dynamic>.from(json)))
          .where((p) => p.publicStock > 0)
          .toList();
      _latestReviews = (data['latestReviews'] as List<dynamic>? ?? const [])
          .whereType<Map>()
          .map((r) => ReviewModel.fromJson(Map<String, dynamic>.from(r)))
          .toList();
      _soldOut.clear();
    } catch (e) {
      if (!silent) _error = ApiService.getErrorMessage(e);
    }
    if (mounted) setState(() { _loading = false; });
    if (silent) return;
    if (mounted && widget.highlightProduct != null && _error == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _maybeOpenHighlightSheet());
    }
  }

  void _maybeOpenHighlightSheet() {
    final highlight = widget.highlightProduct;
    if (highlight == null || !mounted) return;
    final matches = _products.where((p) => p.id == highlight.id);
    if (matches.isEmpty) return;
    final match = matches.first;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => _ProductQuickSheet(product: match),
    );
  }

  /// The store's average rating across its products' reviews
  Widget _storeRating() {
    final average = toDoubleOrNull(_vendorData?['averageRating']);
    final count = toInt(_vendorData?['ratingCount']);
    if (average == null || count == 0) {
      return Row(
        children: [
          const Icon(Icons.star_outline_rounded, size: 18, color: starColor),
          const SizedBox(width: 6),
          Text('No ratings yet', style: GoogleFonts.poppins(fontSize: 13, color: AppColors.textSecondary)),
        ],
      );
    }
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 8,
      runSpacing: 2,
      children: [
        RatingStars(rating: average, size: 18),
        Text(average.toStringAsFixed(1),
            style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
        Text('· ${ratingCountLabel(count)}', style: GoogleFonts.poppins(fontSize: 13, color: AppColors.textSecondary)),
      ],
    );
  }

  double? _calculateDistance() {
    final lat = toDoubleOrNull(_vendorData?['latitude']);
    final lng = toDoubleOrNull(_vendorData?['longitude']);
    if (lat == null || lng == null) return null;
    return haversineKm(_customerLat, _customerLng, lat, lng);
  }

  String get _storeName => _vendorData?['storeName']?.toString() ?? widget.storeName;
  String? get _logoUrl => _vendorData?['logoUrl']?.toString();

  /// A product's own page; its "Visit store" comes back here
  void _openProduct(ProductModel product) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => ProductDetailScreen(product: product, openedFromStore: true)),
    );
  }

  void _openAllReviews() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => StoreReviewsScreen(
          vendorId: widget.vendorId,
          storeName: _storeName,
          logoUrl: _logoUrl,
          averageRating: toDoubleOrNull(_vendorData?['averageRating']),
          ratingCount: toInt(_vendorData?['ratingCount']),
          distribution: ratingDistributionFrom(_vendorData?['ratingDistribution']),
        ),
      ),
    );
  }

  /// "Store reviews": breakdown, the latest few (with their product) and a link to all of them
  Widget _reviewsSection() {
    final average = toDoubleOrNull(_vendorData?['averageRating']);
    final count = toInt(_vendorData?['ratingCount']);
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 20, 16, 0),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Store reviews', style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w600)),
          const SizedBox(height: 12),
          RatingSummary(
            average: average,
            count: count,
            distribution: ratingDistributionFrom(_vendorData?['ratingDistribution']),
            emptyText: "No reviews yet. Customers can rate what they buy here once it's delivered.",
          ),
          if (_latestReviews.isNotEmpty) ...[
            const Divider(height: 24),
            for (var i = 0; i < _latestReviews.length; i++) ...[
              if (i > 0) const Divider(height: 1),
              ReviewTile(
                review: _latestReviews[i],
                showProduct: true,
                onProductTap: _productTapFor(_latestReviews[i]),
              ),
            ],
          ],
          if (count > 0)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: _openAllReviews,
                child: Text('See all reviews ($count) ›'),
              ),
            )
          else
            const SizedBox(height: 10),
        ],
      ),
    );
  }

  /// Opens the reviewed product when it's still on sale here
  VoidCallback? _productTapFor(ReviewModel review) {
    final matches = _products.where((p) => p.id == review.productId);
    if (matches.isEmpty) return null;
    return () => _openProduct(matches.first);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      // This store's own cart (every store has a separate cart)
      bottomNavigationBar: BlocBuilder<CartBloc, CartState>(
        builder: (context, cart) {
          final mine = cart.forStore(widget.vendorId);
          if (mine.isEmpty) return const SizedBox.shrink();
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: ElevatedButton.icon(
                onPressed: () => openStoreCart(context, widget.vendorId),
                icon: const Icon(Icons.shopping_cart_checkout),
                label: Text('View cart · ${mine.totalItems} item${mine.totalItems == 1 ? '' : 's'} · ${formatRupees(mine.totalAmount)}'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
          );
        },
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
          : _error != null
              ? Center(child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.error_outline, size: 48, color: Colors.grey.shade400),
                    const SizedBox(height: 16),
                    Text(_error!, textAlign: TextAlign.center),
                    const SizedBox(height: 16),
                    ElevatedButton(onPressed: () => _loadVendorDetails(), child: const Text('Retry')),
                  ],
                ))
              : CustomScrollView(
                  slivers: [
                    // Store header
                    SliverAppBar(
                      expandedHeight: 200,
                      pinned: true,
                      backgroundColor: AppColors.secondary,
                      foregroundColor: Colors.white,
                      iconTheme: const IconThemeData(color: Colors.white),
                      surfaceTintColor: Colors.transparent,
                      flexibleSpace: FlexibleSpaceBar(
                        centerTitle: true,
                        titlePadding: const EdgeInsets.fromLTRB(56, 0, 56, 14),
                        title: Text(
                          _storeName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: GoogleFonts.poppins(
                            fontWeight: FontWeight.w600,
                            fontSize: 16,
                            color: Colors.white,
                            shadows: const [Shadow(color: Colors.black45, blurRadius: 6)],
                          ),
                        ),
                        // The store's cover photo (brand gradient without one) and its logo
                        background: Stack(
                          fit: StackFit.expand,
                          children: [
                            StoreCover(coverUrl: _vendorData?['coverUrl']?.toString(), shade: true),
                            Align(
                              alignment: Alignment.center,
                              child: StoreLogo(storeName: _storeName, logoUrl: _logoUrl, size: 72, ring: true),
                            ),
                          ],
                        ),
                      ),
                    ),

                    // Store info
                    SliverToBoxAdapter(
                      child: Container(
                        color: Colors.white,
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            InkWell(
                              onTap: toInt(_vendorData?['ratingCount']) > 0 ? _openAllReviews : null,
                              borderRadius: BorderRadius.circular(8),
                              child: _storeRating(),
                            ),
                            const SizedBox(height: 10),
                            if (_vendorData?['ownerName'] != null)
                              Row(
                                children: [
                                  const Icon(Icons.person_outline, size: 16, color: AppColors.textSecondary),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(_vendorData!['ownerName'], style: GoogleFonts.poppins(fontSize: 13, color: AppColors.textSecondary)),
                                  ),
                                  // Tap-to-call the store (copies the number where calling isn't possible)
                                  PhoneAction(phone: _vendorData?['ownerPhone']?.toString(), label: 'Call store'),
                                ],
                              ),
                            const SizedBox(height: 8),
                            if (_vendorData?['storeAddress'] != null)
                              Row(
                                children: [
                                  const Icon(Icons.location_on_outlined, size: 16, color: AppColors.secondary),
                                  const SizedBox(width: 6),
                                  Expanded(child: Text(_vendorData!['storeAddress'], style: GoogleFonts.poppins(fontSize: 13, color: AppColors.textPrimary))),
                                ],
                              ),
                            const SizedBox(height: 8),
                            // Distance info
                            Builder(builder: (context) {
                              final dist = _calculateDistance();
                              if (dist == null) return const SizedBox();
                              return Row(
                                children: [
                                  const Icon(Icons.directions_walk, size: 16, color: AppColors.primary),
                                  const SizedBox(width: 6),
                                  Text(
                                    '${distanceLabel(dist)} away',
                                    style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.primary),
                                  ),
                                  const SizedBox(width: 12),
                                  Text('~${(dist * 3).ceil()} min delivery', style: GoogleFonts.poppins(fontSize: 12, color: AppColors.textSecondary)),
                                ],
                              );
                            }),
                            const SizedBox(height: 12),
                            // Trust badge
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              decoration: BoxDecoration(color: const Color(0xFFE8F5E9), borderRadius: BorderRadius.circular(8)),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.verified_user, size: 16, color: Color(0xFF2E7D32)),
                                  const SizedBox(width: 6),
                                  Flexible(
                                    child: Text('Vendra Verified • Escrow Protected',
                                        style: GoogleFonts.poppins(fontSize: 11, fontWeight: FontWeight.w600, color: const Color(0xFF2E7D32))),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    // Products section title
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 20, 16, 12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Products (${_products.length})', style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w600)),
                            // Dual inventory reassurance (FR01)
                            if (_products.isNotEmpty) const LiveStockNote(),
                          ],
                        ),
                      ),
                    ),

                    // Products grid
                    _products.isEmpty
                        ? SliverToBoxAdapter(
                            child: Center(
                              child: Padding(
                                padding: const EdgeInsets.all(32),
                                child: Column(
                                  children: [
                                    Icon(Icons.inventory_2_outlined, size: 64, color: Colors.grey.shade300),
                                    const SizedBox(height: 16),
                                    Text('No products available', style: GoogleFonts.poppins(color: AppColors.textSecondary)),
                                  ],
                                ),
                              ),
                            ),
                          )
                        : SliverPadding(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            sliver: SliverGrid(
                              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 2,
                                childAspectRatio: 0.72,
                                crossAxisSpacing: 12,
                                mainAxisSpacing: 12,
                              ),
                              delegate: SliverChildBuilderDelegate(
                                (context, index) {
                                  final product = _products[index];
                                  return ProductCard(
                                    product: product,
                                    onTap: () => _openProduct(product),
                                    onAddToCart: () {
                                      final inCart = context.read<CartBloc>().state.quantityOf(product.id);
                                      final full = inCart >= product.publicStock;
                                      if (!full) context.read<CartBloc>().add(AddToCart(product: product));
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(
                                          content: Text(full
                                              ? 'Your cart already has all ${product.publicStock} available'
                                              : '${product.name} added to cart'),
                                          backgroundColor: AppColors.success,
                                          behavior: SnackBarBehavior.floating,
                                          duration: const Duration(seconds: 1),
                                        ),
                                      );
                                    },
                                  );
                                },
                                childCount: _products.length,
                              ),
                            ),
                          ),

                    // Reviews of the store's products
                    SliverToBoxAdapter(child: _reviewsSection()),

                    // ── MAP showing vendor location ──
                    SliverToBoxAdapter(
                      child: Builder(builder: (context) {
                        final lat = _vendorData?['latitude'];
                        final lng = _vendorData?['longitude'];
                        if (lat == null || lng == null) {
                          return Padding(
                            padding: const EdgeInsets.all(16),
                            child: Container(
                              height: 150,
                              decoration: BoxDecoration(
                                color: Colors.grey.shade100,
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: Center(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.map_outlined, size: 40, color: Colors.grey.shade400),
                                    const SizedBox(height: 8),
                                    Text('Location not set by vendor', style: GoogleFonts.poppins(fontSize: 12, color: AppColors.textSecondary)),
                                  ],
                                ),
                              ),
                            ),
                          );
                        }

                        final vendorLatLng = LatLng((lat as num).toDouble(), (lng as num).toDouble());
                        return Padding(
                          padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Store Location', style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w600)),
                              const SizedBox(height: 8),
                              MapPickerWidget(
                                initialCenter: vendorLatLng,
                                initialZoom: 15.0,
                                interactive: false,
                                height: 200,
                                markers: [
                                  MapMarkerData(
                                    position: vendorLatLng,
                                    label: _vendorData?['storeName'] ?? 'Store',
                                    icon: Icons.storefront,
                                    color: AppColors.primary,
                                  ),
                                ],
                              ),
                            ],
                          ),
                        );
                      }),
                    ),

                    const SliverToBoxAdapter(child: SizedBox(height: 24)),
                  ],
                ),
    );
  }
}

class _ProductQuickSheet extends StatelessWidget {
  final ProductModel product;
  const _ProductQuickSheet({required this.product});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Row(
              children: [
                Expanded(child: Text(product.name, style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.w600, color: AppColors.textPrimary))),
                IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close)),
              ],
            ),
            Text(formatRupees(product.price),
                style: GoogleFonts.poppins(fontSize: 20, fontWeight: FontWeight.w700, color: AppColors.primary)),
            const SizedBox(height: 4),
            Wrap(
              spacing: 12,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (product.ratingCount > 0) RatingBadge(average: product.averageRating, count: product.ratingCount),
                LiveStockIndicator(product: product, compact: true),
              ],
            ),
            if (product.description != null && product.description!.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                product.description!,
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.poppins(fontSize: 13, color: AppColors.textSecondary),
              ),
            ],
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {
                      Navigator.pop(context);
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => ProductDetailScreen(product: product, openedFromStore: true)),
                      );
                    },
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 14),
                      textStyle: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w600),
                    ),
                    icon: const Icon(Icons.info_outline, size: 18),
                    label: const Text('View details', maxLines: 1),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () {
                      context.read<CartBloc>().add(AddToCart(product: product));
                      Navigator.pop(context);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('${product.name} added to cart'), backgroundColor: AppColors.success, behavior: SnackBarBehavior.floating),
                      );
                    },
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 14),
                      textStyle: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w600),
                    ),
                    icon: const Icon(Icons.add_shopping_cart, size: 18),
                    label: const Text('Add to cart', maxLines: 1),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.secondary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                onPressed: () {
                  context.read<CartBloc>().add(AddToCart(product: product));
                  Navigator.pop(context);
                  openStoreCart(context, product.vendorId);
                },
                child: const Text('Go to checkout'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
