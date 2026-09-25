// ══════════════════════════════════════════════════════════════
// Vendra App - Vendor Orders Screen (FR07)
// Two tabs:
//   Active   every in-progress order, with approve/reject, pack and
//            ready-for-pickup. Delivery orders are handed to riders (who
//            mark them delivered); self-pickup orders can be marked
//            delivered here.
//   History  delivered / cancelled orders, paged — more load as you scroll.
// Cards show the customer and rider (tap to call), the escrow status and
// any dispute. Orders update live: each order:update event or order
// notification re-reads just that order and moves it between the tabs.
// ══════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:vendra_vendor/vendra_core.dart';
import '../bloc/vendor_order_bloc.dart';
import '../../auth/bloc/auth_bloc.dart';
import '../../auth/bloc/auth_event.dart';
import 'vendor_disputes_screen.dart';

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
    return DefaultTabController(
      length: 2,
      child: SafeArea(
        bottom: false,
        child: BlocConsumer<VendorOrderBloc, VendorOrderState>(
          listener: (context, state) {
            // The bloc re-reads the order itself after every action
            if (state is VendorOrderActionSuccess) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(state.message),
                  backgroundColor: AppColors.success,
                  behavior: SnackBarBehavior.floating,
                ),
              );
              context.read<AuthBloc>().add(RefreshUserRequested());
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
            final bloc = context.read<VendorOrderBloc>();
            final activeCount = bloc.hasLoaded ? bloc.activeOrders.length : null;

            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: Text('Orders', style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.w600)),
                ),
                TabBar(
                  labelColor: AppColors.secondary,
                  indicatorColor: AppColors.secondary,
                  unselectedLabelColor: AppColors.textSecondary,
                  labelStyle: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w600),
                  tabs: [
                    Tab(text: activeCount == null ? 'Active' : 'Active ($activeCount)'),
                    const Tab(text: 'History'),
                  ],
                ),
                Expanded(
                  child: !bloc.hasLoaded
                      ? (state is VendorOrderError
                          ? _errorView(context, state.message)
                          : const Center(child: CircularProgressIndicator(color: AppColors.primary)))
                      : TabBarView(
                          children: [
                            _activeTab(context, bloc),
                            _historyTab(context, bloc),
                          ],
                        ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Future<void> _refresh(BuildContext context) async {
    context.read<VendorOrderBloc>().add(const FetchVendorOrders(silent: true));
  }

  Widget _errorView(BuildContext context, String message) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(message, textAlign: TextAlign.center, style: GoogleFonts.poppins(color: AppColors.textSecondary)),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: () => context.read<VendorOrderBloc>().add(const FetchVendorOrders()),
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _emptyList(BuildContext context, String text) {
    return RefreshIndicator(
      onRefresh: () => _refresh(context),
      child: ListView(
        children: [
          const SizedBox(height: 120),
          Icon(Icons.receipt_long_outlined, size: 64, color: Colors.grey.shade300),
          const SizedBox(height: 16),
          Center(child: Text(text, style: GoogleFonts.poppins(color: AppColors.textSecondary))),
        ],
      ),
    );
  }

  Widget _activeTab(BuildContext context, VendorOrderBloc bloc) {
    final orders = bloc.activeOrders;
    if (orders.isEmpty) return _emptyList(context, 'No orders in progress');
    return RefreshIndicator(
      onRefresh: () => _refresh(context),
      child: ListView.builder(
        key: const PageStorageKey('vendor-orders-active'),
        padding: const EdgeInsets.all(16),
        itemCount: orders.length,
        itemBuilder: (context, index) => _orderCard(context, orders[index]),
      ),
    );
  }

  Widget _historyTab(BuildContext context, VendorOrderBloc bloc) {
    final orders = bloc.historyOrders;
    if (orders.isEmpty && !bloc.hasMoreHistory) {
      return _emptyList(context, 'No completed or cancelled orders yet');
    }
    return RefreshIndicator(
      onRefresh: () => _refresh(context),
      child: NotificationListener<ScrollNotification>(
        // Infinite scroll: fetch the next page when near the bottom
        onNotification: (n) {
          if (n.metrics.extentAfter < 400 && bloc.hasMoreHistory && !bloc.isLoadingMoreHistory && bloc.historyError == null) {
            bloc.add(const LoadMoreVendorOrderHistory());
          }
          return false;
        },
        child: ListView.builder(
          key: const PageStorageKey('vendor-orders-history'),
          padding: const EdgeInsets.all(16),
          itemCount: orders.length + 1,
          itemBuilder: (context, index) {
            if (index < orders.length) return _orderCard(context, orders[index]);
            return _historyFooter(context, bloc);
          },
        ),
      ),
    );
  }

  /// Spinner while loading, a "Load more" button (also the retry after an error), or the end
  Widget _historyFooter(BuildContext context, VendorOrderBloc bloc) {
    Widget child;
    if (bloc.isLoadingMoreHistory) {
      child = const SizedBox(
        width: 24,
        height: 24,
        child: CircularProgressIndicator(strokeWidth: 2.5, color: AppColors.primary),
      );
    } else if (bloc.hasMoreHistory) {
      child = Column(
        children: [
          if (bloc.historyError != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(bloc.historyError!,
                  textAlign: TextAlign.center, style: GoogleFonts.poppins(fontSize: 12, color: AppColors.error)),
            ),
          OutlinedButton.icon(
            onPressed: () => bloc.add(const LoadMoreVendorOrderHistory()),
            icon: const Icon(Icons.expand_more, size: 18),
            label: Text(bloc.historyError != null ? 'Try again' : 'Load more'),
          ),
        ],
      );
    } else {
      child = Text('That\'s all your past orders',
          style: GoogleFonts.poppins(fontSize: 12, color: AppColors.textLight));
    }
    return Padding(padding: const EdgeInsets.symmetric(vertical: 12), child: Center(child: child));
  }

  Widget _orderCard(BuildContext context, OrderModel order) {
    final isPending = order.status == 'pending';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: isPending
            ? Border.all(color: Colors.orange.shade300, width: 1.5)
            : (order.hasOpenDispute ? Border.all(color: AppColors.stockRed.withValues(alpha: 0.5), width: 1.5) : null),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8)],
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
              Flexible(
                child: Container(
                  margin: const EdgeInsets.only(left: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: _statusColor(order.status).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    order.statusText,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w600, color: _statusColor(order.status)),
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 6),

          // Escrow + dispute badges
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              _escrowBadge(order),
              if (order.latestDispute != null) _disputeBadge(context, order),
            ],
          ),

          const SizedBox(height: 8),

          // Customer name + phone (tap to call)
          Row(
            children: [
              const Icon(Icons.person_outline, size: 16, color: AppColors.textSecondary),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  order.customerName ?? 'Customer',
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.poppins(fontSize: 13, color: AppColors.textSecondary),
                ),
              ),
              PhoneAction(phone: order.customerPhone),
            ],
          ),

          const SizedBox(height: 4),

          // Delivery type
          Row(
            children: [
              Icon(order.isDelivery ? Icons.delivery_dining : Icons.store, size: 16, color: AppColors.secondary),
              const SizedBox(width: 6),
              Text(
                order.deliveryTypeText,
                style: GoogleFonts.poppins(fontSize: 12, color: AppColors.secondary, fontWeight: FontWeight.w500),
              ),
              if (order.estimatedMinutes != null) ...[
                const SizedBox(width: 8),
                Text('~${order.estimatedMinutes} min', style: GoogleFonts.poppins(fontSize: 11, color: AppColors.textLight)),
              ],
            ],
          ),
          if (order.isDelivery && order.deliveryAddress != null)
            Padding(
              padding: const EdgeInsets.only(left: 22, top: 2),
              child: Text(order.deliveryAddress!, style: GoogleFonts.poppins(fontSize: 11, color: AppColors.textLight)),
            ),

          // Rider (delivery orders)
          if (order.isDelivery) _riderInfo(order),

          const SizedBox(height: 6),

          // Items
          for (final item in order.items)
            Text('${item.quantity} × ${item.productName ?? 'Product #${item.productId}'}',
                style: GoogleFonts.poppins(fontSize: 12, color: AppColors.textSecondary)),

          const Divider(height: 16),

          // Bottom row: date + total
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              if (order.createdAt != null)
                Flexible(
                  child: Text(
                    DateFormat('MMM dd, hh:mm a').format(DateTime.parse(order.createdAt!).toLocal()),
                    style: GoogleFonts.poppins(fontSize: 12, color: AppColors.textLight),
                  ),
                ),
              Text(
                'Rs. ${order.totalAmount.toStringAsFixed(0)}',
                style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.primary),
              ),
            ],
          ),

          ..._actions(context, order),
        ],
      ),
    );
  }

  // ── Escrow status (FR03) ──
  Widget _escrowBadge(OrderModel order) {
    Color color;
    IconData icon;
    switch (order.escrowStatus) {
      case 'held':
        color = Colors.green.shade700;
        icon = Icons.lock_outline;
        break;
      case 'disputed':
        color = AppColors.stockRed;
        icon = Icons.lock_clock;
        break;
      case 'released':
        color = AppColors.secondary;
        icon = Icons.account_balance_wallet_outlined;
        break;
      case 'refunded':
        color = Colors.grey.shade700;
        icon = Icons.undo;
        break;
      default:
        color = Colors.grey;
        icon = Icons.hourglass_empty;
    }
    var text = order.escrowStatusText;
    if (order.escrowStatus == 'held' && order.escrowReleaseDueAt != null) {
      text += ' · releases ${DateFormat('MMM dd, h:mm a').format(order.escrowReleaseDueAt!)}';
    }
    return _badge(text, icon, color);
  }

  // ── Dispute badge (FR08) ──
  Widget _disputeBadge(BuildContext context, OrderModel order) {
    final d = order.latestDispute!;
    final open = d.status == 'open';
    final text = open
        ? 'Dispute open'
        : (d.resolution == 'refund' ? 'Dispute resolved · refunded' : 'Dispute resolved · released');
    return InkWell(
      borderRadius: BorderRadius.circular(6),
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => VendorDisputesScreen(highlightOrderId: order.id)),
      ),
      child: _badge(text, Icons.gavel_outlined, open ? AppColors.stockRed : AppColors.reservedAmber),
    );
  }

  Widget _badge(String text, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Flexible(
            child: Text(text, style: GoogleFonts.poppins(fontSize: 10, color: color, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  // ── Rider assignment (delivery orders) ──
  Widget _riderInfo(OrderModel order) {
    final rider = order.rider;
    if (rider != null) {
      return Container(
        margin: const EdgeInsets.only(top: 8),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(color: Colors.deepPurple.shade50, borderRadius: BorderRadius.circular(10)),
        child: Row(
          children: [
            Icon(Icons.two_wheeler, size: 18, color: Colors.deepPurple.shade400),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Rider: ${rider.name ?? 'Assigned'}',
                      style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.deepPurple.shade700)),
                ],
              ),
            ),
            // Tap to call the rider
            PhoneAction(phone: rider.phone),
          ],
        ),
      );
    }
    if (order.status == 'ready_for_pickup') {
      return Container(
        margin: const EdgeInsets.only(top: 8),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(color: Colors.teal.shade50, borderRadius: BorderRadius.circular(10)),
        child: Row(
          children: [
            Icon(Icons.wifi_tethering, size: 18, color: Colors.teal.shade600),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Nearby riders have been notified — waiting for one to accept.',
                style: GoogleFonts.poppins(fontSize: 12, color: Colors.teal.shade700),
              ),
            ),
          ],
        ),
      );
    }
    return const SizedBox.shrink();
  }

  // ── Workflow buttons ──
  List<Widget> _actions(BuildContext context, OrderModel order) {
    final bloc = context.read<VendorOrderBloc>();

    if (order.status == 'pending') {
      return [
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => _showRejectConfirmation(context, order.id),
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
                onPressed: () => bloc.add(ApproveVendorOrder(orderId: order.id)),
                icon: const Icon(Icons.check, size: 18),
                label: Text('Approve', style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
                style: _buttonStyle(AppColors.stockGreen),
              ),
            ),
          ],
        ),
      ];
    }

    if (order.status == 'confirmed') {
      return [
        const SizedBox(height: 12),
        _fullWidthButton(
          label: 'Mark as Packed',
          icon: Icons.inventory_outlined,
          color: Colors.indigo,
          onPressed: () => bloc.add(MarkOrderPreparing(orderId: order.id)),
        ),
      ];
    }

    if (order.status == 'packed') {
      return [
        const SizedBox(height: 12),
        _fullWidthButton(
          label: 'Mark as Ready for Pickup',
          icon: Icons.storefront_outlined,
          color: AppColors.primary,
          onPressed: () => bloc.add(MarkOrderReadyForPickup(orderId: order.id, isDelivery: order.isDelivery)),
        ),
        _hint(order.isDelivery
            ? 'Nearby riders will be notified to collect this order.'
            : 'The customer will be notified to collect this order.'),
      ];
    }

    // Self pickup: the store hands the order over and marks it delivered
    if (!order.isDelivery && (order.status == 'ready_for_pickup' || order.status == 'picked')) {
      return [
        const SizedBox(height: 12),
        _fullWidthButton(
          label: 'Mark as Delivered',
          icon: Icons.done_all,
          color: Colors.teal.shade700,
          onPressed: () => bloc.add(DeliverVendorOrder(orderId: order.id)),
        ),
        _hint('Completes the order. Payment is released to your wallet after the dispute window.'),
      ];
    }

    // Delivery: riders pick up and deliver (geofenced) — no vendor action
    if (order.isDelivery && (order.status == 'picked' || order.status == 'on_the_way')) {
      return [_hint('The rider will mark this order delivered at the customer\'s location.')];
    }

    return const [];
  }

  ButtonStyle _buttonStyle(Color color) => ElevatedButton.styleFrom(
        backgroundColor: color,
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        padding: const EdgeInsets.symmetric(vertical: 10),
      );

  Widget _fullWidthButton({
    required String label,
    required IconData icon,
    required Color color,
    required VoidCallback onPressed,
  }) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 18),
        label: Text(label, style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
        style: _buttonStyle(color),
      ),
    );
  }

  Widget _hint(String text) => Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Text(text, style: GoogleFonts.poppins(fontSize: 11, color: AppColors.textSecondary)),
      );

  void _showRejectConfirmation(BuildContext context, int orderId) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Reject Order?', style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
        content: Text(
          'This will cancel the order, refund the customer and release the reserved stock. This action cannot be undone.',
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
