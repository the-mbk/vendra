// ══════════════════════════════════════════════════════════════
// Vendra App - Cart Screen
// Delivery method, synced saved address/map location, checkout
// - Delivery needs a map pin: the rider can only complete the delivery
//   inside the geofence around it (FR04), so checkout sends lat/lng
// - Delivery fee comes from GET /api/public-config (admin policy)
// - Live stock (FR01) flags lines the store can no longer fill
// - 409 INSUFFICIENT_STOCK / 400 INSUFFICIENT_BALANCE explained clearly
// ══════════════════════════════════════════════════════════════

import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:latlong2/latlong.dart';

import 'package:vendra_customer/vendra_core.dart';
import '../../../config/app_routes.dart';
import '../../../core/models/cart_item_model.dart';
import '../../../core/services/customer_location_storage.dart';
import '../../../core/services/public_config_service.dart';
import '../bloc/cart_bloc.dart';
import '../bloc/checkout_bloc.dart';
import '../bloc/order_bloc.dart';
import '../../auth/bloc/auth_bloc.dart';
import '../../auth/bloc/auth_event.dart';
import '../../auth/bloc/auth_state.dart';

class CartScreen extends StatefulWidget {
  const CartScreen({super.key});

  @override
  State<CartScreen> createState() => _CartScreenState();
}

class _CartScreenState extends State<CartScreen> {
  final _checkoutBloc = CheckoutBloc();

  String _deliveryType = 'delivery';
  final _addressController = TextEditingController();
  final _labelController = TextEditingController();

  double _customerLat = CustomerLocationStorage.defaultLat;
  double _customerLng = CustomerLocationStorage.defaultLng;
  bool _hasPin = false;
  bool _prefsLoaded = false;

  PublicConfig? _config;
  bool _configFailed = false;

  bool get _isDelivery => _deliveryType == 'delivery';

  @override
  void initState() {
    super.initState();
    _loadSavedDeliveryPrefs();
    _loadConfig();
  }

  Future<void> _loadConfig() async {
    try {
      final config = await PublicConfigService.load();
      if (mounted) setState(() => _config = config);
    } catch (_) {
      if (mounted) setState(() => _configFailed = true);
    }
  }

  Future<void> _loadSavedDeliveryPrefs() async {
    final snap = await CustomerLocationStorage.loadSnapshot();
    if (!mounted) return;
    setState(() {
      _customerLat = snap.lat;
      _customerLng = snap.lng;
      _hasPin = snap.hasPin;
      _labelController.text = snap.locationLabel;
      _addressController.text = snap.defaultAddressText;
      _prefsLoaded = true;
    });
  }

  Future<void> _persistDeliveryPrefs() async {
    await CustomerLocationStorage.save(
      latitude: _customerLat,
      longitude: _customerLng,
      locationName: _labelController.text.trim().isNotEmpty ? _labelController.text.trim() : CustomerLocationStorage.defaultName,
      addressLine: _addressController.text.trim().isNotEmpty ? _addressController.text.trim() : null,
    );
  }

  @override
  void dispose() {
    _addressController.dispose();
    _labelController.dispose();
    _checkoutBloc.close();
    super.dispose();
  }

  double _haversineKm(double lat1, double lon1, double lat2, double lon2) {
    const r = 6371.0;
    final dLat = (lat2 - lat1) * pi / 180;
    final dLon = (lon2 - lon1) * pi / 180;
    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(lat1 * pi / 180) * cos(lat2 * pi / 180) * sin(dLon / 2) * sin(dLon / 2);
    return r * 2 * atan2(sqrt(a), sqrt(1 - a));
  }

  String? _deliveryDistanceSubtitle(List<CartItemModel>? items) {
    if (!_isDelivery || !_hasPin || items == null || items.isEmpty) return null;
    final vLat = items.first.product.vendorLat;
    final vLng = items.first.product.vendorLng;
    if (vLat == null || vLng == null) return null;
    final km = _haversineKm(_customerLat, _customerLng, vLat, vLng);
    if (km < 1) return '~${(km * 1000).round()} m from the store';
    return '~${km.toStringAsFixed(1)} km from the store';
  }

  int get _geofence => _config?.geofenceMeters ?? 200;

