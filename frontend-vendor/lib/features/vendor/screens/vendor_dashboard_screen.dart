// ══════════════════════════════════════════════════════════════
// Vendra App - Vendor Dashboard Screen
// Adapted from Stitch vendor_dashboard_web design for mobile
// Uses BottomNavigationBar with 5 tabs: Home · POS · Orders · Ledger · Profile
// Stock numbers on this screen are live (see VendorProductBloc).
// ══════════════════════════════════════════════════════════════

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:vendra_vendor/vendra_core.dart';
import '../../../config/app_routes.dart';
import '../../auth/bloc/auth_bloc.dart';
import '../../auth/bloc/auth_event.dart';
import '../../auth/bloc/auth_state.dart' as auth_state;
import '../bloc/pos_bloc.dart';
import '../bloc/vendor_product_bloc.dart';
import '../bloc/vendor_order_bloc.dart';
import '../bloc/store_location_bloc.dart';
import 'pos_screen.dart';
import 'vendor_orders_screen.dart';
import 'stock_ledger_screen.dart';
import 'vendor_profile_screen.dart';
import 'vendor_disputes_screen.dart';
import 'wallet_screen.dart';
import '../widgets/wallet_widgets.dart';

import 'vendor_location_screen.dart';

final NumberFormat _money = NumberFormat('#,##0');

/// Greeting that matches the time of day
String _greeting() {
  final h = DateTime.now().hour;
  if (h < 12) return 'Good morning';
  if (h < 17) return 'Good afternoon';
  return 'Good evening';
}

class VendorDashboardScreen extends StatefulWidget {
  const VendorDashboardScreen({super.key});

  @override
  State<VendorDashboardScreen> createState() => _VendorDashboardScreenState();
}

class _VendorDashboardScreenState extends State<VendorDashboardScreen> {
  // Tab indexes
  static const int _homeTab = 0;
  static const int _posTab = 1;
  static const int _ordersTab = 2;
  static const int _ledgerTab = 3;
  static const int _profileTab = 4;

  int _currentIndex = _homeTab;
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  StreamSubscription<OrderUpdateEvent>? _escrowSub;
  StreamSubscription<NotificationModel>? _walletNotifSub;

  @override
  void initState() {
    super.initState();
    context.read<VendorProductBloc>().add(const FetchVendorProducts());
    context.read<VendorOrderBloc>().add(const FetchVendorOrders());
    context.read<StoreLocationBloc>().add(const StoreLocationRequested());
    // Escrow released to the store → refresh the wallet chip
    _escrowSub = RealtimeService().orderUpdates.listen((e) {
      if (e.escrowStatus == 'released' && mounted) context.read<AuthBloc>().add(RefreshUserRequested());
    });
    // A bounced withdrawal puts the money back → refresh the balance
    _walletNotifSub = RealtimeService().notifications.listen((n) {
      if (isWalletNotification(n.type) && mounted) context.read<AuthBloc>().add(RefreshUserRequested());
      // An admin approved / rejected a store location change → refresh the location card
      if ((n.type == 'location_approved' || n.type == 'location_rejected') && mounted) {
        context.read<StoreLocationBloc>().add(const StoreLocationRequested());
        context.read<AuthBloc>().add(RefreshUserRequested());
      }
    });
  }

  @override
  void dispose() {
    _escrowSub?.cancel();
    _walletNotifSub?.cancel();
    super.dispose();
  }

  void _goToTab(int index) => setState(() => _currentIndex = index);

  void _openWallet() => Navigator.push(context, MaterialPageRoute(builder: (_) => const WalletScreen()));

  void _openDisputes() => Navigator.push(context, MaterialPageRoute(builder: (_) => const VendorDisputesScreen()));

