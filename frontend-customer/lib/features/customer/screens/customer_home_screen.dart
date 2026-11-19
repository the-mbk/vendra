// ══════════════════════════════════════════════════════════════
// Vendra App - Customer Home Screen
// Products show store info (with the store's logo), location & distance.
// Tapping a product → its product page (photos, store, reviews); tapping
// a store (search matches, Explore map/list) → the store page.
// Categories come from GET /api/categories and filter the product list
// together with search (FR06). Stock on the list is live (FR01).
// The product list is paged: the next page loads as the customer
// scrolls near the bottom (a new search/category starts from page 1).
// ══════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:latlong2/latlong.dart';
import 'dart:async';
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
import '../widgets/home_product_tile.dart';
import '../widgets/store_widgets.dart';
import '../widgets/wallet_actions.dart';
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
  Timer? _searchDebounce;

  /// Stores whose name or area matches [_search] (shown above the products)
  List<_MapStore> _storeMatches = const [];

  /// The wallet and profile shown here are re-read from the server whenever an
  /// order changes (refunds, cancellations, disputes) and when the app comes back
  /// to the front, so they always match the last state, not the login-time copy.
  StreamSubscription<OrderUpdateEvent>? _orderSub;
  Timer? _refreshDebounce;
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    _homeScroll.addListener(_maybeLoadMoreProducts);
    context.read<CategoryBloc>().add(const FetchCategories());
    _fetchProducts();
    _loadSavedLocation();
    _orderSub = RealtimeService().orderUpdates.listen((_) => _refreshUser());
    _lifecycle = AppLifecycleListener(onResume: _refreshUser);
    _refreshUser();
  }

  void _refreshUser() {
    _refreshDebounce?.cancel();
    _refreshDebounce = Timer(const Duration(milliseconds: 600), () {
      if (mounted) context.read<AuthBloc>().add(AuthUserRefreshRequested());
    });
  }

  void _editProfile(UserModel user) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => EditProfileScreen(
          user: user,
          onSaved: () => context.read<AuthBloc>().add(AuthUserRefreshRequested()),
        ),
      ),
    );
  }

  void _fetchProducts() {
    context.read<CustomerProductBloc>().add(FetchProducts(
          search: _search.isNotEmpty ? _search : null,
          categoryId: _categoryId,
        ));
    _searchStores();
  }

  /// Runs the search a moment after the customer stops typing
  void _onSearchChanged(String value) {
    setState(() {});
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 400), () {
      if (!mounted || value.trim() == _search) return;
      setState(() => _search = value.trim());
      _fetchProducts();
    });
  }

  void _submitSearch(String value) {
    _searchDebounce?.cancel();
    setState(() => _search = value.trim());
    _fetchProducts();
  }

  /// Stores matching the search box, nearest first
  Future<void> _searchStores() async {
    final query = _search;
    if (query.isEmpty) {
      if (_storeMatches.isNotEmpty) setState(() => _storeMatches = const []);
      return;
    }
    try {
      final res = await ApiService().get(ApiConfig.stores,
          queryParams: {'search': query, 'lat': _customerLat, 'lng': _customerLng});
      final list = (res.data['data'] as List<dynamic>? ?? const [])
          .whereType<Map>()
          .map((m) => _MapStore.fromJson(Map<String, dynamic>.from(m)))
          .toList();
      if (!mounted || query != _search) return;
      setState(() => _storeMatches = list);
    } catch (_) {
      // Store matches are extra; the product results still show
      if (mounted && query == _search) setState(() => _storeMatches = const []);
    }
  }

  void _openStore(_MapStore st) {
    Navigator.push(context, MaterialPageRoute(builder: (context) => StoreScreen(vendorId: st.id, storeName: st.name)));
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
    _searchDebounce?.cancel();
    _searchController.clear();
    setState(() {
      _search = '';
      _categoryId = null;
    });
    _fetchProducts();
  }

  /// Empty results: say what matched nothing and offer a way on (clear, or a category)
  Widget _noProducts() {
    final filtered = _categoryId != null || _search.isNotEmpty;
    final categories = context.read<CategoryBloc>().state.categories.where((c) => c.id != _categoryId).take(6).toList();
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
      child: Column(
        children: [
          Icon(filtered ? Icons.search_off_rounded : Icons.storefront_outlined, size: 56, color: AppColors.textLight),
          const SizedBox(height: 12),
          Text(
            !filtered
                ? 'No products available yet'
                : _search.isNotEmpty
                    ? 'No products match "$_search"'
                    : 'Nothing in this category yet',
            textAlign: TextAlign.center,
            style: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
          ),
          if (filtered) ...[
            const SizedBox(height: 4),
            Text('Check the spelling, or browse a category instead.',
                textAlign: TextAlign.center, style: GoogleFonts.poppins(fontSize: 13, color: AppColors.textSecondary)),
            const SizedBox(height: 14),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final c in categories)
                  ActionChip(
                    avatar: Icon(CategoryStyle.of(c).icon, size: 16, color: CategoryStyle.of(c).tone),
                    label: Text(c.name),
                    onPressed: () {
                      _searchDebounce?.cancel();
                      _searchController.clear();
                      setState(() {
                        _search = '';
                        _categoryId = c.id;
                      });
                      _fetchProducts();
                    },
                  ),
              ],
            ),
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: _clearFilters,
              icon: const Icon(Icons.clear_all, size: 18),
              label: const Text('Show everything'),
            ),
          ],
        ],
      ),
    );
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
    _orderSub?.cancel();
    _refreshDebounce?.cancel();
    _lifecycle.dispose();
    _searchDebounce?.cancel();
    _searchController.dispose();
    _exploreSearch.dispose();
    _homeScroll.dispose();
    super.dispose();
  }

  String _distanceText(ProductModel product) {
    if (product.vendorLat == null || product.vendorLng == null) return '';
    return distanceLabel(haversineKm(_customerLat, _customerLng, product.vendorLat!, product.vendorLng!));
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
      backgroundColor: AppColors.surface,
      elevation: 0,
      leading: Builder(
        builder: (ctx) => IconButton(
          icon: Icon(Icons.menu, color: AppColors.textPrimary),
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
                  color: AppColors.successSurface,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: AppColors.success.withValues(alpha: 0.35)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.account_balance_wallet, size: 16, color: AppColors.successInk),
                    const SizedBox(width: 6),
                    Text(
                      formatRupees(authState.user.walletBalance),
                      style: GoogleFonts.poppins(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppColors.successInk,
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
        const ThemeToggleButton(),
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
                color: AppColors.surface,
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
                          Icon(Icons.map_outlined, size: 14, color: AppColors.secondary),
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
                onChanged: _onSearchChanged,
                onSubmitted: _submitSearch,
                decoration: InputDecoration(
                  hintText: 'Search products or stores...',
                  prefixIcon: Icon(Icons.search, color: AppColors.textLight),
                  suffixIcon: _searchController.text.isEmpty && _search.isEmpty
                      ? null
                      : IconButton(
                          tooltip: 'Clear search',
                          icon: Icon(Icons.close, color: AppColors.textLight),
                          onPressed: () {
                            _searchDebounce?.cancel();
                            _searchController.clear();
                            setState(() => _search = '');
                            _fetchProducts();
                          },
                        ),
                  filled: true,
                  fillColor: AppColors.surface,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(color: AppColors.hairline),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(color: AppColors.hairline),
                  ),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                ),
              ),
            ),

            // Escrow banner (how every payment on Vendra works — no promo codes)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: AppColors.brandGradient,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Escrow-protected payments',
                              style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.w700, color: Colors.white)),
                          const SizedBox(height: 4),
                          Text('Your money is held safely until your order is delivered.',
                              style: GoogleFonts.poppins(fontSize: 13, height: 1.35, color: Colors.white.withValues(alpha: 0.85))),
                          const SizedBox(height: 10),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.18),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.store_mall_directory_outlined, size: 14, color: Colors.white),
                                const SizedBox(width: 6),
                                Text('Local stores · Live tracking',
                                    style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.white)),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Icon(Icons.verified_user_outlined, size: 52, color: Colors.white38),
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
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: catState.categories.length + 1,
                    separatorBuilder: (_, __) => const SizedBox(width: 10),
                    itemBuilder: (context, i) {
                      if (i == 0) {
                        return CustomCategoryChip(
                          label: 'All',
                          style: CategoryStyle.all,
                          selected: _categoryId == null,
                          onTap: () => _selectCategory(null),
                        );
                      }
                      final category = catState.categories[i - 1];
                      return CustomCategoryChip(
                        label: category.name,
                        style: CategoryStyle.of(category),
                        selected: _categoryId == category.id,
                        onTap: () => _selectCategory(category.id),
                      );
                    },
                  ),
                );
              },
            ),

            const SizedBox(height: 20),

            // Stores matching the search
            if (_search.isNotEmpty && _storeMatches.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  'Stores (${_storeMatches.length})',
                  style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w600),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                height: StoreBannerCard.height,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: _storeMatches.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 10),
                  itemBuilder: (context, i) => _storeMatchCard(_storeMatches[i]),
                ),
              ),
              const SizedBox(height: 20),
            ],

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
                          Icon(Icons.error_outline, size: 48, color: AppColors.textLight),
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
                  if (state.products.isEmpty) return _noProducts();

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
                      // Opens the product's own page
                      return HomeProductTile(product: product, distance: _distanceText(product));
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

  /// Demo drop-off pins next to the demo stores (development builds only)
  static const _demoPresets = [
    ('Saddar, Karachi', LatLng(24.8620, 67.0300)),
    ('Gulberg, Lahore', LatLng(31.5200, 74.3580)),
    ('Blue Area, Islamabad', LatLng(33.7150, 73.0600)),
    ('COMSATS, Wah Cantt', LatLng(33.7810, 72.8240)),
  ];

  /// "Saddar, Karachi · 1.0 km to Karachi Electronics Hub" when a store delivers there
  static String _presetLabel(String name, LatLng at, List<_MapStore> stores) {
    _MapStore? nearest;
    var best = double.infinity;
    for (final st in stores) {
      final km = haversineKm(at.latitude, at.longitude, st.lat, st.lng);
      if (km < best) {
        best = km;
        nearest = st;
      }
    }
    if (nearest == null || !AppConfig.current.deliversAt(best)) return name;
    return '$name · ${best.toStringAsFixed(1)} km to ${nearest.name}';
  }

  Future<void> _showLocationPicker() async {
    // The picker shows every store as a pin, so the customer can set a drop-off in range
    if (_stores == null && !_storesLoading) await _loadStores();
    if (!mounted) return;
    final stores = _stores ?? const <_MapStore>[];
    final showPresets = AppConfig.current.isDevelopment;
    final controller = TextEditingController(text: _locationName);
    LatLng pickedLocation = LatLng(_customerLat, _customerLng);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            Widget presetChip(String name, LatLng coords) {
              final isMatch = (pickedLocation.latitude - coords.latitude).abs() < 0.005 &&
                  (pickedLocation.longitude - coords.longitude).abs() < 0.005;
              return ActionChip(
                avatar: Icon(Icons.place_outlined, size: 16, color: isMatch ? AppColors.primary : AppColors.textSecondary),
                label: Text(_presetLabel(name, coords, stores),
                    style: GoogleFonts.poppins(fontSize: 11.5, fontWeight: isMatch ? FontWeight.w600 : FontWeight.w500)),
                backgroundColor: isMatch ? AppColors.primary.withValues(alpha: 0.15) : AppColors.surfaceMuted,
                side: BorderSide(color: isMatch ? AppColors.primary : AppColors.hairline),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                onPressed: () {
                  setModalState(() {
                    pickedLocation = coords;
                    controller.text = name;
                  });
                },
              );
            }

            return Padding(
              padding: EdgeInsets.only(
                left: 20,
                right: 20,
                top: 20,
                bottom: MediaQuery.of(context).viewInsets.bottom + 20,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Set Your Location', style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.w600)),
                        IconButton(
                          icon: const Icon(Icons.close, size: 20),
                          onPressed: () => Navigator.pop(context),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      stores.isEmpty ? 'Tap the map to drop your delivery pin' : 'Tap the map to drop your delivery pin. Store pins show where you can order from.',
                      style: GoogleFonts.poppins(fontSize: 12.5, color: AppColors.textSecondary),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: controller,
                      decoration: InputDecoration(
                        hintText: 'e.g., Clifton / Saddar, Karachi',
                        prefixIcon: Icon(Icons.search, color: AppColors.secondary),
                        filled: true,
                        fillColor: AppColors.surfaceMuted,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: AppColors.hairline),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    // Interactive Map with pin
                    MapPickerWidget(
                      key: ValueKey('${pickedLocation.latitude}_${pickedLocation.longitude}'),
                      initialCenter: pickedLocation,
                      initialZoom: 14.0,
                      interactive: true,
                      height: 220,
                      markers: [
                        for (final st in stores)
                          MapMarkerData(
                            position: LatLng(st.lat, st.lng),
                            label: st.name,
                            icon: Icons.storefront_rounded,
                            color: AppColors.secondary,
                          ),
                      ],
                      onLocationSelected: (latLng) {
                        setModalState(() => pickedLocation = latLng);
                      },
                    ),
                    if (showPresets) ...[
                      const SizedBox(height: 12),
                      Text('Demo locations (development only)',
                          style: GoogleFonts.poppins(fontSize: 11.5, fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        children: [for (final (name, at) in _demoPresets) presetChip(name, at)],
                      ),
                    ],
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
              ),
            );
          },
        );
      },
    );
  }

  String _listTitle() {
    if (_search.isNotEmpty) return 'Results for "$_search"';
    if (_categoryId != null) {
      final cats = context.read<CategoryBloc>().state.categories.where((c) => c.id == _categoryId);
      if (cats.isNotEmpty) return cats.first.name;
    }
    return "Today's Picks";
  }

  Widget _buildOrdersTab() {
    return const CustomerOrdersPanel(showTopPadding: true);
  }

  Widget _buildCustomerDrawer(BuildContext context) {
    final auth = context.read<AuthBloc>().state;
    final user = auth is Authenticated ? auth.user : null;
    return Drawer(
      backgroundColor: AppColors.surface,
      child: ListTileTheme(
        iconColor: AppColors.secondary,
        textColor: AppColors.textPrimary,
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            Container(
              padding: EdgeInsets.fromLTRB(20, MediaQuery.of(context).padding.top + 36, 20, 20),
              decoration: const BoxDecoration(gradient: AppColors.brandGradient),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(2),
                    decoration: const BoxDecoration(color: Colors.white24, shape: BoxShape.circle),
                    child: UserAvatar(name: user?.fullName, photoUrl: user?.avatarUrl, size: 52),
                  ),
                  const SizedBox(height: 12),
                  Text(user?.fullName ?? 'Vendra',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.poppins(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700)),
                  Text(user?.email ?? 'Customer',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.poppins(color: Colors.white70, fontSize: 13)),
                  if (user != null) ...[
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.account_balance_wallet_outlined, size: 14, color: Colors.white),
                          const SizedBox(width: 6),
                          Text('Wallet ${formatRupees(user.walletBalance)}',
                              style: GoogleFonts.poppins(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 8),
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
              title: const Text('Saved'),
              onTap: () {
                Navigator.pop(context);
                setState(() => _currentNavIndex = 3);
              },
            ),
            ListTile(
              leading: const Icon(Icons.person_outline),
              title: const Text('Profile'),
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
                    UserAvatar(name: user.fullName, photoUrl: user.avatarUrl, size: 84),
                    const SizedBox(height: 12),
                    Text(
                      user.fullName,
                      style: GoogleFonts.poppins(fontSize: 20, fontWeight: FontWeight.bold, color: AppColors.secondary),
                    ),
                    Text(
                      user.email,
                      style: GoogleFonts.poppins(fontSize: 14, color: AppColors.textSecondary),
                    ),
                    if (user.phone != null)
                      Text(user.phone!, style: GoogleFonts.poppins(fontSize: 13, color: AppColors.textSecondary)),
                    const SizedBox(height: 10),
                    OutlinedButton.icon(
                      onPressed: () => _editProfile(user),
                      icon: const Icon(Icons.edit_outlined, size: 18),
                      label: const Text('Edit profile'),
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
                  gradient: AppColors.brandGradient,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(color: AppColors.navy.withValues(alpha: 0.25), blurRadius: 12, offset: const Offset(0, 4)),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text('Available Balance',
                              style: GoogleFonts.poppins(color: Colors.white70, fontSize: 14)),
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
                      formatRupees(user.walletBalance),
                      style: GoogleFonts.poppins(color: Colors.white, fontSize: 28, fontWeight: FontWeight.bold),
                    ),
                    if (user.platformEscrowBalance > 0) ...[
                      const SizedBox(height: 8),
                      Text(
                        'Platform escrow pool: ${formatRupees(user.platformEscrowBalance)}',
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
                              foregroundColor: AppColors.navy,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                            icon: const Icon(Icons.add_card),
                            label: const Text('Add money'),
                            onPressed: () => _handleTopup(context),
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
                            icon: const Icon(Icons.north_east),
                            label: const Text('Withdraw'),
                            onPressed: () => startWithdrawal(context, balance: user.walletBalance),
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
                leading: Icon(Icons.location_on_outlined, color: AppColors.textSecondary),
                title: Text('Delivery location', style: GoogleFonts.poppins()),
                subtitle: Text(_locationName, maxLines: 1, overflow: TextOverflow.ellipsis, style: GoogleFonts.poppins(fontSize: 12)),
                trailing: const Icon(Icons.chevron_right),
                onTap: _showLocationPicker,
              ),
              const Divider(),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.history, color: AppColors.textSecondary),
                title: Text('Wallet Ledger', style: GoogleFonts.poppins()),
                subtitle: Text('Top-ups, escrow holds, refunds and withdrawals', style: GoogleFonts.poppins(fontSize: 12)),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.pushNamed(context, AppRoutes.wallet),
              ),
              const Divider(),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.gavel_outlined, color: AppColors.textSecondary),
                title: Text('My Disputes', style: GoogleFonts.poppins()),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.pushNamed(context, AppRoutes.myDisputes),
              ),
              const Divider(),
              const ThemeModeTile(contentPadding: EdgeInsets.zero),
              const Divider(),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.lock_reset, color: AppColors.textSecondary),
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
  
  /// Card top-up (amount → card → one-time password if asked)
  Future<void> _handleTopup(BuildContext context) async {
    final result = await startCardTopUp(context);
    if (result == null || !context.mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(result.message),
        backgroundColor: result.success ? AppColors.stockGreen : AppColors.error,
        behavior: SnackBarBehavior.floating,
      ));
  }

  /// Every open store for the Explore map (GET /api/stores), nearest first.
  /// [_storesFor] is the location they were fetched for; moving re-fetches.
  List<_MapStore>? _stores;
  String? _storesFor;
  bool _storesLoading = false;
  String? _storesError;

  Future<void> _loadStores() async {
    final at = '$_customerLat,$_customerLng';
    setState(() {
      _storesFor = at;
      _storesLoading = true;
      _storesError = null;
    });
    try {
      final res = await ApiService().get(ApiConfig.stores, queryParams: {'lat': _customerLat, 'lng': _customerLng});
      final list = (res.data['data'] as List<dynamic>? ?? const [])
          .whereType<Map>()
          .map((m) => _MapStore.fromJson(Map<String, dynamic>.from(m)))
          .toList();
      if (!mounted || _storesFor != at) return;
      setState(() {
        _stores = list;
        _storesLoading = false;
      });
    } catch (e) {
      if (!mounted || _storesFor != at) return;
      setState(() {
        _storesLoading = false;
        _storesError = ApiService.getErrorMessage(e);
      });
    }
  }

  /// A store matching the search: its cover as a banner with the logo on top
  Widget _storeMatchCard(_MapStore st) {
    return StoreBannerCard(
      storeName: st.name,
      logoUrl: st.logoUrl,
      coverUrl: st.coverUrl,
      subtitle: _storeSubtitle(st),
      warn: st.deliversToYou == false,
      onTap: () => _openStore(st),
    );
  }

  /// "2.9 km · 30 products" (+ "pickup only" beyond the delivery radius)
  String _storeSubtitle(_MapStore st) {
    final parts = <String>[
      if (st.distanceKm != null) '${st.distanceKm!.toStringAsFixed(1)} km',
      '${st.productCount} products',
      if (st.deliversToYou == false) 'pickup only',
    ];
    return parts.join(' · ');
  }

  /// Explore map search: filters the pins by store name or area
  final _exploreSearch = TextEditingController();

  List<_MapStore> _exploreMatches(List<_MapStore> stores) {
    final q = _exploreSearch.text.trim().toLowerCase();
    if (q.isEmpty) return stores;
    return stores
        .where((st) => st.name.toLowerCase().contains(q) || (st.address ?? '').toLowerCase().contains(q))
        .toList();
  }

  Widget _buildExploreTab() {
    // Fetch on first build and whenever the customer's location changes
    if (_storesFor != '$_customerLat,$_customerLng' && !_storesLoading) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _loadStores();
      });
    }
    final searching = _exploreSearch.text.trim().isNotEmpty;
    final stores = _exploreMatches(_stores ?? const <_MapStore>[]);
    final delivering = stores.where((st) => st.deliversToYou != false).length;

    final markers = <MapMarkerData>[
      MapMarkerData(
        position: LatLng(_customerLat, _customerLng),
        label: 'You are here',
        icon: Icons.person_pin_circle,
        color: AppColors.primary,
      ),
      for (final st in stores)
        MapMarkerData(
          position: LatLng(st.lat, st.lng),
          label: '${st.name} · ${st.productCount} products${st.deliversToYou == false ? ' · pickup only' : ''}',
          icon: Icons.store,
          color: st.deliversToYou == false ? AppColors.textLight : AppColors.secondary,
          onTap: () => _openStore(st),
        ),
    ];

    return Stack(
      children: [
        Positioned.fill(
          child: MapPickerWidget(
            // The key re-centres the map when the customer moves
            key: ValueKey('$_customerLat,$_customerLng'),
            initialCenter: LatLng(_customerLat, _customerLng),
            initialZoom: 13.0,
            interactive: false,
            height: double.infinity,
            markers: markers,
          ),
        ),
        Positioned(
          top: 12,
          left: 12,
          // Leaves the map's zoom buttons (top-right) uncovered
          right: 64,
          child: Container(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.96),
              borderRadius: BorderRadius.circular(14),
              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.12), blurRadius: 12, offset: const Offset(0, 3))],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: AppColors.secondary.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(Icons.map_outlined, size: 20, color: AppColors.secondary),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Explore Nearby Vendors',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                          Text(
                            _storesLoading
                                ? 'Finding stores near you…'
                                : _storesError != null
                                    ? "Couldn't load stores"
                                    : '${stores.length} stores · $delivering deliver to you',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.poppins(
                                fontSize: 12, color: _storesError != null ? AppColors.error : AppColors.textSecondary),
                          ),
                        ],
                      ),
                    ),
                    if (_storesLoading)
                      const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    else if (_storesError != null)
                      TextButton(onPressed: _loadStores, child: const Text('Retry')),
                  ],
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _exploreSearch,
                  textInputAction: TextInputAction.search,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: 'Search stores by name or area',
                    prefixIcon: Icon(Icons.search, size: 20, color: AppColors.textLight),
                    suffixIcon: searching
                        ? IconButton(
                            tooltip: 'Clear search',
                            icon: Icon(Icons.close, size: 18, color: AppColors.textLight),
                            onPressed: () => setState(_exploreSearch.clear),
                          )
                        : null,
                    filled: true,
                    fillColor: AppColors.surface,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: AppColors.hairline),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: AppColors.hairline),
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  ),
                ),
                if (searching) ...[
                  const SizedBox(height: 6),
                  if (stores.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Text('No stores match "${_exploreSearch.text.trim()}"',
                          style: GoogleFonts.poppins(fontSize: 12, color: AppColors.textSecondary)),
                    )
                  else
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 230),
                      child: ListView.builder(
                        shrinkWrap: true,
                        padding: EdgeInsets.zero,
                        itemCount: stores.length,
                        itemBuilder: (context, i) {
                          final st = stores[i];
                          return ListTile(
                            dense: true,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                            leading: Opacity(
                              opacity: st.deliversToYou == false ? 0.55 : 1,
                              child: StoreLogo(storeName: st.name, logoUrl: st.logoUrl, size: 34),
                            ),
                            title: Text(st.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w600)),
                            subtitle: Text(_storeSubtitle(st),
                                style: GoogleFonts.poppins(fontSize: 11, color: AppColors.textSecondary)),
                            trailing: const Icon(Icons.chevron_right, size: 18),
                            onTap: () => _openStore(st),
                          );
                        },
                      ),
                    ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPlaceholderTab(String label) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 88,
              height: 88,
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.08),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.favorite_outline, size: 40, color: AppColors.primary),
            ),
            const SizedBox(height: 20),
            Text(label, style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
            const SizedBox(height: 8),
            Text(
              'Saved products and local vendor events will appear here in a future update.',
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(fontSize: 13, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 20),
            OutlinedButton.icon(
              onPressed: () => setState(() => _currentNavIndex = 0),
              style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12)),
              icon: const Icon(Icons.storefront_outlined, size: 18),
              label: const Text('Browse products'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomNav() {
    return BottomNavigationBar(
      currentIndex: _currentNavIndex,
      onTap: (index) {
        setState(() => _currentNavIndex = index);
        _refreshUser();
      },
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

/// A store pin on the Explore map
class _MapStore {
  final int id;
  final String name;
  final double lat;
  final double lng;
  final int productCount;
  final double? distanceKm;
  final String? address;
  final String? logoUrl;
  final String? coverUrl;

  /// Within the max delivery distance of the customer (null when unknown)
  final bool? deliversToYou;

  const _MapStore({required this.id, required this.name, required this.lat, required this.lng, required this.productCount, this.distanceKm, this.address, this.logoUrl, this.coverUrl, this.deliversToYou});

  factory _MapStore.fromJson(Map<String, dynamic> json) => _MapStore(
        id: toInt(json['id']),
        name: json['storeName'] ?? 'Store',
        lat: toDouble(json['latitude']),
        lng: toDouble(json['longitude']),
        productCount: toInt(json['productCount']),
        distanceKm: toDoubleOrNull(json['distanceKm']),
        address: json['storeAddress'] as String?,
        logoUrl: json['logoUrl'] as String?,
        coverUrl: json['coverUrl'] as String?,
        deliversToYou: json['deliversToYou'] is bool ? json['deliversToYou'] as bool : null,
      );
}
