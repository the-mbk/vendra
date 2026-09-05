// ══════════════════════════════════════════════════════════════
// Vendra App - Store Screen
// Shows vendor shop details with REAL MAP, and all products
// Customer lands here when clicking a product on the homepage
// ══════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:latlong2/latlong.dart';
import '../../../config/app_theme.dart';
import '../../../config/app_routes.dart';
import '../../../core/models/product_model.dart';
import '../../../core/services/api_service.dart';
import '../../../core/services/customer_location_storage.dart';
import '../../../config/api_config.dart';
import '../../../core/widgets/product_card.dart';
import '../../../core/widgets/map_picker_widget.dart';
import '../bloc/cart_bloc.dart';
import 'dart:math';

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

  @override
  void initState() {
    super.initState();
    _loadVendorDetails();
    _loadCustomerLocation();
  }

  Future<void> _loadCustomerLocation() async {
    final loc = await CustomerLocationStorage.load();
    if (!mounted) return;
    setState(() {
      _customerLat = loc.lat;
      _customerLng = loc.lng;
    });
  }

  Future<void> _loadVendorDetails() async {
    setState(() { _loading = true; _error = null; });
    try {
      final response = await ApiService().get(ApiConfig.vendorDetails(widget.vendorId));
      if (response.data['success'] == true) {
        final data = response.data['data'];
        _vendorData = data;
        _products = (data['products'] as List)
            .map((json) => ProductModel.fromJson(json))
            .toList();
      } else {
        _error = response.data['message'] ?? 'Failed to load store';
      }
    } catch (e) {
      _error = ApiService.getErrorMessage(e);
    }
    if (mounted) setState(() { _loading = false; });
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
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => _ProductQuickSheet(product: match),
    );
  }

  double? _calculateDistance() {
    if (_vendorData == null) return null;
    final lat = _vendorData!['latitude'];
    final lng = _vendorData!['longitude'];
    if (lat == null || lng == null) return null;
    return _haversine(_customerLat, _customerLng, (lat as num).toDouble(), (lng as num).toDouble());
  }

  double _haversine(double lat1, double lon1, double lat2, double lon2) {
    const r = 6371.0;
    final dLat = (lat2 - lat1) * pi / 180;
    final dLon = (lon2 - lon1) * pi / 180;
    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(lat1 * pi / 180) * cos(lat2 * pi / 180) *
        sin(dLon / 2) * sin(dLon / 2);
    final c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return r * c;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
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
                    ElevatedButton(onPressed: _loadVendorDetails, child: const Text('Retry')),
                  ],
                ))
              : CustomScrollView(
                  slivers: [
                    // Store header
                    SliverAppBar(
                      expandedHeight: 200,
                      pinned: true,
                      backgroundColor: AppColors.secondary,
                      flexibleSpace: FlexibleSpaceBar(
                        title: Text(
                          _vendorData?['storeName'] ?? widget.storeName,
                          style: GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 16),
                        ),
                        background: Container(
                          decoration: const BoxDecoration(
                            gradient: LinearGradient(
                              colors: [Color(0xFF0D2137), Color(0xFF1565C0)],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                          ),
                          child: Stack(
                            children: [
                              Positioned(right: -30, top: -30, child: Container(width: 160, height: 160, decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white.withOpacity(0.05)))),
                              Center(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    const SizedBox(height: 30),
                                    Container(
                                      width: 72, height: 72,
                                      decoration: BoxDecoration(color: Colors.white.withOpacity(0.15), shape: BoxShape.circle, border: Border.all(color: Colors.white24, width: 2)),
                                      child: const Icon(Icons.storefront, size: 36, color: Colors.white),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
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
                            if (_vendorData?['ownerName'] != null)
                              Row(
                                children: [
                                  const Icon(Icons.person_outline, size: 16, color: AppColors.textSecondary),
                                  const SizedBox(width: 6),
                                  Text(_vendorData!['ownerName'], style: GoogleFonts.poppins(fontSize: 13, color: AppColors.textSecondary)),
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
                                    dist < 1 ? '${(dist * 1000).toStringAsFixed(0)} m away' : '${dist.toStringAsFixed(1)} km away',
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
                                  Text('Vendra Verified • Escrow Protected', style: GoogleFonts.poppins(fontSize: 11, fontWeight: FontWeight.w600, color: const Color(0xFF2E7D32))),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

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
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
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

                    // Products section title
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 20, 16, 12),
                        child: Text('Products (${_products.length})', style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w600)),
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
                                    onTap: () => Navigator.pushNamed(context, AppRoutes.productDetail, arguments: product),
                                    onAddToCart: () {
                                      context.read<CartBloc>().add(AddToCart(product: product));
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(
                                          content: Text('${product.name} added to cart'),
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
                Expanded(child: Text(product.name, style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.w600))),
                IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close)),
              ],
            ),
            Text('Rs. ${product.price.toStringAsFixed(0)}',
                style: GoogleFonts.poppins(fontSize: 20, fontWeight: FontWeight.w700, color: AppColors.primary)),
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
                      Navigator.pushNamed(context, AppRoutes.productDetail, arguments: product);
                    },
                    icon: const Icon(Icons.info_outline, size: 20),
                    label: const Text('View details'),
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
                    icon: const Icon(Icons.add_shopping_cart, size: 20),
                    label: const Text('Add to cart'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: AppColors.secondary, foregroundColor: Colors.white),
                onPressed: () {
                  context.read<CartBloc>().add(AddToCart(product: product));
                  Navigator.pop(context);
                  Navigator.pushNamed(context, AppRoutes.cart);
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