  /// Opens the map on the live store location, then re-reads /me so the
  /// location card shows a pending request (or the applied move)
  Future<void> _openLocation() async {
    final live = context.read<StoreLocationBloc>().state.status;
    final auth = context.read<AuthBloc>().state;
    final user = auth is auth_state.Authenticated ? auth.user : null;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => VendorLocationScreen(
          currentLat: live?.latitude ?? user?.storeLat,
          currentLng: live?.longitude ?? user?.storeLng,
        ),
      ),
    );
    if (!mounted) return;
    context.read<StoreLocationBloc>().add(const StoreLocationRequested());
    context.read<AuthBloc>().add(RefreshUserRequested());
  }

  Widget _drawerItem(IconData icon, String title, VoidCallback onTap, {int? tab}) {
    final selected = tab != null && tab == _currentIndex;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
      child: ListTile(
        selected: selected,
        selectedTileColor: AppColors.primary.withValues(alpha: 0.08),
        selectedColor: AppColors.primary,
        iconColor: AppColors.textSecondary,
        textColor: AppColors.textPrimary,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        leading: Icon(icon, size: 22),
        title: Text(title,
            style: GoogleFonts.poppins(fontSize: 14, fontWeight: selected ? FontWeight.w600 : FontWeight.w500)),
        onTap: () {
          Navigator.pop(context);
          onTap();
        },
      ),
    );
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
              Container(
                padding: const EdgeInsets.fromLTRB(20, 28, 20, 20),
                margin: const EdgeInsets.only(bottom: 8),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(colors: [Color(0xFF0D2137), Color(0xFF1565C0)]),
                ),
                child: BlocBuilder<AuthBloc, auth_state.AuthState>(
                  builder: (context, state) {
                    final user = state is auth_state.Authenticated ? state.user : null;
                    return Row(
                      children: [
                        Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(Icons.storefront, color: Colors.white, size: 26),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(user?.storeName ?? 'Vendor Panel',
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: GoogleFonts.poppins(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w700)),
                              Text(user?.fullName ?? 'Manage store & orders',
                                  overflow: TextOverflow.ellipsis,
                                  style: GoogleFonts.poppins(color: Colors.white70, fontSize: 12)),
                            ],
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
              _drawerItem(Icons.dashboard_outlined, 'Home', () => _goToTab(_homeTab), tab: _homeTab),
              _drawerItem(Icons.point_of_sale, 'Walk-in POS', () => _goToTab(_posTab), tab: _posTab),
              _drawerItem(Icons.receipt_long_outlined, 'Orders', () => _goToTab(_ordersTab), tab: _ordersTab),
              _drawerItem(Icons.inventory_2_outlined, 'Stock ledger', () => _goToTab(_ledgerTab), tab: _ledgerTab),
              _drawerItem(Icons.person_outline, 'Profile', () => _goToTab(_profileTab), tab: _profileTab),
              const Divider(indent: 16, endIndent: 16, height: 24),
              _drawerItem(Icons.account_balance_wallet_outlined, 'Wallet', _openWallet),
              _drawerItem(Icons.gavel_outlined, 'Disputes', _openDisputes),
              _drawerItem(Icons.map_outlined, 'Store location', _openLocation),
              _drawerItem(Icons.add_circle_outline, 'Add product', () => Navigator.pushNamed(context, AppRoutes.addProduct)),
            ],
          ),
        ),
      ),
      body: IndexedStack(
        index: _currentIndex,
        children: [
          _buildHomeTab(),
          const PosScreen(),
          const VendorOrdersScreen(),
          const StockLedgerScreen(),
          const VendorProfileScreen(),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: _goToTab,
        items: [
          const BottomNavigationBarItem(icon: Icon(Icons.dashboard_outlined), activeIcon: Icon(Icons.dashboard), label: 'Home'),
          const BottomNavigationBarItem(icon: Icon(Icons.point_of_sale_outlined), activeIcon: Icon(Icons.point_of_sale), label: 'POS'),
          BottomNavigationBarItem(
            icon: _ordersIcon(Icons.receipt_long_outlined),
            activeIcon: _ordersIcon(Icons.receipt_long),
            label: 'Orders',
          ),
          const BottomNavigationBarItem(icon: Icon(Icons.inventory_2_outlined), activeIcon: Icon(Icons.inventory_2), label: 'Ledger'),
          const BottomNavigationBarItem(icon: Icon(Icons.person_outline), activeIcon: Icon(Icons.person), label: 'Profile'),
        ],
      ),
      floatingActionButton: _currentIndex == _homeTab
          ? FloatingActionButton.extended(
              onPressed: () => Navigator.pushNamed(context, AppRoutes.addProduct),
              icon: const Icon(Icons.add),
              label: const Text('Add Product'),
            )
          : null,
    );
  }

  /// Home card that opens the location screen; shows a change waiting for the admin
  /// and the reason the last one was rejected
  Widget _locationCard() {
    return BlocBuilder<StoreLocationBloc, StoreLocationState>(
      builder: (context, state) {
        final status = state.status;
        final pending = status?.pending;
        final rejection = pending == null ? status?.rejectionReason : null;

        final String title;
        final String subtitle;
        final IconData icon;
        final List<Color> colors;
        if (pending != null) {
          final when = pending.requestedAt != null ? DateFormat('MMM dd').format(pending.requestedAt!) : 'recently';
          title = 'Location change pending approval';
          subtitle = 'Requested $when · customers still see your current location';
          icon = Icons.hourglass_top;
          colors = const [Color(0xFF8A6D00), AppColors.reservedAmber];
        } else {
          title = 'Set Store Location';
          subtitle = 'Pin your shop on the map for customers';
          icon = Icons.map;
          colors = const [Color(0xFF0D2137), Color(0xFF1565C0)];
        }

        return GestureDetector(
          onTap: _openLocation,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: colors),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                Container(
                  width: 40, height: 40,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, color: Colors.white, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.white)),
                      Text(subtitle, style: GoogleFonts.poppins(fontSize: 11, color: Colors.white70)),
                      if (rejection != null) ...[
                        const SizedBox(height: 4),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(Icons.warning_amber_rounded, size: 14, color: Colors.red.shade100),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                'Last change rejected: $rejection',
                                style: GoogleFonts.poppins(fontSize: 11, fontWeight: FontWeight.w500, color: Colors.red.shade100),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                const Icon(Icons.arrow_forward_ios, color: Colors.white54, size: 16),
              ],
            ),
          ),
        );
      },
    );
  }

  /// Orders tab icon with a badge for orders waiting for approval
  Widget _ordersIcon(IconData icon) {
    return BlocBuilder<VendorOrderBloc, VendorOrderState>(
      builder: (context, _) {
        final pending = context.read<VendorOrderBloc>().activeOrders.where((o) => o.status == 'pending').length;
        return Badge(
          isLabelVisible: pending > 0,
          label: Text('$pending'),
          backgroundColor: AppColors.primary,
          child: Icon(icon),
        );
      },
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
                  Text(_greeting(),
                      style: GoogleFonts.poppins(fontSize: 12, color: AppColors.textSecondary, fontWeight: FontWeight.w400)),
                  Text(storeName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.poppins(fontSize: 17, fontWeight: FontWeight.w700, color: AppColors.secondary)),
                ],
              );
            },
          ),
          actions: [
            BlocBuilder<AuthBloc, auth_state.AuthState>(
              builder: (context, state) {
                if (state is auth_state.Authenticated) {
                  return IconButton(
                    tooltip: 'Wallet · Rs. ${_money.format(state.user.walletBalance)}',
                    onPressed: _openWallet,
                    icon: Icon(Icons.account_balance_wallet_outlined, color: Colors.green.shade700),
                  );
                }
                return const SizedBox.shrink();
              },
            ),
            // FR09: live inbox; order notifications open the Orders tab
            NotificationBell(
              color: AppColors.textPrimary,
              onOpenOrder: (ctx, orderId) {
                Navigator.of(ctx).pop();
                context.read<VendorOrderBloc>().add(RefreshVendorOrder(orderId));
                _goToTab(_ordersTab);
              },
            ),
            const SizedBox(width: 8),
          ],
        ),

        // Stats cards
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Builder(
              builder: (context) {
                // Every in-progress order (scope=active is not paged, so the counts are exact)
                final activeOrders = context.watch<VendorOrderBloc>().activeOrders;
                final products = context.watch<VendorProductBloc>().products;
                final pos = context.watch<PosBloc>().state;
                final activeCount = activeOrders.length;
                final pendingCount = activeOrders.where((o) => o.status == 'pending').length;
                final reservedUnits = products.fold<int>(0, (sum, p) => sum + p.reservedQuantity);
                final awaitingApproval = products.where((p) => !p.isApproved).length;

                return Column(
                  children: [
                    Row(
                      children: [
                        _statCard('Active Orders', '$activeCount', Icons.shopping_bag_outlined, AppColors.secondary,
                            onTap: () => _goToTab(_ordersTab)),
                        const SizedBox(width: 12),
                        _statCard('Pending', '$pendingCount', Icons.hourglass_top, Colors.orange,
                            onTap: () => _goToTab(_ordersTab)),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        _statCard(
                          'Walk-in Today',
                          'Rs. ${_money.format(pos.todayTotal)}',
                          Icons.point_of_sale,
                          AppColors.primary,
                          subtitle: '${pos.todayCount} sale${pos.todayCount == 1 ? '' : 's'} · open POS',
                          onTap: () => _goToTab(_posTab),
                        ),
                        const SizedBox(width: 12),
                        _statCard('Reserved Units', '$reservedUnits', Icons.lock_outline, AppColors.reservedAmber,
                            subtitle: 'Locked by online orders'),
                      ],
                    ),
                    const SizedBox(height: 12),
                    _walletCard(),
                    if (awaitingApproval > 0) ...[
                      const SizedBox(height: 12),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppColors.warning.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppColors.warning),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.hourglass_top, size: 18, color: Color(0xFF8A6D00)),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                '$awaitingApproval product${awaitingApproval == 1 ? ' is' : 's are'} awaiting admin approval '
                                '— hidden from customers until approved.',
                                style: GoogleFonts.poppins(
                                    fontSize: 12, fontWeight: FontWeight.w600, color: const Color(0xFF8A6D00)),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    // Set Store Location button (shows a change waiting for admin approval)
                    _locationCard(),
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
                Text('My Products',
                    style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                TextButton.icon(
                  onPressed: () => context.read<VendorProductBloc>().add(const FetchVendorProducts(silent: true)),
                  icon: const Icon(Icons.refresh, size: 18),
                  label: const Text('Refresh'),
                ),
              ],
            ),
          ),
        ),

        // Product grid (live stock)
        BlocConsumer<VendorProductBloc, VendorProductState>(
          listener: (context, state) {
            // The add/edit screen reports its own results while it is on top
            if (ModalRoute.of(context)?.isCurrent != true) return;
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
            final bloc = context.read<VendorProductBloc>();
            if (!bloc.hasLoaded) {
              if (state is VendorProductError) {
                return SliverFillRemaining(child: Center(child: Text(state.message)));
              }
              return const SliverFillRemaining(child: LoadingShimmer());
            }

            final products = bloc.products;
            if (products.isEmpty) {
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
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 240,
                  childAspectRatio: 0.72,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                ),
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    final product = products[index];
                    return Stack(
                      children: [
                        Positioned.fill(
                          child: ProductCard(
                            product: product,
                            showVendorStock: true,
                            onTap: () => Navigator.pushNamed(context, AppRoutes.editProduct, arguments: product),
                          ),
                        ),
                        if (!product.isApproved)
                          // Below the card's own stock badge so both fit on narrow phones
                          const Positioned(top: 40, left: 12, child: _AwaitingApprovalBadge()),
                      ],
                    );
                  },
                  childCount: products.length,
                ),
              ),
            );
          },
        ),

        const SliverToBoxAdapter(child: SizedBox(height: 80)),
      ],
    );
  }

  /// Wallet balance (escrow releases) with a Withdraw shortcut; tap opens the wallet
  Widget _walletCard() {
    return BlocBuilder<AuthBloc, auth_state.AuthState>(
      builder: (context, state) {
        if (state is! auth_state.Authenticated) return const SizedBox.shrink();
        final balance = state.user.walletBalance;
        return Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8)],
          ),
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: _openWallet,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
                child: Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(color: Colors.green.shade50, borderRadius: BorderRadius.circular(10)),
                      child: Icon(Icons.account_balance_wallet, color: Colors.green.shade700, size: 22),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Wallet balance', style: GoogleFonts.poppins(fontSize: 12, color: AppColors.textSecondary)),
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: Text('Rs. ${_money.format(balance)}',
                                style: GoogleFonts.poppins(
                                    fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                          ),
                        ],
                      ),
                    ),
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.secondary,
                        side: const BorderSide(color: AppColors.secondary),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      icon: const Icon(Icons.north_east, size: 18),
                      label: Text('Withdraw', style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w600)),
                      onPressed: () => startWithdrawal(context, balance: balance),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _statCard(String title, String value, IconData icon, Color color, {VoidCallback? onTap, String? subtitle}) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8)],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(title,
                        style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w500, color: AppColors.textSecondary)),
                  ),
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
                    child: Icon(icon, color: color, size: 18),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(value,
                    style: GoogleFonts.poppins(fontSize: 24, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
              ),
              if (subtitle != null)
                Text(subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.poppins(fontSize: 10, color: AppColors.textLight)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Shown on products an admin hasn't approved yet (hidden from customers)
class _AwaitingApprovalBadge extends StatelessWidget {
  const _AwaitingApprovalBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.warning,
        borderRadius: BorderRadius.circular(6),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.15), blurRadius: 4)],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.hourglass_top, size: 12, color: Color(0xFF5C4800)),
          const SizedBox(width: 4),
          Text('Awaiting approval',
              style: GoogleFonts.poppins(fontSize: 10, fontWeight: FontWeight.w700, color: const Color(0xFF5C4800))),
        ],
      ),
    );
  }
}
