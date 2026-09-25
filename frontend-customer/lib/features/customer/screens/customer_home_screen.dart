// ══════════════════════════════════════════════════════════════
// Vendra App - Customer Home Screen
// Products show store info, location & distance.
// Tapping a product card → opens the Store page.
// Categories come from GET /api/categories and filter the product list
// together with search (FR06). Stock on the list is live (FR01).
// The product list is paged: the next page loads as the customer
// scrolls near the bottom (a new search/category starts from page 1).
// ══════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:latlong2/latlong.dart';
import 'dart:math';
import 'package:vendra_customer/vendra_core.dart';
import '../../../config/app_routes.dart';
import '../bloc/customer_product_bloc.dart';
import '../bloc/cart_bloc.dart';
import '../bloc/category_bloc.dart';
import '../../auth/bloc/auth_bloc.dart';
import '../../auth/bloc/auth_event.dart';
import '../../auth/bloc/auth_state.dart';

import 'store_screen.dart';
import 'customer_orders_panel.dart';
import '../../../core/services/customer_location_storage.dart';


class CustomerHomeScreen extends StatefulWidget {
  const CustomerHomeScreen({super.key});

  @override
  State<CustomerHomeScreen> createState() => _CustomerHomeScreenState();
}

class _CustomerHomeScreenState extends State<CustomerHomeScreen> {
  final _searchController = TextEditingController();
  final _homeScroll = ScrollController();
  int _currentNavIndex = 0;

  String _locationName = CustomerLocationStorage.defaultName;
  double _customerLat = CustomerLocationStorage.defaultLat;
  double _customerLng = CustomerLocationStorage.defaultLng;

  /// Active filters (FR06)
  int? _categoryId;
  String _search = '';

  @override
  void initState() {
    super.initState();
    _homeScroll.addListener(_maybeLoadMoreProducts);
    context.read<CategoryBloc>().add(const FetchCategories());
    _fetchProducts();
    _loadSavedLocation();
  }

  void _fetchProducts() {
    context.read<CustomerProductBloc>().add(FetchProducts(
          search: _search.isNotEmpty ? _search : null,
          categoryId: _categoryId,
        ));
  }

  /// Asks for the next page of products when the bottom is close (or already
  /// on screen). The bloc ignores it while a page is loading or none are left.
  void _maybeLoadMoreProducts() {
    if (!_homeScroll.hasClients) return;
    final state = context.read<CustomerProductBloc>().state;
    if (state is! CustomerProductLoaded || !state.hasMore || state.loadingMore) return;
    if (_homeScroll.position.extentAfter < 600) {
      context.read<CustomerProductBloc>().add(const LoadMoreProducts());
    }
  }

  void _selectCategory(int? id) {
    setState(() => _categoryId = _categoryId == id ? null : id);
    _fetchProducts();
  }

  void _clearFilters() {
    _searchController.clear();
    setState(() {
      _search = '';
      _categoryId = null;
    });
    _fetchProducts();
  }

  void _openOrderFromNotification(BuildContext ctx, int orderId) {
    Navigator.pushNamed(ctx, AppRoutes.orderTracking, arguments: orderId);
  }

