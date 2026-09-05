// ══════════════════════════════════════════════════════════════
// Customer orders list — used on Orders tab and full "My Orders" route
// ══════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../../config/app_theme.dart';
import '../../../config/app_routes.dart';
import '../../../core/models/order_model.dart';
import '../bloc/order_bloc.dart';

class CustomerOrdersPanel extends StatefulWidget {
  /// When false (embedded in home), no extra top padding for app bar.
  final bool showTopPadding;

  const CustomerOrdersPanel({super.key, this.showTopPadding = true});

  @override
  State<CustomerOrdersPanel> createState() => _CustomerOrdersPanelState();
}

class _CustomerOrdersPanelState extends State<CustomerOrdersPanel> {
  @override
  void initState() {
    super.initState();
    context.read<OrderBloc>().add(FetchCustomerOrders());
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'pending':
        return Colors.orange;
      case 'confirmed':
        return AppColors.secondary;
      case 'packed':
        return Colors.indigo;
      case 'ready_for_pickup':
        return Colors.teal;
      case 'picked':
        return Colors.deepPurple;
      case 'on_the_way':
        return AppColors.primary;
      case 'delivered':
        return AppColors.stockGreen;
      case 'cancelled':
        return AppColors.stockRed;
      default:
        return Colors.grey;
    }
  }

  void _showInvoice(BuildContext context, OrderModel order) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Invoice #VDR-${order.id.toString().padLeft(5, '0')}', style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (order.storeName != null)
                Text(order.storeName!, style: GoogleFonts.poppins(fontSize: 13, color: AppColors.textSecondary)),
              const SizedBox(height: 8),
              if (order.createdAt != null)
                Text(DateFormat('MMM dd, yyyy • hh:mm a').format(DateTime.parse(order.createdAt!)),
                    style: GoogleFonts.poppins(fontSize: 12, color: AppColors.textLight)),
              const Divider(height: 20),
              ...order.items.map((item) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      children: [
                        Text('${item.quantity}×', style: GoogleFonts.poppins(fontWeight: FontWeight.w600, color: AppColors.secondary)),
                        const SizedBox(width: 8),
                        Expanded(child: Text(item.productName ?? 'Item', style: GoogleFonts.poppins(fontSize: 13))),
                        Text('Rs. ${item.total.toStringAsFixed(0)}', style: GoogleFonts.poppins(fontSize: 13)),
                      ],
                    ),
                  )),
              const Divider(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Total', style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
                  Text('Rs. ${order.totalAmount.toStringAsFixed(0)}',
                      style: GoogleFonts.poppins(fontWeight: FontWeight.w700, color: AppColors.primary, fontSize: 18)),
                ],
              ),
              const SizedBox(height: 8),
              Text(order.deliveryTypeText, style: GoogleFonts.poppins(fontSize: 12, color: AppColors.textSecondary)),
              const SizedBox(height: 4),
              Text(order.escrowStatusText, style: GoogleFonts.poppins(fontSize: 11, color: Colors.amber.shade800)),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<OrderBloc, OrderState>(
      listenWhen: (_, curr) => curr is OrdersLoaded && curr.feedback != null,
      listener: (context, state) {
        final s = state as OrdersLoaded;
        if (s.feedback == null) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(s.feedback!, style: GoogleFonts.poppins()),
            backgroundColor: s.feedbackIsError ? AppColors.error : AppColors.stockGreen,
            behavior: SnackBarBehavior.floating,
          ),
        );
        context.read<OrderBloc>().add(ClearOrderFeedback());
      },
      builder: (context, state) {
        if (state is OrderLoading) {
          return const Center(child: CircularProgressIndicator(color: AppColors.primary));
        }
        if (state is OrderError) {
          return Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(state.message)));
        }
        if (state is OrdersLoaded) {
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

          return RefreshIndicator(
            onRefresh: () async {
              context.read<OrderBloc>().add(FetchCustomerOrders());
            },
            child: ListView.builder(
              padding: EdgeInsets.fromLTRB(16, widget.showTopPadding ? 12 : 0, 16, 24),
              itemCount: state.orders.length,
              itemBuilder: (context, index) {
                final order = state.orders[index];
                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  child: Theme(
                    data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                    child: ExpansionTile(
                      tilePadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                      childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
                      title: Row(
                        children: [
                          Expanded(
                            child: Text('#VDR-${order.id.toString().padLeft(5, '0')}',
                                style: GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 14)),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: _statusColor(order.status).withOpacity(0.12),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              order.statusText,
                              style: GoogleFonts.poppins(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: _statusColor(order.status),
                              ),
                            ),
                          ),
                        ],
                      ),
                      subtitle: Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(order.storeName ?? 'Vendor', style: GoogleFonts.poppins(fontSize: 12, color: AppColors.textSecondary)),
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                Text('Rs. ${order.totalAmount.toStringAsFixed(0)}',
                                    style: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.primary)),
                                const Spacer(),
                                if (order.createdAt != null)
                                  Text(
                                    DateFormat('MMM dd, yyyy').format(DateTime.parse(order.createdAt!)),
                                    style: GoogleFonts.poppins(fontSize: 11, color: AppColors.textLight),
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      children: [
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Text('Items', style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w600)),
                        ),
                        const SizedBox(height: 6),
                        ...order.items.map((item) => Padding(
                              padding: const EdgeInsets.only(bottom: 4),
                              child: Row(
                                children: [
                                  Text('${item.quantity}×', style: GoogleFonts.poppins(fontSize: 12, color: AppColors.secondary)),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(item.productName ?? '', style: GoogleFonts.poppins(fontSize: 12)),
                                  ),
                                  Text('Rs. ${item.total.toStringAsFixed(0)}', style: GoogleFonts.poppins(fontSize: 12)),
                                ],
                              ),
                            )),
                        const SizedBox(height: 10),
                        Text(order.escrowStatusText, style: GoogleFonts.poppins(fontSize: 11, fontWeight: FontWeight.w500, color: Colors.amber.shade800)),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: () => _showInvoice(context, order),
                                icon: const Icon(Icons.receipt_long_outlined, size: 18),
                                label: const Text('Invoice'),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: ElevatedButton.icon(
                                onPressed: () {
                                  Navigator.pushNamed(context, AppRoutes.orderTracking, arguments: order);
                                },
                                icon: const Icon(Icons.timeline, size: 18),
                                label: const Text('Track'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppColors.secondary,
                                  foregroundColor: Colors.white,
                                ),
                              ),
                            ),
                          ],
                        ),
                        if (order.deliveryType == 'self_pickup' &&
                            (order.status == 'ready_for_pickup' || order.status == 'picked')) ...[
                          const SizedBox(height: 10),
                          if (order.status == 'ready_for_pickup')
                            Row(
                              children: [
                                Expanded(
                                  child: OutlinedButton.icon(
                                    onPressed: () => context.read<OrderBloc>().add(CustomerMarkPickedUp(orderId: order.id)),
                                    icon: const Icon(Icons.inventory_2_outlined, size: 18),
                                    label: const Text('Picked Up'),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: ElevatedButton.icon(
                                    onPressed: () =>
                                        context.read<OrderBloc>().add(CustomerConfirmDelivered(orderId: order.id)),
                                    icon: const Icon(Icons.done_all, size: 18),
                                    label: const Text('Delivered'),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: AppColors.secondary,
                                      foregroundColor: Colors.white,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          if (order.status == 'picked')
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton.icon(
                                onPressed: () =>
                                    context.read<OrderBloc>().add(CustomerConfirmDelivered(orderId: order.id)),
                                icon: const Icon(Icons.done_all, size: 18),
                                label: const Text('Mark as Delivered'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppColors.secondary,
                                  foregroundColor: Colors.white,
                                ),
                              ),
                            ),
                        ],
                      ],
                    ),
                  ),
                );
              },
            ),
          );
        }
        return const SizedBox.shrink();
      },
    );
  }
}
