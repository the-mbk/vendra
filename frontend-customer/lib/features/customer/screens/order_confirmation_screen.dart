// ══════════════════════════════════════════════════════════════
// Vendra App - Order Confirmation Screen
// Shown after successful checkout. Re-reads the order
// (GET /api/customer/orders/:id) for reservationExpiresAt, then shows the
// stock reservation countdown (FR02) and the escrow trust badge (FR03).
// When the reservation runs out the order is refreshed: by then the
// store has accepted it, or it was cancelled and refunded.
// ══════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:vendra_customer/vendra_core.dart';
import '../../../config/app_routes.dart';
import '../../auth/bloc/auth_bloc.dart';
import '../../auth/bloc/auth_event.dart';
import '../bloc/cart_bloc.dart';
import '../widgets/reservation_countdown.dart';
import '../widgets/trust_badges.dart';
import 'cart_screen.dart';

class OrderConfirmationScreen extends StatefulWidget {
  final OrderModel order;

  const OrderConfirmationScreen({super.key, required this.order});

  @override
  State<OrderConfirmationScreen> createState() => _OrderConfirmationScreenState();
}

class _OrderConfirmationScreenState extends State<OrderConfirmationScreen> {
  late OrderModel _order = widget.order;

  @override
  void initState() {
    super.initState();
    _refresh();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<AuthBloc>().add(CheckAuthRequested());
    });
  }

  /// The checkout response is a short summary; the full order has the
  /// reservation deadline (and stays current after it runs out)
  Future<void> _refresh() async {
    try {
      final res = await ApiService().get(ApiConfig.customerOrder(widget.order.id));
      if (res.data['success'] == true && mounted) {
        setState(() => _order = OrderModel.fromJson(Map<String, dynamic>.from(res.data['data'] as Map)));
      }
    } catch (_) {
      // Keep the checkout summary; the countdown falls back to createdAt + timeout
    }
  }

  @override
  Widget build(BuildContext context) {
    final order = _order;
    final cancelled = order.status == 'cancelled';
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: LayoutBuilder(
          // Scrolls on short screens; on tall ones the spacers centre the content
          builder: (context, constraints) => SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight - 48),
              child: IntrinsicHeight(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Spacer(),

                    Container(
                      width: 100,
                      height: 100,
                      decoration: BoxDecoration(
                        color: (cancelled ? AppColors.stockRed : AppColors.stockGreen).withValues(alpha: 0.1),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(cancelled ? Icons.cancel_outlined : Icons.check_circle,
                          color: cancelled ? AppColors.stockRed : AppColors.stockGreen, size: 64),
                    ),

                    const SizedBox(height: 24),

                    Text(
                      cancelled ? 'Order cancelled' : 'Order placed',
                      style: GoogleFonts.poppins(fontSize: 24, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
                    ),

                    const SizedBox(height: 8),

                    Text(
                      cancelled
                          ? 'The reserved stock was released and your payment refunded to your Vendra wallet.'
                          : order.status == 'pending'
                              ? 'Your order is pending vendor approval.\nStock has been reserved for you.'
                              : 'The store accepted your order.',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.poppins(fontSize: 14, color: AppColors.textSecondary, height: 1.5),
                    ),

                    const SizedBox(height: 20),

                    // Stock reservation timer (FR02), only while pending
                    if (reservationDeadline(order) != null) ...[
                      ReservationCountdown(order: order, onExpired: _refresh),
                      const SizedBox(height: 16),
                    ],

                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 12)],
                      ),
                      child: Column(
                        children: [
                          _infoRow('Order ID', '#VDR-${order.id.toString().padLeft(5, '0')}'),
                          const SizedBox(height: 12),
                          _infoRow('Status', order.statusText),
                          const SizedBox(height: 12),
                          _infoRow('Delivery', order.deliveryTypeText),
                          if (order.estimatedMinutes != null) ...[
                            const SizedBox(height: 12),
                            _infoRow('Est. Time', '~${order.estimatedMinutes} min'),
                          ],
                          const SizedBox(height: 12),
                          _infoRow('Items', '${order.items.length} item(s)'),
                          const Divider(height: 24),
                          _infoRow('Subtotal', formatRupees(order.subtotal)),
                          const SizedBox(height: 12),
                          _infoRow('Delivery fee', order.isDelivery ? formatRupees(order.deliveryFee) : 'Free'),
                          const SizedBox(height: 12),
                          _infoRow(
                            'Total Amount',
                            formatRupees(order.totalAmount),
                            isBold: true,
                          ),
                          const SizedBox(height: 14),
                          // Escrow trust badge (FR03)
                          if (order.escrowStatus == null || order.escrowStatus == 'held')
                            const EscrowTrustBadge()
                          else
                            Text(order.escrowStatusText,
                                style: GoogleFonts.poppins(
                                    fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.secondary)),
                        ],
                      ),
                    ),

                    // Carts from other stores: check the next one out straight away (pin and address are kept)
                    BlocBuilder<CartBloc, CartState>(
                      builder: (context, cart) {
                        final others = cart.stores.where((s) => s.vendorId != order.vendorId).toList();
                        if (others.isEmpty) return const SizedBox.shrink();
                        return Padding(padding: const EdgeInsets.only(top: 16), child: _NextCartCard(carts: others));
                      },
                    ),

                    const Spacer(),
                    const SizedBox(height: 24),

                    VendraButton(
                      text: 'Track live progress',
                      icon: Icons.timeline,
                      onPressed: () {
                        Navigator.pushReplacementNamed(context, AppRoutes.orderTracking, arguments: order);
                      },
                    ),

                    const SizedBox(height: 12),

                    VendraButton(
                      text: 'Back to Home',
                      icon: Icons.home_outlined,
                      onPressed: () {
                        Navigator.pushNamedAndRemoveUntil(context, AppRoutes.customerHome, (route) => false);
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _infoRow(String label, String value, {bool isBold = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: GoogleFonts.poppins(fontSize: 13, color: AppColors.textSecondary)),
        const SizedBox(width: 12),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.right,
            style: GoogleFonts.poppins(
              fontSize: isBold ? 16 : 14,
              fontWeight: isBold ? FontWeight.w700 : FontWeight.w500,
              color: isBold ? AppColors.primary : AppColors.textPrimary,
            ),
          ),
        ),
      ],
    );
  }
}

/// "You also have a cart at Lahore Fashion" with a one-tap checkout of the next one
class _NextCartCard extends StatelessWidget {
  final List<StoreCart> carts;
  const _NextCartCard({required this.carts});

  @override
  Widget build(BuildContext context) {
    final next = carts.first;
    final more = carts.length - 1;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              StoreLogo(storeName: next.storeName, logoUrl: next.storeLogoUrl, size: 36),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Next cart: ${next.storeName}',
                        style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                    Text(
                      '${next.totalItems} item${next.totalItems == 1 ? '' : 's'} · ${formatRupees(next.totalAmount)}'
                      '${more > 0 ? ' · $more more cart${more == 1 ? '' : 's'} after this' : ''}',
                      style: GoogleFonts.poppins(fontSize: 12, color: AppColors.textSecondary),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text('Each store sends its own rider, so carts are paid one store at a time. Your pin and address carry over.',
              style: GoogleFonts.poppins(fontSize: 12, color: AppColors.textSecondary)),
          const SizedBox(height: 10),
          ElevatedButton.icon(
            onPressed: () => Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (_) => CartScreen(vendorId: next.vendorId)),
            ),
            icon: const Icon(Icons.shopping_cart_checkout),
            label: const Text('Check out next cart'),
          ),
        ],
      ),
    );
  }
}
