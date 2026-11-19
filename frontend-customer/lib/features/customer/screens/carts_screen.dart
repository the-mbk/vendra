// ══════════════════════════════════════════════════════════════
// Vendra App - My Carts
// One cart per store (every order comes from one store). Lists each
// store's cart with its total and whether the store delivers to the
// customer's pin; opening one goes to that store's CartScreen.
// With a single cart it opens that cart straight away.
// A short card on top explains why: each shop sends its own rider
// (hyperlocal delivery, SRDS §1.1 / §2.2), so carts check out per store.
// ══════════════════════════════════════════════════════════════


import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:vendra_customer/vendra_core.dart';
import '../../../core/services/customer_location_storage.dart';
import '../bloc/cart_bloc.dart';
import '../widgets/store_widgets.dart' show haversineKm;
import 'cart_screen.dart';

class CartsScreen extends StatefulWidget {
  const CartsScreen({super.key});

  @override
  State<CartsScreen> createState() => _CartsScreenState();
}

class _CartsScreenState extends State<CartsScreen> {
  double? _pinLat;
  double? _pinLng;

  @override
  void initState() {
    super.initState();
    _loadPin();
    final stores = context.read<CartBloc>().state.stores;
    if (stores.length == 1) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => CartScreen(vendorId: stores.first.vendorId)),
        );
      });
    }
  }

  Future<void> _loadPin() async {
    final snap = await CustomerLocationStorage.loadSnapshot();
    if (!mounted || !snap.hasPin) return;
    setState(() {
      _pinLat = snap.lat;
      _pinLng = snap.lng;
    });
  }

  double? _kmTo(StoreCart cart) {
    if (_pinLat == null || cart.storeLat == null || cart.storeLng == null) return null;
    return haversineKm(_pinLat!, _pinLng!, cart.storeLat!, cart.storeLng!);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: Text('My carts', style: GoogleFonts.poppins(fontWeight: FontWeight.w600))),
      body: BlocBuilder<CartBloc, CartState>(
        builder: (context, state) {
          final stores = state.stores;
          if (stores.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.shopping_cart_outlined, size: 80, color: AppColors.textLight),
                  const SizedBox(height: 16),
                  Text('Your carts are empty', style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    child: Text('Add products from any store; each store gets its own cart',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.poppins(fontSize: 13, color: AppColors.textSecondary)),
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton.icon(
                    onPressed: () => Navigator.pop(context),
                    style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14)),
                    icon: const Icon(Icons.storefront_outlined, size: 20),
                    label: const Text('Start shopping'),
                  ),
                ],
              ),
            );
          }
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const _HyperlocalInfoCard(),
              const SizedBox(height: 12),
              for (final cart in stores) _storeCartCard(cart),
            ],
          );
        },
      ),
    );
  }

  Widget _storeCartCard(StoreCart cart) {
    final km = _kmTo(cart);
    final config = AppConfig.current;
    final delivers = km == null || config.deliversAt(km);
    final names = cart.items.map((i) => '${i.quantity}× ${i.product.name}').join(', ');

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              StoreLogo(storeName: cart.storeName, logoUrl: cart.storeLogoUrl, size: 32),
              const SizedBox(width: 10),
              Expanded(
                child: Text(cart.storeName,
                    style: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis),
              ),
              IconButton(
                tooltip: 'Remove this cart',
                icon: const Icon(Icons.delete_outline, size: 20),
                onPressed: () => _confirmRemove(cart),
              ),
            ],
          ),
          Text(names, maxLines: 2, overflow: TextOverflow.ellipsis,
              style: GoogleFonts.poppins(fontSize: 12, color: AppColors.textSecondary)),
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(delivers ? Icons.delivery_dining : Icons.store, size: 16,
                  color: delivers ? AppColors.textSecondary : AppColors.warningInk),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  km == null
                      ? 'Set your pin at checkout to see delivery'
                      : delivers
                          ? '${km.toStringAsFixed(1)} km away · delivers to you'
                          : '${km.toStringAsFixed(1)} km away · self pickup only (delivery up to ${config.maxDeliveryKm.toStringAsFixed(0)} km)',
                  style: GoogleFonts.poppins(fontSize: 12, color: delivers ? AppColors.textSecondary : AppColors.warningInk),
                ),
              ),
            ],
          ),
          if (cart.hasStockProblems)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text('Some items no longer have enough stock',
                  style: GoogleFonts.poppins(fontSize: 12, color: AppColors.error)),
            ),
          const Divider(height: 20),
          Row(
            children: [
              Expanded(
                child: Text(
                  '${cart.totalItems} item${cart.totalItems == 1 ? '' : 's'} · ${formatRupees(cart.totalAmount)}',
                  style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
                ),
              ),
              ElevatedButton(
                onPressed: () => openStoreCart(context, cart.vendorId),
                style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, foregroundColor: Colors.white),
                child: const Text('Checkout'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _confirmRemove(StoreCart cart) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove this cart?'),
        content: Text('All ${cart.totalItems} item(s) from ${cart.storeName} will be removed.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Keep')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Remove')),
        ],
      ),
    );
    if (ok == true && mounted) context.read<CartBloc>().add(ClearStoreCart(vendorId: cart.vendorId));
  }
}

/// Why there is one cart per store: every shop dispatches its own rider
class _HyperlocalInfoCard extends StatelessWidget {
  const _HyperlocalInfoCard();

  @override
  Widget build(BuildContext context) {
    final accent = AppColors.secondary;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: AppColors.isDark ? 0.15 : 0.04),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.hairline),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Route glyph: shop → rider
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: accent.withValues(alpha: 0.25)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.storefront_outlined, size: 18, color: accent),
                Icon(Icons.arrow_right_alt, size: 16, color: AppColors.textLight),
                const Icon(Icons.delivery_dining_outlined, size: 18, color: AppColors.primary),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Hyperlocal instant delivery',
                    style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                const SizedBox(height: 2),
                Text(
                  'Each shop dispatches its own rider to deliver fresh items within 25–35 minutes. '
                  'Checkout and delivery tracking happen per store.',
                  style: GoogleFonts.poppins(fontSize: 12, height: 1.4, color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
