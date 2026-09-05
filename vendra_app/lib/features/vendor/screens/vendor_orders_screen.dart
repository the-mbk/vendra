// ══════════════════════════════════════════════════════════════
// Vendra App - Vendor Orders Screen
// Shows incoming orders with approve/reject for pending orders
// ══════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../../config/app_theme.dart';
import '../bloc/vendor_order_bloc.dart';
import '../../auth/bloc/auth_bloc.dart';
import '../../auth/bloc/auth_event.dart';

class VendorOrdersScreen extends StatelessWidget {
  const VendorOrdersScreen({super.key});

  Color _statusColor(String status) {
    switch (status) {
      case 'pending': return Colors.orange;
      case 'confirmed': return AppColors.stockGreen;
      case 'packed': return Colors.indigo;
      case 'ready_for_pickup': return Colors.teal;
      case 'picked': return Colors.deepPurple;
      case 'on_the_way': return AppColors.primary;
      case 'delivered': return Colors.green.shade700;
      case 'cancelled': return AppColors.stockRed;
      default: return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Text('Incoming Orders', style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.w600)),
        ),
        Expanded(
          child: RefreshIndicator(
        onRefresh: () async {
          context.read<VendorOrderBloc>().add(FetchVendorOrders());
        },
        child: BlocConsumer<VendorOrderBloc, VendorOrderState>(
          listener: (context, state) {
            if (state is VendorOrderActionSuccess) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(state.message),
                  backgroundColor: AppColors.success,
                  behavior: SnackBarBehavior.floating,
                ),
              );
              context.read<AuthBloc>().add(CheckAuthRequested());
              context.read<VendorOrderBloc>().add(FetchVendorOrders());
            }
            if (state is VendorOrderActionError) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(state.message),
                  backgroundColor: AppColors.error,
                  behavior: SnackBarBehavior.floating,
                ),
              );
            }
          },
          builder: (context, state) {
            if (state is VendorOrderLoading) {
              return const Center(child: CircularProgressIndicator(color: AppColors.primary));
            }

            if (state is VendorOrderError) {
              return Center(child: Text(state.message));
            }

            if (state is VendorOrderLoaded) {
              if (state.orders.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.receipt_long_outlined, size: 64, color: Colors.grey.shade300),
                      const SizedBox(height: 16),
                      Text('No orders yet', style: GoogleFonts.poppins(color: AppColors.textSecondary)),
                    ],
                  ),
                );
              }

              return ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: state.orders.length,
                itemBuilder: (context, index) {
                  final order = state.orders[index];
                  final isPending = order.status == 'pending';
                  final escrowActive = order.status != 'cancelled' && order.status != 'delivered';

                  return Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      border: isPending ? Border.all(color: Colors.orange.shade300, width: 1.5) : null,
                      boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8)],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Header: order ID + status
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('#ORD-${order.id.toString().padLeft(3, '0')}',
                                style: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w600)),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: _statusColor(order.status).withOpacity(0.1),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                order.statusText,
                                style: GoogleFonts.poppins(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: _statusColor(order.status),
                                ),
                              ),
                            ),
                          ],
                        ),

                        if (escrowActive) ...[
                          const SizedBox(height: 4),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.green.shade50,
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(color: Colors.green.shade200),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.lock_outline, size: 14, color: Colors.green.shade700),
                                const SizedBox(width: 4),
                                Text('Escrow Funded (Hold)', style: GoogleFonts.poppins(fontSize: 10, color: Colors.green.shade700, fontWeight: FontWeight.w500)),
                              ],
                            ),
                          ),
                        ],

                        const SizedBox(height: 8),

                        // Customer name
                        Row(
                          children: [
                            const Icon(Icons.person_outline, size: 16, color: AppColors.textSecondary),
                            const SizedBox(width: 6),
                            Text(order.customerName ?? 'Customer',
                                style: GoogleFonts.poppins(fontSize: 13, color: AppColors.textSecondary)),
                          ],
                        ),

                        const SizedBox(height: 4),

                        // Delivery type
                        Row(
                          children: [
                            Icon(
                              order.deliveryType == 'self_pickup' ? Icons.store : Icons.delivery_dining,
                              size: 16,
                              color: AppColors.secondary,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              order.deliveryType == 'self_pickup' ? 'Self Pickup' : 'Home Delivery',
                              style: GoogleFonts.poppins(fontSize: 12, color: AppColors.secondary, fontWeight: FontWeight.w500),
                            ),
                            if (order.estimatedMinutes != null) ...[
                              const SizedBox(width: 8),
                              Text(
                                '~${order.estimatedMinutes} min',
                                style: GoogleFonts.poppins(fontSize: 11, color: AppColors.textLight),
                              ),
                            ],
                          ],
                        ),

                        const SizedBox(height: 4),

                        // Items summary
                        Text('${order.items.length} item(s)',
                            style: GoogleFonts.poppins(fontSize: 12, color: AppColors.textLight)),

                        const Divider(height: 16),

                        // Bottom row: date + total
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            if (order.createdAt != null)
                              Text(
                                DateFormat('MMM dd, hh:mm a').format(DateTime.parse(order.createdAt!)),
                                style: GoogleFonts.poppins(fontSize: 12, color: AppColors.textLight),
                              ),
                            Text(
                              'Rs. ${order.totalAmount.toStringAsFixed(0)}',
                              style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.primary),
                            ),
                          ],
                        ),

                        // ── Approve / Reject buttons for pending orders ──
                        if (isPending) ...[
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: () {
                                    _showRejectConfirmation(context, order.id);
                                  },
                                  icon: const Icon(Icons.close, size: 18),
                                  label: Text('Reject', style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: AppColors.stockRed,
                                    side: const BorderSide(color: AppColors.stockRed),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                    padding: const EdgeInsets.symmetric(vertical: 10),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: ElevatedButton.icon(
                                  onPressed: () {
                                    context.read<VendorOrderBloc>().add(ApproveVendorOrder(orderId: order.id));
                                  },
                                  icon: const Icon(Icons.check, size: 18),
                                  label: Text('Approve', style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: AppColors.stockGreen,
                                    foregroundColor: Colors.white,
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                    padding: const EdgeInsets.symmetric(vertical: 10),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],

                        if (order.status == 'confirmed') ...[
                          const SizedBox(height: 12),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              onPressed: () {
                                context.read<VendorOrderBloc>().add(MarkOrderPreparing(orderId: order.id));
                              },
                              icon: const Icon(Icons.restaurant_outlined, size: 18),
                              label: Text('Mark as Preparing', style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.indigo,
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                padding: const EdgeInsets.symmetric(vertical: 10),
                              ),
                            ),
                          ),
                        ],

                        if (order.status == 'packed') ...[
                          const SizedBox(height: 12),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              onPressed: () {
                                context.read<VendorOrderBloc>().add(MarkOrderReadyForPickup(orderId: order.id));
                              },
                              icon: const Icon(Icons.storefront_outlined, size: 18),
                              label: Text('Mark as Ready for Pickup', style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.primary,
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                padding: const EdgeInsets.symmetric(vertical: 10),
                              ),
                            ),
                          ),
                        ],

                        if (order.deliveryType == 'self_pickup' &&
                            (order.status == 'ready_for_pickup' || order.status == 'picked')) ...[
                          const SizedBox(height: 12),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              onPressed: () {
                                context.read<VendorOrderBloc>().add(DeliverVendorOrder(orderId: order.id));
                              },
                              icon: const Icon(Icons.done_all, size: 18),
                              label: Text('Mark as Delivered', style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.teal.shade700,
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                padding: const EdgeInsets.symmetric(vertical: 10),
                              ),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Text(
                              'Completes the order and releases escrow to your wallet.',
                              style: GoogleFonts.poppins(fontSize: 11, color: AppColors.textSecondary),
                            ),
                          ),
                        ],
                      ],
                    ),
                  );
                },
              );
            }

            return const SizedBox();
          },
        ),
      ),
    ),
      ],
    );
  }

  void _showRejectConfirmation(BuildContext context, int orderId) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Reject Order?', style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
        content: Text(
          'This will cancel the order and release the reserved stock. This action cannot be undone.',
          style: GoogleFonts.poppins(fontSize: 13, color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel', style: GoogleFonts.poppins(color: AppColors.textSecondary)),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              context.read<VendorOrderBloc>().add(RejectVendorOrder(orderId: orderId));
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.stockRed),
            child: Text('Reject', style: GoogleFonts.poppins(color: Colors.white)),
          ),
        ],
      ),
    );
  }
}