  void _snack(String message, {bool error = false, SnackBarAction? action}) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(message),
        backgroundColor: error ? AppColors.error : null,
        behavior: SnackBarBehavior.floating,
        duration: Duration(seconds: action != null ? 6 : 4),
        action: action,
      ));
  }

  void _openEditDeliverySheet() {
    LatLng picked = LatLng(_customerLat, _customerLng);
    final addrCtl = TextEditingController(text: _addressController.text);
    final labCtl = TextEditingController(text: _labelController.text);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            return Padding(
              padding: EdgeInsets.only(
                left: 20,
                right: 20,
                top: 20,
                bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
              ),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('Delivery location', style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 8),
                    Text(
                      'Tap the map exactly where the rider should hand over your order. '
                      'The rider can only mark it delivered within $_geofence m of this pin.',
                      style: GoogleFonts.poppins(fontSize: 12, color: AppColors.textSecondary),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: labCtl,
                      decoration: InputDecoration(
                        labelText: 'Label e.g. Home, Office',
                        filled: true,
                        fillColor: Colors.grey.shade50,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      style: GoogleFonts.poppins(fontSize: 13),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: addrCtl,
                      decoration: InputDecoration(
                        labelText: 'Street / building details',
                        filled: true,
                        fillColor: Colors.grey.shade50,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      style: GoogleFonts.poppins(fontSize: 13),
                      maxLines: 2,
                    ),
                    const SizedBox(height: 12),
                    MapPickerWidget(
                      initialCenter: picked,
                      initialZoom: 14,
                      interactive: true,
                      height: 220,
                      onLocationSelected: (latLng) => setModalState(() => picked = latLng),
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () async {
                          setState(() {
                            _customerLat = picked.latitude;
                            _customerLng = picked.longitude;
                            _hasPin = true;
                            _addressController.text = addrCtl.text.trim();
                            _labelController.text = labCtl.text.trim();
                          });
                          await _persistDeliveryPrefs();
                          if (ctx.mounted) Navigator.pop(ctx);
                          if (mounted) _snack('Delivery pin saved');
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        child: Text('Use this pin', style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
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

  /// null while the fee is loading (or failed to load)
  double? get _deliveryFee => _isDelivery ? _config?.deliveryFee : 0;

  String _money(double v) => 'Rs. ${v.toStringAsFixed(0)}';

  Future<void> _placeOrder(CartState cartState) async {
    if (cartState.hasStockProblems) {
      _snack('Some items no longer have enough stock. Lower the highlighted quantities first.', error: true);
      return;
    }
    if (_isDelivery && !_hasPin) {
      _snack('Drop a pin on the map so the rider knows where to deliver.', error: true);
      _openEditDeliverySheet();
      return;
    }
    if (_isDelivery) await _persistDeliveryPrefs();
    if (!mounted) return;

    final addr = _isDelivery
        ? (_addressController.text.trim().isNotEmpty ? _addressController.text.trim() : _labelController.text.trim())
        : null;
    _checkoutBloc.add(CheckoutRequested(
      items: cartState.items,
      deliveryType: _deliveryType,
      deliveryAddress: addr,
      customerLat: _isDelivery ? _customerLat : null,
      customerLng: _isDelivery ? _customerLng : null,
    ));
  }

  void _onCheckoutState(BuildContext context, CheckoutState state) {
    if (state is CheckoutSuccess) {
      if (state.walletBalance != null) {
        context.read<AuthBloc>().add(AuthWalletBalanceUpdated(walletBalance: state.walletBalance!));
      }
      context.read<OrderBloc>().add(const FetchCustomerOrders(silent: true));
      context.read<CartBloc>().add(ClearCart());
      Navigator.pushReplacementNamed(context, AppRoutes.orderConfirmation, arguments: state.order);
    } else if (state is CheckoutFailure) {
      if (state.isStockProblem && state.productId != null) {
        // Someone else bought it first — reflect the real stock in the cart
        context.read<CartBloc>().add(
              CartStockChanged(productId: state.productId!, publicStock: state.available ?? 0),
            );
        final left = state.available ?? 0;
        _snack(
          left > 0
              ? 'Stock changed: only $left left for one of your items. We updated your cart — adjust the quantity and try again.'
              : 'One of your items just sold out. Remove it from your cart to continue.',
          error: true,
        );
      } else if (state.isBalanceProblem) {
        _snack(
          state.message,
          error: true,
          action: SnackBarAction(
            label: 'TOP UP',
            textColor: Colors.white,
            onPressed: () => Navigator.pushNamed(context, AppRoutes.wallet),
          ),
        );
      } else {
        _snack(state.message, error: true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text('My Cart', style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
      ),
      body: BlocConsumer<CheckoutBloc, CheckoutState>(
        bloc: _checkoutBloc,
        listener: _onCheckoutState,
        builder: (context, checkoutState) {
          return BlocBuilder<CartBloc, CartState>(
            builder: (context, cartState) {
              if (cartState.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.shopping_cart_outlined, size: 80, color: Colors.grey.shade300),
                      const SizedBox(height: 16),
                      Text('Your cart is empty', style: GoogleFonts.poppins(fontSize: 18, color: AppColors.textSecondary)),
                      const SizedBox(height: 8),
                      Text('Browse products and add them to cart', style: GoogleFonts.poppins(fontSize: 13, color: AppColors.textLight)),
                    ],
                  ),
                );
              }

              return Column(
                children: [
                  Expanded(
                    child: !_prefsLoaded
                        ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
                        : ListView(
                            padding: const EdgeInsets.all(16),
                            children: [
                              if (cartState.hasStockProblems) _stockWarningBanner(),
                              ...cartState.items.map(_cartItemCard),
                              const SizedBox(height: 8),
                              _deliveryMethodCard(cartState),
                              const SizedBox(height: 8),
                              _escrowNotice(),
                            ],
                          ),
                  ),
                  _totalsPanel(cartState, checkoutState is CheckoutSubmitting),
                ],
              );
            },
          );
        },
      ),
    );
  }

  Widget _stockWarningBanner() {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.stockRed.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.stockRed.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.inventory_outlined, color: AppColors.stockRed),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Stock changed while you were shopping. Adjust the highlighted items to continue.',
              style: GoogleFonts.poppins(fontSize: 12, color: AppColors.stockRed),
            ),
          ),
        ],
      ),
    );
  }

  Widget _cartItemCard(CartItemModel item) {
    final problem = item.exceedsStock;
    final soldOut = item.available == 0;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: problem ? Border.all(color: AppColors.stockRed.withValues(alpha: 0.5)) : null,
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8)],
      ),
      child: Column(
        children: [
          Row(
            children: [
              SizedBox(
                width: 56,
                height: 56,
                child: ProductImage(
                  product: item.product,
                  iconSize: 24,
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.product.name,
                      style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w500),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    if (item.product.storeName != null)
                      Text(item.product.storeName!, style: GoogleFonts.poppins(fontSize: 11, color: AppColors.secondary)),
                    const SizedBox(height: 4),
                    Text(_money(item.product.price), style: GoogleFonts.poppins(fontSize: 13, color: AppColors.textSecondary)),
                  ],
                ),
              ),
              Row(
                children: [
                  _qtyButton(Icons.remove, () {
                    context.read<CartBloc>().add(
                          UpdateCartQuantity(productId: item.product.id, quantity: item.quantity - 1),
                        );
                  }),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    child: Text('${item.quantity}', style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w600)),
                  ),
                  _qtyButton(
                    Icons.add,
                    item.quantity >= item.available
                        ? null
                        : () => context.read<CartBloc>().add(
                              UpdateCartQuantity(productId: item.product.id, quantity: item.quantity + 1),
                            ),
                  ),
                ],
              ),
              const SizedBox(width: 16),
              Text(_money(item.total), style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w600)),
            ],
          ),
          if (problem) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Icon(soldOut ? Icons.remove_shopping_cart_outlined : Icons.warning_amber_rounded,
                    size: 16, color: AppColors.stockRed),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    soldOut ? 'Sold out right now' : 'Only ${item.available} left in stock',
                    style: GoogleFonts.poppins(fontSize: 12, color: AppColors.stockRed, fontWeight: FontWeight.w500),
                  ),
                ),
                TextButton(
                  onPressed: () => context.read<CartBloc>().add(soldOut
                      ? RemoveFromCart(productId: item.product.id)
                      : UpdateCartQuantity(productId: item.product.id, quantity: item.available)),
                  child: Text(soldOut ? 'Remove' : 'Set to ${item.available}'),
                ),
              ],
            ),
          ] else if (item.product.isLowStock) ...[
            const SizedBox(height: 6),
            Align(
              alignment: Alignment.centerLeft,
              child: Text('Only ${item.available} left',
                  style: GoogleFonts.poppins(fontSize: 11, color: AppColors.reservedAmber, fontWeight: FontWeight.w500)),
            ),
          ],
        ],
      ),
    );
  }

  Widget _deliveryMethodCard(CartState cartState) {
    final distanceSubtitle = _deliveryDistanceSubtitle(cartState.items);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Delivery method', style: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w600)),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _deliveryOption(
                  icon: Icons.delivery_dining,
                  label: 'Home Delivery',
                  subtitle: _config != null
                      ? 'A rider brings it to your pin • ${_money(_config!.deliveryFee)}'
                      : 'A rider brings it to your pin',
                  value: 'delivery',
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _deliveryOption(
                  icon: Icons.store,
                  label: 'Self Pickup',
                  subtitle: 'Collect at the store • free',
                  value: 'self_pickup',
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (_isDelivery) ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Deliver to', style: GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 13)),
                TextButton.icon(
                  onPressed: _openEditDeliverySheet,
                  icon: Icon(_hasPin ? Icons.edit_location_alt_outlined : Icons.add_location_alt_outlined, size: 18),
                  label: Text(_hasPin ? 'Change pin' : 'Set pin'),
                ),
              ],
            ),
            if (!_hasPin)
              _pinRequiredNotice()
            else ...[
              Text(
                _labelController.text.isNotEmpty ? _labelController.text : 'Saved location',
                style: GoogleFonts.poppins(fontSize: 12, color: AppColors.secondary),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _addressController,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  hintText: 'Street / flat / landmarks',
                  prefixIcon: const Icon(Icons.home_work_outlined, color: AppColors.secondary, size: 20),
                  filled: true,
                  fillColor: Colors.grey.shade50,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: Colors.grey.shade200),
                  ),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                ),
                style: GoogleFonts.poppins(fontSize: 13),
                maxLines: 3,
              ),
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: MapPickerWidget(
                  // Rebuild the preview when the pin moves
                  key: ValueKey('$_customerLat,$_customerLng'),
                  initialCenter: LatLng(_customerLat, _customerLng),
                  initialZoom: 15,
                  interactive: false,
                  height: 120,
                  markers: [
                    MapMarkerData(
                      position: LatLng(_customerLat, _customerLng),
                      label: _labelController.text.isNotEmpty ? _labelController.text : 'Drop-off',
                      icon: Icons.place,
                      color: AppColors.primary,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Text(
                [
                  if (distanceSubtitle != null) distanceSubtitle,
                  'Rider must be within $_geofence m of this pin to complete delivery',
                ].join(' • '),
                style: GoogleFonts.poppins(fontSize: 11, color: AppColors.textSecondary),
              ),
            ],
          ] else ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.teal.shade50,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.teal.shade100),
              ),
              child: Row(
                children: [
                  Icon(Icons.storefront_outlined, color: Colors.teal.shade800),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Collect your order at the store and confirm you received it in the app.',
                      style: GoogleFonts.poppins(fontSize: 11, color: Colors.teal.shade900),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _pinRequiredNotice() {
    return InkWell(
      onTap: _openEditDeliverySheet,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.primary.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.primary.withValues(alpha: 0.4)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.pin_drop_outlined, color: AppColors.primary),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Drop a pin to get delivery',
                      style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.primary)),
                  const SizedBox(height: 2),
                  Text(
                    'Riders navigate to this exact spot, and can only mark your order delivered '
                    'within $_geofence m of it — this protects your escrow payment.',
                    style: GoogleFonts.poppins(fontSize: 11, color: AppColors.textSecondary),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _escrowNotice() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF8E1),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.amber.shade200),
      ),
      child: Row(
        children: [
          Icon(Icons.account_balance, size: 22, color: Colors.amber.shade700),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Escrow Payment',
                  style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.amber.shade800),
                ),
                Text(
                  'The total moves from your wallet into escrow now. The store is paid only after '
                  '${_isDelivery ? 'the rider delivers' : 'you confirm pickup'} and the dispute window closes.',
                  style: GoogleFonts.poppins(fontSize: 11, color: Colors.amber.shade700),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _totalsPanel(CartState cartState, bool submitting) {
    final subtotal = cartState.totalAmount;
    final fee = _deliveryFee;
    final total = fee == null ? null : subtotal + fee;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 10, offset: const Offset(0, -4))],
      ),
      child: SafeArea(
        child: Column(
          children: [
            _totalRow('Subtotal', _money(subtotal)),
            const SizedBox(height: 4),
            _totalRow(
              _isDelivery ? 'Delivery fee' : 'Self pickup',
              !_isDelivery
                  ? 'Free'
                  : fee != null
                      ? _money(fee)
                      : (_configFailed ? 'Added at checkout' : '…'),
              valueColor: _isDelivery ? AppColors.textPrimary : Colors.green,
            ),
            const Divider(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Total (charged now)', style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.w700)),
                Text(
                  total != null ? _money(total) : '${_money(subtotal)} + fee',
                  style: GoogleFonts.poppins(fontSize: 20, fontWeight: FontWeight.w700, color: AppColors.primary),
                ),
              ],
            ),
            BlocBuilder<AuthBloc, AuthState>(
              builder: (context, auth) {
                if (auth is! Authenticated) return const SizedBox(height: 12);
                final balance = auth.user.walletBalance;
                final short = total != null && balance < total;
                return InkWell(
                  onTap: () => Navigator.pushNamed(context, AppRoutes.wallet),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Row(
                      children: [
                        Icon(Icons.account_balance_wallet_outlined,
                            size: 16, color: short ? AppColors.error : AppColors.textSecondary),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            short
                                ? 'Wallet has ${_money(balance)} — top up ${_money(total - balance)} more'
                                : 'Paid from wallet · ${_money(balance)} available',
                            style: GoogleFonts.poppins(fontSize: 12, color: short ? AppColors.error : AppColors.textSecondary),
                          ),
                        ),
                        Text(short ? 'Top up' : 'View',
                            style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.secondary)),
                      ],
                    ),
                  ),
                );
              },
            ),
            VendraButton(
              text: _isDelivery && !_hasPin ? 'Set delivery pin' : 'Place Order',
              icon: _isDelivery && !_hasPin ? Icons.pin_drop_outlined : Icons.arrow_forward,
              isLoading: submitting,
              onPressed: () => _placeOrder(cartState),
            ),
          ],
        ),
      ),
    );
  }

  Widget _totalRow(String label, String value, {Color valueColor = AppColors.textPrimary}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: GoogleFonts.poppins(fontSize: 14, color: AppColors.textSecondary)),
        Text(value, style: GoogleFonts.poppins(fontSize: 14, color: valueColor)),
      ],
    );
  }

  Widget _deliveryOption({
    required IconData icon,
    required String label,
    required String subtitle,
    required String value,
  }) {
    final isSelected = _deliveryType == value;
    return GestureDetector(
      onTap: () => setState(() => _deliveryType = value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primary.withValues(alpha: 0.08) : Colors.grey.shade50,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? AppColors.primary : Colors.grey.shade200,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Column(
          children: [
            Icon(icon, size: 28, color: isSelected ? AppColors.primary : AppColors.textSecondary),
            const SizedBox(height: 6),
            Text(
              label,
              style: GoogleFonts.poppins(
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                color: isSelected ? AppColors.primary : AppColors.textPrimary,
              ),
            ),
            Text(
              subtitle,
              style: GoogleFonts.poppins(fontSize: 9, color: AppColors.textSecondary),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _qtyButton(IconData icon, VoidCallback? onTap) {
    final enabled = onTap != null;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 30,
        height: 30,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: enabled ? Colors.grey.shade300 : Colors.grey.shade200),
        ),
        child: Icon(icon, size: 16, color: enabled ? AppColors.textPrimary : AppColors.textLight),
      ),
    );
  }
}
