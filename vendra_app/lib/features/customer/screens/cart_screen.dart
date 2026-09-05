// ══════════════════════════════════════════════════════════════
// Vendra App - Cart Screen
// Delivery method, synced saved address/map location, checkout
// ══════════════════════════════════════════════════════════════

import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:latlong2/latlong.dart';

import '../../../config/app_theme.dart';
import '../../../config/app_routes.dart';
import '../../../core/constants/app_checkout.dart';
import '../../../core/models/cart_item_model.dart';
import '../../../core/widgets/map_picker_widget.dart';
import '../../../core/widgets/vendra_button.dart';
import '../../../core/services/customer_location_storage.dart';
import '../bloc/cart_bloc.dart';
import '../bloc/order_bloc.dart';
import '../../auth/bloc/auth_bloc.dart';
import '../../auth/bloc/auth_event.dart';

class CartScreen extends StatefulWidget {
  const CartScreen({super.key});

  @override
  State<CartScreen> createState() => _CartScreenState();
}

class _CartScreenState extends State<CartScreen> {
  String _deliveryType = 'delivery';
  final _addressController = TextEditingController();
  final _labelController = TextEditingController();

  double _customerLat = CustomerLocationStorage.defaultLat;
  double _customerLng = CustomerLocationStorage.defaultLng;
  bool _prefsLoaded = false;

  @override
  void initState() {
    super.initState();
    _loadSavedDeliveryPrefs();
  }

