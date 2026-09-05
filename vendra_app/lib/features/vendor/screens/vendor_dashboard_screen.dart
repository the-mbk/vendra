// ══════════════════════════════════════════════════════════════
// Vendra App - Vendor Dashboard Screen
// Adapted from Stitch vendor_dashboard_web design for mobile
// Uses BottomNavigationBar with 4 tabs
// ══════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../config/app_theme.dart';
import '../../../config/app_routes.dart';
import '../../../core/widgets/product_card.dart';
import '../../../core/widgets/loading_shimmer.dart';
import '../../auth/bloc/auth_bloc.dart';
import '../../auth/bloc/auth_state.dart' as auth_state;
import '../bloc/vendor_product_bloc.dart';
import '../bloc/vendor_order_bloc.dart';
import 'vendor_orders_screen.dart';
import 'stock_ledger_screen.dart';
import 'vendor_profile_screen.dart';

import 'vendor_location_screen.dart';

class VendorDashboardScreen extends StatefulWidget {
  const VendorDashboardScreen({super.key});

  @override
  State<VendorDashboardScreen> createState() => _VendorDashboardScreenState();
}

class _VendorDashboardScreenState extends State<VendorDashboardScreen> {
  int _currentIndex = 0;
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  @override
  void initState() {
    super.initState();
    context.read<VendorProductBloc>().add(FetchVendorProducts());
    context.read<VendorOrderBloc>().add(FetchVendorOrders());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: AppColors.background,
      drawer: Drawer(
        child: SafeArea(
          child: ListView(
            padding: EdgeInsets.zero,
            children: [
              DrawerHeader(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(colors: [Color(0xFF0D2137), Color(0xFF1565C0)]),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Vendor Panel', style: GoogleFonts.poppins(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 4),
                    Text('Manage store & orders', style: GoogleFonts.poppins(color: Colors.white70, fontSize: 12)),
                  ],
                ),
              ),
              ListTile(
                leading: const Icon(Icons.dashboard_outlined),
                title: const Text('Home'),
                onTap: () {
                  Navigator.pop(context);
                  setState(() => _currentIndex = 0);
                },
              ),
              ListTile(
                leading: const Icon(Icons.receipt_long_outlined),
                title: const Text('Orders'),
                onTap: () {
                  Navigator.pop(context);
                  setState(() => _currentIndex = 1);
                },
              ),
              ListTile(
                leading: const Icon(Icons.inventory_2_outlined),
                title: const Text('Stock ledger'),
                onTap: () {
                  Navigator.pop(context);
                  setState(() => _currentIndex = 2);
                },
              ),
              ListTile(
                leading: const Icon(Icons.person_outline),
                title: const Text('Profile'),
                onTap: () {
                  Navigator.pop(context);
                  setState(() => _currentIndex = 3);
                },
              ),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.map_outlined),
                title: const Text('Store location'),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(context, MaterialPageRoute(builder: (_) => const VendorLocationScreen()));
                },
              ),
              ListTile(
                leading: const Icon(Icons.add_circle_outline),
                title: const Text('Add product'),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.pushNamed(context, AppRoutes.addProduct);
                },
              ),
            ],
          ),
        ),
      ),
      body: IndexedStack(
        index: _currentIndex,
        children: [
          _buildHomeTab(),
          const VendorOrdersScreen(),
          const StockLedgerScreen(),
          const VendorProfileScreen(),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (i) => setState(() => _currentIndex = i),
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.dashboard_outlined), activeIcon: Icon(Icons.dashboard), label: 'Home'),
          BottomNavigationBarItem(icon: Icon(Icons.receipt_long_outlined), activeIcon: Icon(Icons.receipt_long), label: 'Orders'),
          BottomNavigationBarItem(icon: Icon(Icons.inventory_2_outlined), activeIcon: Icon(Icons.inventory_2), label: 'Ledger'),
          BottomNavigationBarItem(icon: Icon(Icons.person_outline), activeIcon: Icon(Icons.person), label: 'Profile'),
        ],
      ),
      floatingActionButton: _currentIndex == 0
          ? FloatingActionButton.extended(
              onPressed: () => Navigator.pushNamed(context, AppRoutes.addProduct),
              icon: const Icon(Icons.add),
              label: const Text('Add Product'),
            )
          : null,
    );
  }

  Widget _buildHomeTab() {
    return CustomScrollView(
      slivers: [
        // App bar
        SliverAppBar(
          floating: true,
          backgroundColor: Colors.white,
          leading: IconButton(
            icon: const Icon(Icons.menu, color: AppColors.textPrimary),
            onPressed: () => _scaffoldKey.currentState?.openDrawer(),
          ),
          automaticallyImplyLeading: false,
          title: BlocBuilder<AuthBloc, auth_state.AuthState>(
            builder: (context, state) {
              String storeName = 'My Store';
              if (state is auth_state.Authenticated) {
                storeName = state.user.storeName ?? 'My Store';
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Good morning! 👋',
                      style: GoogleFonts.poppins(fontSize: 13, color: AppColors.textSecondary, fontWeight: FontWeight.w400)),
                  Text(storeName, style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.w600, color: AppColors.secondary)),
                ],
              );
            },
          ),
          actions: [
            BlocBuilder<AuthBloc, auth_state.AuthState>(
              builder: (context, state) {
                if (state is auth_state.Authenticated) {
                  return Container(
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
                          'Rs. ${state.user.walletBalance.toStringAsFixed(0)}',
                          style: GoogleFonts.poppins(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: Colors.green.shade800,
                          ),
                        ),
                      ],
                    ),
                  );
                }
                return const SizedBox.shrink();
              },
            ),
            IconButton(
              icon: const Icon(Icons.notifications_outlined),
              onPressed: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Notifications coming soon.'), behavior: SnackBarBehavior.floating),
                );
              },
            ),
            const SizedBox(width: 8),
          ],
        ),

        // Stats cards
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: BlocBuilder<VendorOrderBloc, VendorOrderState>(
              builder: (context, orderState) {
                int orderCount = 0;
                int pendingCount = 0;
                if (orderState is VendorOrderLoaded) {
                  orderCount = orderState.orders.length;
                  pendingCount = orderState.orders.where((o) => o.status == 'pending').length;
                }
                return Column(
                  children: [
                    Row(
                      children: [
                        _statCard("Today's Orders", '$orderCount', Icons.shopping_bag_outlined, AppColors.secondary),
                        const SizedBox(width: 12),
                        _statCard('Pending', '$pendingCount', Icons.hourglass_top, Colors.orange),
                      ],
                    ),
                    const SizedBox(height: 12),
                    // Set Store Location button
                    GestureDetector(
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => const VendorLocationScreen()),
                        );
                      },
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFF0D2137), Color(0xFF1565C0)],
                          ),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 40, height: 40,
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.15),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Icon(Icons.map, color: Colors.white, size: 22),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('Set Store Location', style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.white)),
                                  Text('Pin your shop on the map for customers', style: GoogleFonts.poppins(fontSize: 11, color: Colors.white70)),
                                ],
                              ),
                            ),
                            const Icon(Icons.arrow_forward_ios, color: Colors.white54, size: 16),
                          ],
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),

        // Section title
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('My Products', style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w600)),
                TextButton(
                  onPressed: () => context.read<VendorProductBloc>().add(FetchVendorProducts()),
                  child: const Text('Refresh'),
                ),
              ],
            ),
          ),
        ),

        // Product grid
        BlocConsumer<VendorProductBloc, VendorProductState>(
          listener: (context, state) {
            if (state is VendorProductActionSuccess) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(state.message), backgroundColor: AppColors.success, behavior: SnackBarBehavior.floating),
              );
            }
            if (state is VendorProductError) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(state.message), backgroundColor: AppColors.error, behavior: SnackBarBehavior.floating),
              );
            }
          },
          builder: (context, state) {
            if (state is VendorProductLoading) {
              return const SliverFillRemaining(child: LoadingShimmer());
            }

            if (state is VendorProductLoaded) {
              if (state.products.isEmpty) {
                return SliverFillRemaining(
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.inventory_2_outlined, size: 64, color: Colors.grey.shade300),
                        const SizedBox(height: 16),
                        Text('No products yet', style: GoogleFonts.poppins(color: AppColors.textSecondary)),
                        const SizedBox(height: 8),
                        Text('Tap + Add Product to get started', style: GoogleFonts.poppins(fontSize: 13, color: AppColors.textLight)),
                      ],
                    ),
                  ),
                );
              }

              return SliverPadding(
                padding: const EdgeInsets.all(16),
                sliver: SliverGrid(
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    childAspectRatio: 0.72,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                  ),
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      final product = state.products[index];
                      return ProductCard(
                        product: product,
                        showVendorStock: true,
                        onTap: () => Navigator.pushNamed(context, AppRoutes.editProduct, arguments: product),
                      );
                    },
                    childCount: state.products.length,
                  ),
                ),
              );
            }

            return const SliverToBoxAdapter(child: SizedBox());
          },
        ),

        const SliverToBoxAdapter(child: SizedBox(height: 80)),
      ],
    );
  }

  Widget _statCard(String title, String value, IconData icon, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8)],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(child: Text(title, style: GoogleFonts.poppins(fontSize: 12, color: AppColors.textSecondary))),
                Icon(icon, color: color, size: 22),
              ],
            ),
            const SizedBox(height: 8),
            Text(value, style: GoogleFonts.poppins(fontSize: 24, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
          ],
        ),
      ),
    );
  }
}
