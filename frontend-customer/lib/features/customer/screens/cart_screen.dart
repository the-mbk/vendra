// ══════════════════════════════════════════════════════════════
// Vendra App - Cart Screen (one store's cart)
// Every order comes from one store, so each store has its own cart
// (CartsScreen lists them). Delivery method, saved address/pin, checkout
// - Stores farther than the max delivery distance (admin policy) offer
//   self pickup only
// - Delivery needs a map pin: the rider can only complete the delivery
//   inside the geofence around it (FR04), so checkout sends lat/lng
// - Delivery fee depends on the distance from the store to the pin: the
//   cart asks POST /api/customer/checkout/quote whenever the items, the pin
//   or an admin policy change, and shows exactly what checkout will charge
// - Live stock (FR01) flags lines the store can no longer fill
// - Pay from the wallet, or by card (shared CardPaymentFlow: card sheet →
//   POST /api/payments/checkout → one-time password if asked)
// - 409 INSUFFICIENT_STOCK / 400 INSUFFICIENT_BALANCE explained clearly;
//   a card charged for an order that then couldn't be placed is explained
//   (the money is in the wallet)
// ══════════════════════════════════════════════════════════════

import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:latlong2/latlong.dart';

import 'package:vendra_customer/vendra_core.dart';
import '../../../config/app_routes.dart';
import '../../../core/models/cart_item_model.dart';
import '../../../core/services/customer_location_storage.dart';
import '../bloc/cart_bloc.dart';
import '../bloc/checkout_bloc.dart';
import '../bloc/order_bloc.dart';
import '../../auth/bloc/auth_bloc.dart';
import '../../auth/bloc/auth_event.dart';
import '../../auth/bloc/auth_state.dart';
import '../widgets/wallet_actions.dart';

/// Opens one store's cart
void openStoreCart(BuildContext context, int vendorId) {
  Navigator.push(context, MaterialPageRoute(builder: (_) => CartScreen(vendorId: vendorId)));
}

class CartScreen extends StatefulWidget {
  /// The store whose cart this is
  final int vendorId;

  const CartScreen({super.key, required this.vendorId});

  @override
  State<CartScreen> createState() => _CartScreenState();
}

/// The server's price for the cart as it is now
class _CartQuote {
  final double subtotal;
  final double deliveryFee;
  final double total;
  final double distanceKm;
  const _CartQuote(this.subtotal, this.deliveryFee, this.total, this.distanceKm);
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

  bool get _isDelivery => _deliveryType == 'delivery';

  /// wallet | card
  String _paymentMethod = 'wallet';
  bool get _payByCard => _paymentMethod == 'card';
  bool get _cardAvailable => AppConfig.current.payments.isAvailable;

  /// Quote for the current delivery cart; [_quoteKey] is the request it belongs to
  _CartQuote? _quote;
  String? _quoteKey;
  bool _quoteLoading = false;
  String? _quoteError;
  Timer? _quoteDebounce;

  @override
  void initState() {
    super.initState();
    _loadSavedDeliveryPrefs();
    _loadConfig();
    AppConfig.notifier.addListener(_onConfigChanged);
  }

  /// An admin changed a policy (fee rates, geofence…): redraw and re-quote
  void _onConfigChanged() {
    if (!mounted) return;
    setState(() => _quoteKey = null);
  }

  /// Asks for a fresh quote when the delivery cart changed. Called while building,
  /// so it only sets fields the rest of this build reads.
  void _ensureQuote(CartState cart) {
    if (!_isDelivery || !_hasPin || cart.items.isEmpty) return;
    final body = {
      'items': cart.items.map((i) => {'productId': i.product.id, 'quantity': i.quantity}).toList(),
      'deliveryType': 'delivery',
      'customerLat': _customerLat,
      'customerLng': _customerLng,
    };
    final key = jsonEncode(body);
    if (key == _quoteKey) return;
    _quoteKey = key;
    _quote = null;
    _quoteError = null;
    _quoteLoading = true;
    _quoteDebounce?.cancel();
    _quoteDebounce = Timer(const Duration(milliseconds: 300), () => _fetchQuote(key, body));
  }

  Future<void> _fetchQuote(String key, Map<String, dynamic> body) async {
    try {
      final res = await ApiService().post(ApiConfig.checkoutQuote, data: body);
      final d = Map<String, dynamic>.from(res.data['data'] as Map);
      if (!mounted || key != _quoteKey) return;
      setState(() {
        _quote = _CartQuote(toDouble(d['subtotal']), toDouble(d['deliveryFee']), toDouble(d['total']), toDouble(d['distanceKm']));
        _quoteLoading = false;
      });
    } catch (e) {
      if (!mounted || key != _quoteKey) return;
      setState(() {
        _quoteLoading = false;
        _quoteError = ApiService.getErrorMessage(e);
      });
    }
  }