  Future<void> _loadSavedDeliveryPrefs() async {
    final snap = await CustomerLocationStorage.loadSnapshot();
    if (!mounted) return;
    setState(() {
      _customerLat = snap.lat;
      _customerLng = snap.lng;
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
    if (_deliveryType != 'delivery' || items == null || items.isEmpty) return null;
    final vLat = items.first.product.vendorLat;
    final vLng = items.first.product.vendorLng;
    if (vLat == null || vLng == null) return null;
    final km = _haversineKm(_customerLat, _customerLng, vLat, vLng);
    if (km < 1) return '~${(km * 1000).round()} m from store • ETA uses this pin';
    return '~${km.toStringAsFixed(1)} km from store • ETA uses this pin';
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
                      'Pin matches your homepage selection by default. Update label or street details anytime.',
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
                      height: 200,
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
                            _addressController.text = addrCtl.text.trim();
                            _labelController.text = labCtl.text.trim();
                          });
                          await _persistDeliveryPrefs();
                          if (ctx.mounted) Navigator.pop(ctx);
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Delivery location saved'), behavior: SnackBarBehavior.floating),
                            );
                          }
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        child: Text('Save for checkout', style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
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

  double _grandTotal(double cartTotal) =>
      cartTotal + (_deliveryType == 'delivery' ? AppCheckout.deliveryFee : 0);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text('My Cart', style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
      ),
      body: BlocConsumer<OrderBloc, OrderState>(
        listener: (context, orderState) {
          if (orderState is OrderPlaced) {
            final nw = orderState.newWalletBalance;
            if (nw != null) {
              context.read<AuthBloc>().add(AuthWalletBalanceUpdated(walletBalance: nw));
            }
            context.read<AuthBloc>().add(CheckAuthRequested());
            context.read<CartBloc>().add(ClearCart());
            Navigator.pushReplacementNamed(
              context,
              AppRoutes.orderConfirmation,
              arguments: orderState.order,
            );
          } else if (orderState is OrderError) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(orderState.message), backgroundColor: AppColors.error, behavior: SnackBarBehavior.floating),
            );
          }
        },
        builder: (context, orderState) {
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

              final distanceSubtitle = _deliveryDistanceSubtitle(cartState.items);

              return Column(
                children: [
                  Expanded(
                    child: !_prefsLoaded
                        ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
                        : ListView(
                            padding: const EdgeInsets.all(16),
                            children: [
                              ...cartState.items.map((item) => Container(
                                    margin: const EdgeInsets.only(bottom: 12),
                                    padding: const EdgeInsets.all(16),
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(14),
                                      boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8)],
                                    ),
                                    child: Row(
                                      children: [
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
                                                Text(
                                                  item.product.storeName!,
                                                  style: GoogleFonts.poppins(fontSize: 11, color: AppColors.secondary),
                                                ),
                                              const SizedBox(height: 4),
                                              Text(
                                                'Rs. ${item.product.price.toStringAsFixed(0)}',
                                                style: GoogleFonts.poppins(fontSize: 13, color: AppColors.textSecondary),
                                              ),
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
                                              child:
                                                  Text('${item.quantity}', style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w600)),
                                            ),
                                            _qtyButton(Icons.add, () {
                                              context.read<CartBloc>().add(
                                                    UpdateCartQuantity(productId: item.product.id, quantity: item.quantity + 1),
                                                  );
                                            }),
                                          ],
                                        ),
                                        const SizedBox(width: 16),
                                        Text(
                                          'Rs. ${item.total.toStringAsFixed(0)}',
                                          style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w600),
                                        ),
                                      ],
                                    ),
                                  )),

                              const SizedBox(height: 8),

                              Container(
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(14),
                                  boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8)],
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
                                            subtitle: 'Rider phase pending — pays vendor later',
                                            value: 'delivery',
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: _deliveryOption(
                                            icon: Icons.store,
                                            label: 'Self Pickup',
                                            subtitle: 'Collect at store • full checkout flow',
                                            value: 'self_pickup',
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 16),
                                    if (_deliveryType == 'delivery') ...[
                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          Text('Deliver to', style: GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 13)),
                                          TextButton.icon(
                                            onPressed: _openEditDeliverySheet,
                                            icon: const Icon(Icons.edit_location_alt_outlined, size: 18),
                                            label: const Text('Change pin'),
                                          ),
                                        ],
                                      ),
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
                                          initialCenter: LatLng(_customerLat, _customerLng),
                                          initialZoom: 14,
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
                                      if (distanceSubtitle != null) ...[
                                        const SizedBox(height: 8),
                                        Text(distanceSubtitle, style: GoogleFonts.poppins(fontSize: 11, color: AppColors.textSecondary)),
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
                                                'You will confirm pickup at the store. Vendor is paid only after you mark the order delivered.',
                                                style: GoogleFonts.poppins(fontSize: 11, color: Colors.teal.shade900),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),

                              const SizedBox(height: 8),

                              Container(
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
                                            _deliveryType == 'self_pickup'
                                                ? 'Amount moves from your wallet into escrow immediately. Vendor is paid after you confirm pickup.'
                                                : 'Amount moves from your wallet into escrow. Vendor payout waits until rider delivery is enabled.',
                                            style: GoogleFonts.poppins(fontSize: 11, color: Colors.amber.shade700),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                  ),

                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                      boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 10, offset: const Offset(0, -4))],
                    ),
                    child: SafeArea(
                      child: Column(
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text('Subtotal', style: GoogleFonts.poppins(fontSize: 14, color: AppColors.textSecondary)),
                              Text('Rs. ${cartState.totalAmount.toStringAsFixed(0)}',
                                  style: GoogleFonts.poppins(fontSize: 14)),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                _deliveryType == 'delivery' ? 'Delivery fee (fixed)' : 'Pickup',
                                style: GoogleFonts.poppins(fontSize: 14, color: AppColors.textSecondary),
                              ),
                              Text(
                                _deliveryType == 'delivery' ? 'Rs. ${AppCheckout.deliveryFee.toStringAsFixed(0)}' : 'Free',
                                style: GoogleFonts.poppins(
                                  fontSize: 14,
                                  color: _deliveryType == 'self_pickup' ? Colors.green : AppColors.textPrimary,
                                ),
                              ),
                            ],
                          ),
                          const Divider(height: 16),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text('Total (charged now)', style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.w700)),
                              Text(
                                'Rs. ${_grandTotal(cartState.totalAmount).toStringAsFixed(0)}',
                                style: GoogleFonts.poppins(fontSize: 20, fontWeight: FontWeight.w700, color: AppColors.primary),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          VendraButton(
                            text: 'Place Order',
                            icon: Icons.arrow_forward,
                            isLoading: orderState is OrderLoading,
                            onPressed: () async {
                              if (_deliveryType == 'delivery') {
                                await _persistDeliveryPrefs();
                              }
                              if (!context.mounted) return;
                              final addr = _deliveryType == 'delivery'
                                  ? _addressController.text.trim().isNotEmpty
                                      ? _addressController.text.trim()
                                      : _labelController.text.trim()
                                  : 'Self pickup at vendor store';
                              context.read<OrderBloc>().add(
                                    CheckoutRequested(
                                      items: cartState.items,
                                      deliveryType: _deliveryType,
                                      deliveryAddress: addr,
                                      customerLat: _customerLat,
                                      customerLng: _customerLng,
                                    ),
                                  );
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              );
            },
          );
        },
      ),
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
          color: isSelected ? AppColors.primary.withOpacity(0.08) : Colors.grey.shade50,
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

  Widget _qtyButton(IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 30,
        height: 30,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: Colors.grey.shade300),
        ),
        child: Icon(icon, size: 16, color: AppColors.textPrimary),
      ),
    );
  }
}