  Future<void> _loadSavedLocation() async {
    final loc = await CustomerLocationStorage.load();
    if (!mounted) return;
    setState(() {
      _customerLat = loc.lat;
      _customerLng = loc.lng;
      _locationName = loc.name;
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _homeScroll.dispose();
    super.dispose();
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

  String _distanceText(ProductModel product) {
    if (product.vendorLat == null || product.vendorLng == null) return '';
    final dist = _haversine(_customerLat, _customerLng, product.vendorLat!, product.vendorLng!);
    if (dist < 1) return '${(dist * 1000).toStringAsFixed(0)} m';
    return '${dist.toStringAsFixed(1)} km';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      drawer: _buildCustomerDrawer(context),
      appBar: _buildAppBar(),
      body: IndexedStack(
        index: _currentNavIndex,
        children: [
          _buildHomeBody(),
          _buildExploreTab(),
          _buildOrdersTab(),
          _buildPlaceholderTab('Saved'),
          _buildProfileTab(),
        ],
      ),
      bottomNavigationBar: _buildBottomNav(),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: Colors.white,
      elevation: 0,
      leading: Builder(
        builder: (ctx) => IconButton(
          icon: const Icon(Icons.menu, color: AppColors.textPrimary),
          onPressed: () => Scaffold.of(ctx).openDrawer(),
        ),
      ),
      title: Text(
        'Vendra',
        style: GoogleFonts.poppins(
          fontSize: 22,
          fontWeight: FontWeight.w700,
          color: AppColors.secondary,
        ),
      ),
      centerTitle: false,
      actions: [
        BlocBuilder<AuthBloc, AuthState>(
          builder: (context, authState) {
            if (authState is Authenticated) {
              return GestureDetector(
                onTap: () => Navigator.pushNamed(context, AppRoutes.wallet),
                child: Container(
                margin: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: Colors.green.shade50,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.green.shade200),
                ),
                child: Row(
                  children: [
                    Icon(Icons.account_balance_wallet, size: 16, color: Colors.green.shade700),
                    const SizedBox(width: 6),
                    Text(
                      'Rs. ${authState.user.walletBalance.toStringAsFixed(0)}',
                      style: GoogleFonts.poppins(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Colors.green.shade800,
                      ),
                    ),
                  ],
                ),
                ),
              );
            }
            return const SizedBox.shrink();
          },
        ),
        // FR09: live inbox; order notifications open the tracking screen
        NotificationBell(onOpenOrder: _openOrderFromNotification),
        // Cart icon with badge
        BlocBuilder<CartBloc, CartState>(
          builder: (context, cartState) {
            return Stack(
              children: [
                IconButton(
                  icon: const Icon(Icons.shopping_cart_outlined),
                  onPressed: () => Navigator.pushNamed(context, AppRoutes.cart),
                ),
                if (cartState.totalItems > 0)
                  Positioned(
                    right: 6,
                    top: 6,
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: const BoxDecoration(
                        color: AppColors.primary,
                        shape: BoxShape.circle,
                      ),
                      constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
                      child: Text(
                        '${cartState.totalItems}',
                        style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
        const SizedBox(width: 8),
      ],
    );
  }

  Widget _buildHomeBody() {
    return RefreshIndicator(
      color: AppColors.primary,
      onRefresh: () async {
        context.read<CategoryBloc>().add(const FetchCategories());
        _fetchProducts();
      },
      child: SingleChildScrollView(
        controller: _homeScroll,
        physics: const AlwaysScrollableScrollPhysics(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Location Selector ──
            GestureDetector(
              onTap: _showLocationPicker,
              child: Container(
                color: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                child: Row(
                  children: [
                    const Icon(Icons.location_on, size: 20, color: AppColors.primary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Delivering to', style: GoogleFonts.poppins(fontSize: 11, color: AppColors.textSecondary)),
                          Text(
                            _locationName,
                            style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w600),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppColors.secondary.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.map_outlined, size: 14, color: AppColors.secondary),
                          const SizedBox(width: 4),
                          Text('Change', style: GoogleFonts.poppins(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.secondary)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Search bar
            Padding(
              padding: const EdgeInsets.all(16),
              child: TextField(
                controller: _searchController,
                textInputAction: TextInputAction.search,
                onChanged: (_) => setState(() {}),
                onSubmitted: (value) {
                  setState(() => _search = value.trim());
                  _fetchProducts();
                },
                decoration: InputDecoration(
                  hintText: 'Search for groceries, clothing...',
                  prefixIcon: const Icon(Icons.search, color: AppColors.textLight),
                  suffixIcon: _searchController.text.isEmpty && _search.isEmpty
                      ? null
                      : IconButton(
                          tooltip: 'Clear search',
                          icon: const Icon(Icons.close, color: AppColors.textLight),
                          onPressed: () {
                            _searchController.clear();
                            setState(() => _search = '');
                            _fetchProducts();
                          },
                        ),
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(color: Colors.grey.shade200),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(color: Colors.grey.shade200),
                  ),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                ),
              ),
            ),

            // Promo banner
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [AppColors.secondary, Color(0xFF1A6DB5)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Free Delivery!',
                              style: GoogleFonts.poppins(fontSize: 20, fontWeight: FontWeight.w700, color: Colors.white)),
                          const SizedBox(height: 4),
                          Text('On your first 3 orders',
                              style: GoogleFonts.poppins(fontSize: 13, color: Colors.white70)),
                          const SizedBox(height: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text('Code: VENDRA1',
                                style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.white)),
                          ),
                        ],
                      ),
                    ),
                    const Icon(Icons.local_shipping_outlined, size: 56, color: Colors.white38),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 20),

            // Categories
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text('Categories', style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w600)),
            ),
            const SizedBox(height: 12),
            BlocBuilder<CategoryBloc, CategoryState>(
              builder: (context, catState) {
                if (catState.categories.isEmpty) {
                  return SizedBox(
                    height: 92,
                    child: Center(
                      child: catState.loading
                          ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
                          : TextButton.icon(
                              onPressed: () => context.read<CategoryBloc>().add(const FetchCategories()),
                              icon: const Icon(Icons.refresh, size: 18),
                              label: const Text('Load categories'),
                            ),
                    ),
                  );
                }
                return SizedBox(
                  height: 92,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    children: [
                      _categoryChip(Icons.apps, 'All', _categoryColors[0],
                          selected: _categoryId == null, onTap: () => _selectCategory(null)),
                      for (var i = 0; i < catState.categories.length; i++)
                        _categoryChip(
                          catState.categories[i].iconData,
                          catState.categories[i].name,
                          _categoryColors[(i + 1) % _categoryColors.length],
                          selected: _categoryId == catState.categories[i].id,
                          onTap: () => _selectCategory(catState.categories[i].id),
                        ),
                    ],
                  ),
                );
              },
            ),

            const SizedBox(height: 20),

            // Products grid title
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Expanded(
                    child: Text(_listTitle(), style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w600)),
                  ),
                  if (_categoryId != null || _search.isNotEmpty)
                    TextButton(onPressed: _clearFilters, child: const Text('Clear filters')),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // Products grid — now with store info on each card
            BlocBuilder<CustomerProductBloc, CustomerProductState>(
              builder: (context, state) {
                if (state is CustomerProductLoading) {
                  return const SizedBox(height: 400, child: LoadingShimmer());
                }

                if (state is CustomerProductError) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Column(
                        children: [
                          Icon(Icons.error_outline, size: 48, color: Colors.grey.shade400),
                          const SizedBox(height: 16),
                          Text(state.message, textAlign: TextAlign.center),
                          const SizedBox(height: 16),
                          ElevatedButton(
                            onPressed: _fetchProducts,
                            child: const Text('Retry'),
                          ),
                        ],
                      ),
                    ),
                  );
                }

                if (state is CustomerProductLoaded) {
                  if (state.products.isEmpty) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(32),
                        child: Column(
                          children: [
                            Icon(Icons.storefront_outlined, size: 64, color: Colors.grey.shade300),
                            const SizedBox(height: 16),
                            Text(
                              _categoryId != null || _search.isNotEmpty
                                  ? 'No products match your filters'
                                  : 'No products available yet',
                              style: GoogleFonts.poppins(color: AppColors.textSecondary),
                            ),
                          ],
                        ),
                      ),
                    );
                  }

                  // A short first page may not fill the screen, so nothing would scroll
                  if (state.hasMore && !state.loadingMore) {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (mounted) _maybeLoadMoreProducts();
                    });
                  }

