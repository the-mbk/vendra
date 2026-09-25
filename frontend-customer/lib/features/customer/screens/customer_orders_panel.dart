// ══════════════════════════════════════════════════════════════
// Customer orders list — used on Orders tab and full "My Orders" route
// Shows live status (incl. rider assignment / picked / on the way),
// rider contact, escrow state and dispute status. Updates in place
// when the server pushes order:update (OrderBloc listens). Pages load
// with infinite scroll as the list nears its end.
// ══════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:vendra_customer/vendra_core.dart';
import '../../../config/app_routes.dart';
import '../bloc/order_bloc.dart';
import '../widgets/order_status_widgets.dart';
import 'report_issue_screen.dart';

class CustomerOrdersPanel extends StatefulWidget {
  /// When false (embedded in home), no extra top padding for app bar.
  final bool showTopPadding;

  const CustomerOrdersPanel({super.key, this.showTopPadding = true});

  @override
  State<CustomerOrdersPanel> createState() => _CustomerOrdersPanelState();
}

class _CustomerOrdersPanelState extends State<CustomerOrdersPanel> {
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_maybeLoadMore);
    context.read<OrderBloc>().add(const FetchCustomerOrders());
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  /// Asks for the next page when the end of the list is close (or already on
  /// screen). The bloc ignores it while a page is loading or none are left.
  void _maybeLoadMore() {
    if (!_scroll.hasClients) return;
    final state = context.read<OrderBloc>().state;
    if (state is! OrdersLoaded || !state.hasMore || state.loadingMore) return;
    if (_scroll.position.extentAfter < 400) {
      context.read<OrderBloc>().add(const LoadMoreCustomerOrders());
    }
  }

  void _openTracking(OrderModel order) =>
      Navigator.pushNamed(context, AppRoutes.orderTracking, arguments: order);

  void _openReport(OrderModel order) =>
      Navigator.push(context, MaterialPageRoute(builder: (_) => ReportIssueScreen(order: order)));

  void _showInvoice(BuildContext context, OrderModel order) {
    Widget line(String label, String value, {bool bold = false}) => Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: GoogleFonts.poppins(fontWeight: bold ? FontWeight.w600 : FontWeight.w400, fontSize: 13)),
            Text(value,
                style: GoogleFonts.poppins(
                  fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
                  color: bold ? AppColors.primary : AppColors.textPrimary,
                  fontSize: bold ? 18 : 13,
                )),
          ],
        );

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
                Text(DateFormat('MMM dd, yyyy • hh:mm a').format(DateTime.parse(order.createdAt!).toLocal()),
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
              line('Subtotal', 'Rs. ${order.subtotal.toStringAsFixed(0)}'),
              const SizedBox(height: 4),
              line('Delivery fee', order.isDelivery ? 'Rs. ${order.deliveryFee.toStringAsFixed(0)}' : 'Free'),
              const Divider(height: 16),
              line('Total', 'Rs. ${order.totalAmount.toStringAsFixed(0)}', bold: true),
              const SizedBox(height: 8),
              Text(order.deliveryTypeText, style: GoogleFonts.poppins(fontSize: 12, color: AppColors.textSecondary)),
              const SizedBox(height: 4),
              EscrowStatusLine(order: order),
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
        if (state is OrderLoading || state is OrderInitial) {
          return const Center(child: CircularProgressIndicator(color: AppColors.primary));
        }
        if (state is OrderError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(state.message, textAlign: TextAlign.center),
                  TextButton(
                    onPressed: () => context.read<OrderBloc>().add(const FetchCustomerOrders()),
                    child: const Text('Retry'),
                  ),
                ],
              ),
            ),
          );
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

          // A short first page may not fill the screen, so nothing would scroll
          if (state.hasMore && !state.loadingMore) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) _maybeLoadMore();
            });
          }

          return RefreshIndicator(
            onRefresh: () async {
              context.read<OrderBloc>().add(const FetchCustomerOrders(silent: true));
            },
            child: ListView.builder(
              controller: _scroll,
              physics: const AlwaysScrollableScrollPhysics(),
              padding: EdgeInsets.fromLTRB(16, widget.showTopPadding ? 12 : 0, 16, 24),
              itemCount: state.orders.length + 1 + (state.hasMore ? 1 : 0),
              itemBuilder: (context, index) {
                if (index == state.orders.length + 1) {
                  // Next page on its way
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: Center(
                      child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2)),
                    ),
                  );
                }
                if (index == 0) {
                  return Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      onPressed: () => Navigator.pushNamed(context, AppRoutes.myDisputes),
                      icon: const Icon(Icons.gavel_outlined, size: 18),
                      label: const Text('My disputes'),
                    ),
                  );
                }
                return _orderCard(context, state.orders[index - 1]);
              },
            ),
          );
        }
        return const SizedBox.shrink();
      },
    );
  }

  Widget _orderCard(BuildContext context, OrderModel order) {
    final color = orderStatusColor(order);
    final rider = order.rider;
    final showRider = order.isDelivery && rider != null && order.status != 'cancelled';

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
              Flexible(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    order.statusText,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.poppins(fontSize: 11, fontWeight: FontWeight.w600, color: color),
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
                Text('${order.storeName ?? 'Vendor'} · ${order.deliveryTypeText}',
                    style: GoogleFonts.poppins(fontSize: 12, color: AppColors.textSecondary)),
                if (showRider)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Row(
                      children: [
                        const Icon(Icons.delivery_dining, size: 14, color: AppColors.secondary),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            rider.name ?? 'Rider',
                            style: GoogleFonts.poppins(fontSize: 12, color: AppColors.secondary, fontWeight: FontWeight.w500),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        // Tap-to-call (copies the number where calling isn't possible)
                        PhoneAction(phone: rider.phone),
                      ],
                    ),
                  ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Text('Rs. ${order.totalAmount.toStringAsFixed(0)}',
                        style: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.primary)),
                    const Spacer(),
                    if (order.createdAt != null)
                      Text(
                        DateFormat('MMM dd, yyyy').format(DateTime.parse(order.createdAt!).toLocal()),
                        style: GoogleFonts.poppins(fontSize: 11, color: AppColors.textLight),
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                EscrowStatusLine(order: order),
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
                      Expanded(child: Text(item.productName ?? '', style: GoogleFonts.poppins(fontSize: 12))),
                      Text('Rs. ${item.total.toStringAsFixed(0)}', style: GoogleFonts.poppins(fontSize: 12)),
                    ],
                  ),
                )),
            if (order.isDelivery)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  children: [
                    Expanded(child: Text('Delivery fee', style: GoogleFonts.poppins(fontSize: 12, color: AppColors.textSecondary))),
                    Text('Rs. ${order.deliveryFee.toStringAsFixed(0)}', style: GoogleFonts.poppins(fontSize: 12)),
                  ],
                ),
              ),
            const SizedBox(height: 10),
            OrderDisputeSection(
              order: order,
              compact: true,
              onReport: () => _openReport(order),
              onViewDisputes: () => Navigator.pushNamed(context, AppRoutes.myDisputes),
            ),
            const SizedBox(height: 10),
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
                    onPressed: () => _openTracking(order),
                    icon: Icon(order.isDelivery ? Icons.map_outlined : Icons.timeline, size: 18),
                    label: const Text('Track'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.secondary,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
            if (!order.isDelivery && (order.status == 'ready_for_pickup' || order.status == 'picked')) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  if (order.status == 'ready_for_pickup') ...[
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => context.read<OrderBloc>().add(CustomerMarkPickedUp(orderId: order.id)),
                        icon: const Icon(Icons.inventory_2_outlined, size: 18),
                        label: const Text('Picked Up'),
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () => context.read<OrderBloc>().add(CustomerConfirmDelivered(orderId: order.id)),
                      icon: const Icon(Icons.done_all, size: 18),
                      label: const Text('Received'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.secondary,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
