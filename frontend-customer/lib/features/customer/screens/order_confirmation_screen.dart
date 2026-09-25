// ══════════════════════════════════════════════════════════════
// Vendra App - Order Confirmation Screen
// Shown after successful checkout
// ══════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:vendra_customer/vendra_core.dart';
import '../../../config/app_routes.dart';
import '../../auth/bloc/auth_bloc.dart';
import '../../auth/bloc/auth_event.dart';

class OrderConfirmationScreen extends StatefulWidget {
  final OrderModel order;

  const OrderConfirmationScreen({super.key, required this.order});

  @override
  State<OrderConfirmationScreen> createState() => _OrderConfirmationScreenState();
}

class _OrderConfirmationScreenState extends State<OrderConfirmationScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<AuthBloc>().add(CheckAuthRequested());
    });
  }

  @override
  Widget build(BuildContext context) {
    final order = widget.order;
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Spacer(),

              Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                  color: AppColors.stockGreen.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.check_circle, color: AppColors.stockGreen, size: 64),
              ),

              const SizedBox(height: 24),

              Text(
                'Order Placed! ✨',
                style: GoogleFonts.poppins(fontSize: 24, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
              ),

              const SizedBox(height: 8),

              Text(
                'Your order is pending vendor approval.\nStock has been reserved for you.',
                textAlign: TextAlign.center,
                style: GoogleFonts.poppins(fontSize: 14, color: AppColors.textSecondary, height: 1.5),
              ),

              const SizedBox(height: 32),

              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
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
                    _infoRow('Subtotal', 'Rs. ${order.subtotal.toStringAsFixed(0)}'),
                    const SizedBox(height: 12),
                    _infoRow('Delivery fee', order.isDelivery ? 'Rs. ${order.deliveryFee.toStringAsFixed(0)}' : 'Free'),
                    const SizedBox(height: 12),
                    _infoRow(
                      'Total Amount',
                      'Rs. ${order.totalAmount.toStringAsFixed(0)}',
                      isBold: true,
                    ),
                    const SizedBox(height: 12),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFF8E1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.account_balance, size: 16, color: Colors.amber.shade700),
                          const SizedBox(width: 6),
                          Text(
                            order.escrowStatusText,
                            style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.amber.shade800),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              const Spacer(),

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
    );
  }

  Widget _infoRow(String label, String value, {bool isBold = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: GoogleFonts.poppins(fontSize: 13, color: AppColors.textSecondary)),
        Text(
          value,
          style: GoogleFonts.poppins(
            fontSize: isBold ? 16 : 14,
            fontWeight: isBold ? FontWeight.w700 : FontWeight.w500,
            color: isBold ? AppColors.primary : AppColors.textPrimary,
          ),
        ),
      ],
    );
  }
}