                  return ListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: state.products.length + (state.hasMore ? 1 : 0),
                    itemBuilder: (context, index) {
                      if (index == state.products.length) {
                        // Next page on its way
                        return const Padding(
                          padding: EdgeInsets.symmetric(vertical: 12),
                          child: Center(
                            child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2)),
                          ),
                        );
                      }
                      final product = state.products[index];
                      final dist = _distanceText(product);
                      return _buildProductTile(product, dist);
                    },
                  );
                }

                return const SizedBox();
              },
            ),

            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  /// Product tile with store info — tapping goes to store page
  Widget _buildProductTile(ProductModel product, String distance) {
    return GestureDetector(
      onTap: () {
        // Navigate to Store Screen
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => StoreScreen(
              vendorId: product.vendorId,
              storeName: product.storeName ?? 'Store',
              highlightProduct: product,
            ),
          ),
        );
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, 2))],
        ),
        child: Row(
          children: [
            // Product photo (placeholder when the vendor hasn't added one)
            SizedBox(
              width: 100,
              height: 110,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: ProductImage(
                      product: product,
                      iconSize: 40,
                      borderRadius: const BorderRadius.horizontal(left: Radius.circular(14)),
                    ),
                  ),
                  // Stock badge
                  if (product.publicStock > 0 && product.publicStock <= 10)
                    Positioned(
                      top: 6,
                      left: 6,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppColors.stockRed.withValues(alpha: 0.9),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text('Low', style: GoogleFonts.poppins(fontSize: 9, fontWeight: FontWeight.w600, color: Colors.white)),
                      ),
                    ),
                ],
              ),
            ),
            // Product details
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Product name
                    Text(
                      product.name,
                      style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w600),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    // Store name
                    Row(
                      children: [
                        const Icon(Icons.storefront, size: 13, color: AppColors.secondary),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            product.storeName ?? 'Store',
                            style: GoogleFonts.poppins(fontSize: 12, color: AppColors.secondary, fontWeight: FontWeight.w500),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    // Distance + delivery info
                    Row(
                      children: [
                        if (distance.isNotEmpty) ...[
                          Icon(Icons.location_on, size: 12, color: Colors.grey.shade500),
                          const SizedBox(width: 2),
                          Text(distance, style: GoogleFonts.poppins(fontSize: 11, color: AppColors.textSecondary)),
                          const SizedBox(width: 8),
                        ],
                        Icon(Icons.shield_outlined, size: 12, color: Colors.green.shade600),
                        const SizedBox(width: 2),
                        Text('Escrow', style: GoogleFonts.poppins(fontSize: 11, color: Colors.green.shade600, fontWeight: FontWeight.w500)),
                      ],
                    ),
                    const SizedBox(height: 6),
                    // Price + live public stock
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Rs. ${product.price.toStringAsFixed(0)}',
                            style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.primary),
                          ),
                        ),
                        Text(
                          '${product.publicStock} left',
                          style: GoogleFonts.poppins(
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                            color: product.isLowStock ? AppColors.stockRed : AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            // Arrow
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Icon(Icons.arrow_forward_ios, size: 14, color: Colors.grey.shade400),
            ),
          ],
        ),
      ),
    );
  }

  void _showLocationPicker() {
    final controller = TextEditingController(text: _locationName);
    LatLng pickedLocation = LatLng(_customerLat, _customerLng);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Padding(
              padding: EdgeInsets.only(
                left: 20,
                right: 20,
                top: 20,
                bottom: MediaQuery.of(context).viewInsets.bottom + 20,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Set Your Location', style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  Text('Tap on the map to pick your delivery location', style: GoogleFonts.poppins(fontSize: 13, color: AppColors.textSecondary)),
                  const SizedBox(height: 16),
                  TextField(
                    controller: controller,
                    decoration: InputDecoration(
                      hintText: 'e.g., Blue Area, Islamabad',
                      prefixIcon: const Icon(Icons.search, color: AppColors.secondary),
                      filled: true,
                      fillColor: Colors.grey.shade50,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: Colors.grey.shade200),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  // Real Map
                  MapPickerWidget(
                    initialCenter: pickedLocation,
                    initialZoom: 14.0,
                    interactive: true,
                    height: 220,
                    onLocationSelected: (latLng) {
                      setModalState(() => pickedLocation = latLng);
                    },
                  ),
                  const SizedBox(height: 12),
                  // Quick location options
                  Wrap(
                    spacing: 8,
                    children: [
                      _locationChip('📍 Use GPS', Icons.my_location),
                      _locationChip('🏠 Blue Area', null),
                      _locationChip('🏙️ F-8 Sector', null),
                      _locationChip('🏫 COMSATS Wah', null),
                    ],
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () async {
                        final name = controller.text.trim().isNotEmpty ? controller.text.trim() : _locationName;
                        await CustomerLocationStorage.save(
                          latitude: pickedLocation.latitude,
                          longitude: pickedLocation.longitude,
                          locationName: name,
                          addressLine: controller.text.trim().isNotEmpty ? controller.text.trim() : null,
                        );
                        if (!mounted) return;
                        setState(() {
                          _locationName = name;
                          _customerLat = pickedLocation.latitude;
                          _customerLng = pickedLocation.longitude;
                        });
                        if (!context.mounted) return;
                        Navigator.pop(context);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: Text('Confirm Location', style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _locationChip(String label, IconData? icon) {
    return ActionChip(
      label: Text(label, style: GoogleFonts.poppins(fontSize: 12)),
      backgroundColor: Colors.grey.shade100,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      onPressed: () {
        setState(() => _locationName = label.replaceAll(RegExp(r'[^\x00-\x7F]'), '').trim());
        Navigator.pop(context);
      },
    );
  }

  static const _categoryColors = [
    Color(0xFFE8F5E9), Color(0xFFE3F2FD), Color(0xFFFFF3E0),
    Color(0xFFF3E5F5), Color(0xFFFCE4EC), Color(0xFFE0F2F1),
  ];

  String _listTitle() {
    if (_search.isNotEmpty) return 'Results for "$_search"';
    if (_categoryId != null) {
      final cats = context.read<CategoryBloc>().state.categories.where((c) => c.id == _categoryId);
      if (cats.isNotEmpty) return cats.first.name;
    }
    return "Today's Picks";
  }

  Widget _categoryChip(IconData icon, String label, Color bgColor,
      {required bool selected, required VoidCallback onTap}) {
    return Padding(
      padding: const EdgeInsets.only(right: 14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: SizedBox(
          width: 68,
          child: Column(
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: selected ? AppColors.secondary : bgColor,
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: selected ? Colors.white : AppColors.secondary, size: 26),
              ),
              const SizedBox(height: 6),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: GoogleFonts.poppins(
                  fontSize: 11,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  color: selected ? AppColors.secondary : AppColors.textPrimary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildOrdersTab() {
    return const CustomerOrdersPanel(showTopPadding: true);
  }

  Widget _buildCustomerDrawer(BuildContext context) {
    return Drawer(
      child: SafeArea(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            DrawerHeader(
              decoration: const BoxDecoration(
                gradient: LinearGradient(colors: [AppColors.secondary, Color(0xFF1A6DB5)]),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Vendra', style: GoogleFonts.poppins(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  Text('Customer', style: GoogleFonts.poppins(color: Colors.white70, fontSize: 13)),
                ],
              ),
            ),
            ListTile(
              leading: const Icon(Icons.home_outlined),
              title: const Text('Home'),
              onTap: () {
                Navigator.pop(context);
                setState(() => _currentNavIndex = 0);
              },
            ),
            ListTile(
              leading: const Icon(Icons.map_outlined),
              title: const Text('Explore map'),
              onTap: () {
                Navigator.pop(context);
                setState(() => _currentNavIndex = 1);
              },
            ),
            ListTile(
              leading: const Icon(Icons.receipt_long_outlined),
              title: const Text('Orders'),
              onTap: () {
                Navigator.pop(context);
                setState(() => _currentNavIndex = 2);
              },
            ),
            ListTile(
              leading: const Icon(Icons.favorite_outline),
              title: const Text('Saved & events'),
              onTap: () {
                Navigator.pop(context);
                setState(() => _currentNavIndex = 3);
              },
            ),
            ListTile(
              leading: const Icon(Icons.person_outline),
              title: const Text('Profile & wallet'),
              onTap: () {
                Navigator.pop(context);
                setState(() => _currentNavIndex = 4);
              },
            ),
            ListTile(
              leading: const Icon(Icons.account_balance_wallet_outlined),
              title: const Text('Wallet & transactions'),
              onTap: () {
                Navigator.pop(context);
                Navigator.pushNamed(context, AppRoutes.wallet);
              },
            ),
            ListTile(
              leading: const Icon(Icons.gavel_outlined),
              title: const Text('My disputes'),
              onTap: () {
                Navigator.pop(context);
                Navigator.pushNamed(context, AppRoutes.myDisputes);
              },
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.shopping_cart_outlined),
              title: const Text('Cart'),
              onTap: () {
                Navigator.pop(context);
                Navigator.pushNamed(context, AppRoutes.cart);
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProfileTab() {
    return BlocBuilder<AuthBloc, AuthState>(
      builder: (context, authState) {
        if (authState is! Authenticated) {
          return const Center(child: CircularProgressIndicator());
        }

        final user = authState.user;

        return SingleChildScrollView(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 24),
              Center(
                child: Column(
                  children: [
                    const CircleAvatar(
                      radius: 40,
                      backgroundColor: AppColors.primary,
                      child: Icon(Icons.person, size: 40, color: Colors.white),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      user.fullName,
                      style: GoogleFonts.poppins(fontSize: 20, fontWeight: FontWeight.bold, color: AppColors.secondary),
                    ),
                    Text(
                      user.email,
                      style: GoogleFonts.poppins(fontSize: 14, color: AppColors.textSecondary),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 32),
              
              Text('My Wallet', style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.w600, color: AppColors.secondary)),
              const SizedBox(height: 16),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF2E7D32), Color(0xFF1B5E20)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(color: Colors.green.withValues(alpha: 0.3), blurRadius: 10, offset: const Offset(0, 4)),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text('Available Balance',
                              style: GoogleFonts.poppins(color: Colors.green.shade100, fontSize: 14)),
                        ),
                        TextButton(
                          onPressed: () => Navigator.pushNamed(context, AppRoutes.wallet),
                          style: TextButton.styleFrom(foregroundColor: Colors.white),
                          child: const Text('Transactions'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Rs. ${user.walletBalance.toStringAsFixed(2)}',
                      style: GoogleFonts.poppins(color: Colors.white, fontSize: 28, fontWeight: FontWeight.bold),
                    ),
                    if (user.platformEscrowBalance > 0) ...[
                      const SizedBox(height: 8),
                      Text(
                        'Platform escrow pool: Rs. ${user.platformEscrowBalance.toStringAsFixed(2)}',
                        style: GoogleFonts.poppins(color: Colors.white70, fontSize: 11),
                      ),
                    ],
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.white,
                              foregroundColor: Colors.green.shade800,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                            icon: const Icon(Icons.add_circle_outline),
                            label: const Text('Top Up (Rs. 5000)'),
                            onPressed: () => _handleTopup(context, 5000),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.white,
                              side: const BorderSide(color: Colors.white),
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                            icon: const Icon(Icons.arrow_downward),
                            label: const Text('Withdraw'),
                            onPressed: () {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Withdrawal feature coming soon.')),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 32),
              
              Text('Account', style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.w600, color: AppColors.secondary)),
              const SizedBox(height: 16),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.location_on_outlined, color: AppColors.textSecondary),
                title: Text('Saved Addresses', style: GoogleFonts.poppins()),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {},
              ),
              const Divider(),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.history, color: AppColors.textSecondary),
                title: Text('Wallet Ledger', style: GoogleFonts.poppins()),
                subtitle: Text('Top-ups, escrow holds and refunds', style: GoogleFonts.poppins(fontSize: 12)),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.pushNamed(context, AppRoutes.wallet),
              ),
              const Divider(),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.gavel_outlined, color: AppColors.textSecondary),
                title: Text('My Disputes', style: GoogleFonts.poppins()),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.pushNamed(context, AppRoutes.myDisputes),
              ),
              const Divider(),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.lock_reset, color: AppColors.textSecondary),
                title: Text('Change password', style: GoogleFonts.poppins()),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const ChangePasswordScreen()),
                ),
              ),
              const Divider(),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.logout, color: AppColors.error),
                title: Text('Logout', style: GoogleFonts.poppins(color: AppColors.error)),
                onTap: () {
                  context.read<AuthBloc>().add(LogoutRequested());
                  Navigator.pushReplacementNamed(context, AppRoutes.login);
                },
              ),
            ],
          ),
        );
      },
    );
  }
  
  Future<void> _handleTopup(BuildContext context, double amount) async {
    try {
      final api = ApiService();
      final res = await api.post(ApiConfig.walletTopup, data: {'amount': amount});
      if (res.data['success'] == true) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Wallet topped up successfully!'), behavior: SnackBarBehavior.floating),
          );
          final wb = res.data['walletBalance'];
          if (wb != null) {
            context.read<AuthBloc>().add(AuthWalletBalanceUpdated(walletBalance: (wb as num).toDouble()));
          }
          context.read<AuthBloc>().add(CheckAuthRequested());
        }
      } else {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(res.data['message'] ?? 'Top up failed'), backgroundColor: AppColors.error),
          );
        }
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Network error. Try again.'), backgroundColor: AppColors.error),
        );
      }
    }
  }

  Widget _buildExploreTab() {
    return BlocBuilder<CustomerProductBloc, CustomerProductState>(
      builder: (context, state) {
        if (state is CustomerProductLoaded) {
          // Extract unique vendors from products
          final Map<int, MapMarkerData> vendorMarkers = {};
          
          for (var p in state.products) {
            if (p.vendorLat != null && p.vendorLng != null) {
              vendorMarkers[p.vendorId] = MapMarkerData(
                position: LatLng(p.vendorLat!, p.vendorLng!),
                label: p.storeName ?? 'Store',
                icon: Icons.store,
                color: AppColors.secondary,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => StoreScreen(vendorId: p.vendorId, storeName: p.storeName ?? 'Store'),
                  ),
                ),
              );
            }
          }

          final List<MapMarkerData> markers = [];
          markers.add(
            MapMarkerData(
              position: LatLng(_customerLat, _customerLng),
              label: 'You are here',
              icon: Icons.person_pin_circle,
              color: AppColors.primary,
            ),
          );
          for (var marker in vendorMarkers.values) {
            markers.add(marker);
          }

          return Stack(
            children: [
              Positioned.fill(
                child: MapPickerWidget(
                  initialCenter: LatLng(_customerLat, _customerLng),
                  initialZoom: 13.0,
                  interactive: false,
                  height: double.infinity,
                  markers: markers,
                ),
              ),
              Positioned(
                top: 16,
                left: 16,
                right: 16,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.9),
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 8)],
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.map, color: AppColors.secondary),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Explore Nearby Vendors',
                          style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
                        ),
                      ),
                      Text('${vendorMarkers.length} found', style: GoogleFonts.poppins(fontSize: 12, color: AppColors.textSecondary)),
                    ],
                  ),
                ),
              ),
            ],
          );
        }
        
        return const Center(child: CircularProgressIndicator());
      },
    );
  }

  Widget _buildPlaceholderTab(String label) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.event_available_outlined, size: 56, color: Colors.grey.shade400),
            const SizedBox(height: 16),
            Text(label, style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Text(
              'Saved products and local vendor events will appear here in a future update.',
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(fontSize: 13, color: AppColors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomNav() {
    return BottomNavigationBar(
      currentIndex: _currentNavIndex,
      onTap: (index) => setState(() => _currentNavIndex = index),
      items: const [
        BottomNavigationBarItem(icon: Icon(Icons.home_outlined), activeIcon: Icon(Icons.home), label: 'Home'),
        BottomNavigationBarItem(icon: Icon(Icons.search), label: 'Explore'),
        BottomNavigationBarItem(icon: Icon(Icons.receipt_long_outlined), label: 'Orders'),
        BottomNavigationBarItem(icon: Icon(Icons.favorite_outline), label: 'Saved'),
        BottomNavigationBarItem(icon: Icon(Icons.person_outline), label: 'Profile'),
      ],
    );
  }
}