  /// Retries the startup config fetch if the backend was unreachable then
  /// (fee rates and geofence are read live from AppConfig.current)
  Future<void> _loadConfig() async {
    if (AppConfig.current.fromServer) return;
    await AppConfig.ensureLoaded();
    if (mounted) setState(() {});
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
    AppConfig.notifier.removeListener(_onConfigChanged);
    _quoteDebounce?.cancel();
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

  int get _geofence => AppConfig.current.geofenceMeters;

  /// Straight-line km from this store to the delivery pin (null without a pin or store location)
  double? _storeKm(CartState cart) {
    if (!_hasPin || cart.items.isEmpty) return null;
    final p = cart.items.first.product;
    if (p.vendorLat == null || p.vendorLng == null) return null;
    return _haversineKm(_customerLat, _customerLng, p.vendorLat!, p.vendorLng!);
  }

  /// The store is beyond the max delivery distance from the pin
  bool _outOfRange(CartState cart) {
    final km = _storeKm(cart);
    return km != null && !AppConfig.current.deliversAt(km);
  }

  String _rangeText(CartState cart) =>
      '${_storeKm(cart)!.toStringAsFixed(1)} km from your pin · delivery up to ${AppConfig.current.maxDeliveryKm.toStringAsFixed(0)} km';

  bool _rangeChecked = false;

  /// On opening, a store out of delivery range starts on self pickup (once)
  void _pickupIfTooFar(CartState cart) {
    if (_rangeChecked || !_prefsLoaded || cart.isEmpty) return;
    _rangeChecked = true;
    if (_isDelivery && _outOfRange(cart)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _deliveryType = 'self_pickup');
      });
    }
  }

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

  /// null while the fee is unknown (no pin yet, quote loading or failed)
  double? get _deliveryFee => _isDelivery ? _quote?.deliveryFee : 0;

  /// What the fee depends on, from the admin policies
  String get _feeRates {
    final c = AppConfig.current;
    if (!c.fromServer) return '';
    return c.deliveryFeePerKm > 0 ? '${_money(c.deliveryFee)} + ${_money(c.deliveryFeePerKm)}/km' : _money(c.deliveryFee);
  }

  String _money(double v) => formatRupees(v.roundToDouble());

  /// Subtotal + delivery fee, or null while the fee is unknown
  double? _orderTotal(CartState cartState) {
    final fee = _deliveryFee;
    return fee == null ? null : cartState.totalAmount + fee;
  }

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
    if (_isDelivery && _outOfRange(cartState)) {
      _snack('${_rangeText(cartState)}. Choose self pickup instead.', error: true);
      return;
    }
    if (_isDelivery) await _persistDeliveryPrefs();
    if (!mounted) return;

    final addr = _isDelivery
        ? (_addressController.text.trim().isNotEmpty ? _addressController.text.trim() : _labelController.text.trim())
        : null;
    final request = CheckoutRequested(
      items: cartState.items,
      deliveryType: _deliveryType,
      deliveryAddress: addr,
      customerLat: _isDelivery ? _customerLat : null,
      customerLng: _isDelivery ? _customerLng : null,
    );
    if (_payByCard) {
      await _payWithCard(request, cartState);
    } else {
      _checkoutBloc.add(request);
    }
  }

  /// Card checkout: the server checks the cart first, then charges the exact total
  Future<void> _payWithCard(CheckoutRequested request, CartState cartState) async {
    final total = _orderTotal(cartState);
    final outcome = await CardPaymentFlow.run(
      context,
      title: 'Pay by card',
      subtitle: 'The total is held in escrow until '
          '${_isDelivery ? 'your order is delivered' : 'you collect your order'}.',
      actionLabel: total != null ? 'Pay ${formatRupees(total)}' : 'Pay',
      submit: (token) => ApiService().post(ApiConfig.paymentsCheckout, data: {...request.toBody(), 'token': token}),
    );
    if (mounted) _checkoutBloc.add(CardCheckoutCompleted(outcome));
  }

  /// Wallet too low: pay this order by card instead, or add money first
  Future<void> _offerCardOrTopUp(String message, CartState cartState) async {
    final total = _orderTotal(cartState);
    final choice = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Not enough in your wallet', style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
        content: Text(
          '$message\n\nPay ${total != null ? formatRupees(total) : 'the total'} by card instead, or add money to your wallet first.',
          style: GoogleFonts.poppins(fontSize: 13, color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, 'topup'), child: const Text('Add money')),
          if (_cardAvailable)
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, 'card'),
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, foregroundColor: Colors.white),
              child: const Text('Pay by card'),
            ),
        ],
      ),
    );
    if (!mounted || choice == null) return;
    if (choice == 'card') {
      setState(() => _paymentMethod = 'card');
      await _placeOrder(cartState);
    } else {
      final auth = context.read<AuthBloc>().state;
      final balance = auth is Authenticated ? auth.user.walletBalance : 0.0;
      final result = await startCardTopUp(context, suggestedAmount: total != null ? total - balance : null);
      if (result != null && mounted) _snack(result.message, error: !result.success);
    }
  }

  /// The card was charged but the order couldn't be placed — explain where the money is
  Future<void> _explainPaidNotPlaced(CheckoutPaidNotPlaced state) {
    return showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        icon: const Icon(Icons.account_balance_wallet_outlined, color: AppColors.reservedAmber, size: 36),
        title: Text("Your order couldn't be placed",
            textAlign: TextAlign.center, style: GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 17)),
        content: Text(
          '${state.reason}\n\nThe ${formatRupees(state.amount)} charged to ${state.cardLabel} is safe in your '
          'Vendra wallet. Update your cart and pay from the wallet, or withdraw it back to a card.',
          textAlign: TextAlign.center,
          style: GoogleFonts.poppins(fontSize: 13, color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              Navigator.pushNamed(context, AppRoutes.wallet);
            },
            child: const Text('Open wallet'),
          ),
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Back to cart')),
        ],
      ),
    );
  }

  void _onCheckoutState(BuildContext context, CheckoutState state) {
    if (state is CheckoutSuccess) {
      if (state.walletBalance != null) {
        context.read<AuthBloc>().add(AuthWalletBalanceUpdated(walletBalance: state.walletBalance!));
      }
      context.read<OrderBloc>().add(const FetchCustomerOrders(silent: true, scope: OrderScope.active));
      context.read<CartBloc>().add(ClearStoreCart(vendorId: widget.vendorId));
      if (state.paidWith != null) _snack('Paid with ${state.paidWith}');
      Navigator.pushReplacementNamed(context, AppRoutes.orderConfirmation, arguments: state.order);
    } else if (state is CheckoutPaidNotPlaced) {
      if (state.walletBalance != null) {
        context.read<AuthBloc>().add(AuthWalletBalanceUpdated(walletBalance: state.walletBalance!));
      }
      // The money is already in the wallet: pay from there next time
      setState(() => _paymentMethod = 'wallet');
      _explainPaidNotPlaced(state);
    } else if (state is CheckoutFailure && state.isOrderPlacedElsewhere) {
      context.read<OrderBloc>().add(const FetchCustomerOrders(silent: true, scope: OrderScope.active));
      context.read<CartBloc>().add(ClearStoreCart(vendorId: widget.vendorId));
      _snack(state.message);
      Navigator.pushReplacementNamed(context, AppRoutes.customerOrders);
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
        _offerCardOrTopUp(state.message, context.read<CartBloc>().state.forStore(widget.vendorId));
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
        title: BlocBuilder<CartBloc, CartState>(
          builder: (context, cart) {
            final store = cart.forStore(widget.vendorId);
            final name = store.isEmpty ? 'Cart' : store.stores.first.storeName;
            return Text(name, style: GoogleFonts.poppins(fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis);
          },
        ),
      ),
      body: BlocConsumer<CheckoutBloc, CheckoutState>(
        bloc: _checkoutBloc,
        listener: _onCheckoutState,
        builder: (context, checkoutState) {
          return BlocBuilder<CartBloc, CartState>(
            builder: (context, allCarts) {
              final cartState = allCarts.forStore(widget.vendorId);
              _pickupIfTooFar(cartState);
              if (cartState.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.shopping_cart_outlined, size: 80, color: Colors.grey.shade300),
                      const SizedBox(height: 16),
                      Text('This cart is empty', style: GoogleFonts.poppins(fontSize: 18, color: AppColors.textSecondary)),
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
                              _paymentMethodCard(),
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
    final tooFar = _outOfRange(cartState);
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
          IntrinsicHeight(
            child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: _deliveryOption(
                  icon: Icons.delivery_dining,
                  label: 'Home Delivery',
                  subtitle: tooFar
                      ? 'Too far for delivery'
                      : (_feeRates.isNotEmpty ? 'A rider brings it to your pin • $_feeRates' : 'A rider brings it to your pin'),
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
          ),
          if (tooFar) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: Colors.orange.shade50, borderRadius: BorderRadius.circular(10)),
              child: Row(
                children: [
                  Icon(Icons.info_outline, size: 18, color: Colors.orange.shade800),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '${_rangeText(cartState)}. Choose self pickup, or move your pin closer.',
                      style: GoogleFonts.poppins(fontSize: 12, color: Colors.orange.shade900),
                    ),
                  ),
                ],
              ),
            ),
          ],
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

  Widget _paymentMethodCard() {
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
          Text('Payment method', style: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w600)),
          const SizedBox(height: 12),
          IntrinsicHeight(
            child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: BlocBuilder<AuthBloc, AuthState>(
                  builder: (context, auth) => _choiceOption(
                    icon: Icons.account_balance_wallet_outlined,
                    label: 'Wallet',
                    subtitle: auth is Authenticated ? '${_money(auth.user.walletBalance)} available' : 'Vendra balance',
                    selected: !_payByCard,
                    onTap: () => setState(() => _paymentMethod = 'wallet'),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _choiceOption(
                  icon: Icons.credit_card,
                  label: 'Card',
                  subtitle: _cardAvailable ? 'Visa / Mastercard' : 'Unavailable right now',
                  selected: _payByCard,
                  onTap: _cardAvailable ? () => setState(() => _paymentMethod = 'card') : null,
                ),
              ),
            ],
          ),
          ),
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
                  style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w600, color: const Color(0xFF8A5A00)),
                ),
                Text(
                  '${_payByCard ? 'Your card is charged the total now and it is held in escrow.' : 'The total moves from your wallet into escrow now.'} '
                  'The store is paid only after '
                  '${_isDelivery ? 'the rider delivers' : 'you confirm pickup'} and the dispute window closes.',
                  style: GoogleFonts.poppins(fontSize: 11, height: 1.4, color: const Color(0xFF6D4C00)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _totalsPanel(CartState cartState, bool submitting) {
    _ensureQuote(cartState);
    // The quote is the server's price; until it arrives show the cart's own subtotal
    final quote = _isDelivery ? _quote : null;
    final subtotal = quote?.subtotal ?? cartState.totalAmount;
    final fee = _deliveryFee;
    final total = quote?.total ?? (fee == null ? null : subtotal + fee);
    final feeLabel = _isDelivery && quote != null
        ? 'Delivery fee (${quote.distanceKm.toStringAsFixed(1)} km)'
        : (_isDelivery ? 'Delivery fee' : 'Self pickup');

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
              feeLabel,
              !_isDelivery
                  ? 'Free'
                  : fee != null
                      ? _money(fee)
                      : !_hasPin
                          ? 'Set your pin'
                          : (_quoteLoading ? '…' : 'Added at checkout'),
              valueColor: _isDelivery ? AppColors.textPrimary : Colors.green,
            ),
            if (_isDelivery && _quoteError != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(_quoteError!, style: GoogleFonts.poppins(fontSize: 11, color: AppColors.error)),
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
            if (_payByCard)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  children: [
                    const Icon(Icons.credit_card, size: 16, color: AppColors.textSecondary),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Charged to your card · held in escrow until the order is complete',
                        style: GoogleFonts.poppins(fontSize: 12, color: AppColors.textSecondary),
                      ),
                    ),
                  ],
                ),
              )
            else
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
                                  ? 'Wallet has ${_money(balance)} — add ${_money(total - balance)} more or pay by card'
                                  : 'Paid from wallet · ${_money(balance)} available',
                              style: GoogleFonts.poppins(fontSize: 12, color: short ? AppColors.error : AppColors.textSecondary),
                            ),
                          ),
                          Text(short ? 'Add money' : 'View',
                              style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.secondary)),
                        ],
                      ),
                    ),
                  );
                },
              ),
            VendraButton(
              text: _isDelivery && !_hasPin
                  ? 'Set delivery pin'
                  : _payByCard
                      ? (total != null ? 'Pay ${_money(total)} by card' : 'Pay by card')
                      : 'Place Order',
              icon: _isDelivery && !_hasPin
                  ? Icons.pin_drop_outlined
                  : _payByCard
                      ? Icons.lock_outline
                      : Icons.arrow_forward,
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
    return _choiceOption(
      icon: icon,
      label: label,
      subtitle: subtitle,
      selected: _deliveryType == value,
      onTap: () => setState(() => _deliveryType = value),
    );
  }

  /// A selectable tile (delivery method, payment method); [onTap] null = disabled
  Widget _choiceOption({
    required IconData icon,
    required String label,
    required String subtitle,
    required bool selected,
    required VoidCallback? onTap,
  }) {
    final isSelected = selected;
    return GestureDetector(
      onTap: onTap,
      child: Opacity(
        opacity: onTap == null ? 0.5 : 1,
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
            mainAxisAlignment: MainAxisAlignment.center,
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
                style: GoogleFonts.poppins(fontSize: 10, height: 1.3, color: AppColors.textSecondary),
                textAlign: TextAlign.center,
              ),
            ],
          ),
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
