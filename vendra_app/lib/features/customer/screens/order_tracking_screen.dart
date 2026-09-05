// ══════════════════════════════════════════════════════════════
// Order tracking — live timeline + self pickup confirmations
// ══════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../config/app_theme.dart';
import '../../../core/models/order_model.dart';
import '../bloc/order_bloc.dart';

class OrderTrackingScreen extends StatefulWidget {
  final OrderModel order;
  const OrderTrackingScreen({super.key, required this.order});

  @override
  State<OrderTrackingScreen> createState() => _OrderTrackingScreenState();
}

class _OrderTrackingScreenState extends State<OrderTrackingScreen> {
  late OrderModel _order;

  @override
  void initState() {
    super.initState();
    _order = widget.order;
  }

  void _applyOrdersLoaded(OrdersLoaded state) {
    for (final o in state.orders) {
      if (o.id == _order.id) {
        if (mounted) setState(() => _order = o);
        break;
      }
    }
  }

  double _overallProgress() {
    switch (_order.status) {
      case 'pending':
        return 0.12;
      case 'confirmed':
        return 0.28;
      case 'packed':
        return 0.44;
      case 'ready_for_pickup':
        return 0.62;
      case 'picked':
        return 0.78;
      case 'delivered':
        return 1.0;
      default:
        return 0;
    }
  }

  String _etaLine() {
    if (_order.deliveryType == 'delivery' && _order.estimatedMinutes != null) {
      return '~${_order.estimatedMinutes} min after rider pickup (coming soon)';
    }
    if (_order.deliveryType == 'self_pickup') {
      return 'Collect from store when status is Ready for Pickup';
    }
    return '—';
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<OrderBloc, OrderState>(
      listenWhen: (p, c) => c is OrdersLoaded,
      listener: (context, state) {
        final s = state as OrdersLoaded;
        _applyOrdersLoaded(s);
      },
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          title: Text('Track Order', style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
          centerTitle: true,
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: () => context.read<OrderBloc>().add(const FetchCustomerOrders(silent: true)),
            ),
          ],
        ),
        body: RefreshIndicator(
          color: AppColors.primary,
          onRefresh: () async {
            context.read<OrderBloc>().add(const FetchCustomerOrders(silent: true));
          },
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildOrderHeader(),
                const SizedBox(height: 16),
                _buildEscrowBadge(),
                const SizedBox(height: 16),
                _buildTimeline(),
                const SizedBox(height: 16),
                _buildDeliveryNotice(),
                const SizedBox(height: 16),
                _buildCustomerActions(context),
                const SizedBox(height: 16),
                _buildOrderSummary(),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildOrderHeader() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppColors.secondary, Color(0xFF1A6DB5)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Order Number', style: GoogleFonts.poppins(fontSize: 12, color: Colors.white70)),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _order.deliveryType == 'self_pickup' ? Icons.storefront_outlined : Icons.local_shipping_outlined,
                      size: 14,
                      color: Colors.white,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      _order.statusText,
                      style: GoogleFonts.poppins(fontSize: 11, color: Colors.white, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '#VDR-${_order.id.toString().padLeft(5, '0')}',
            style: GoogleFonts.poppins(fontSize: 28, fontWeight: FontWeight.w700, color: Colors.white),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                const Icon(Icons.schedule, size: 18, color: Colors.white70),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Timing', style: GoogleFonts.poppins(fontSize: 11, color: Colors.white60)),
                      Text(_etaLine(), style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.white)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEscrowBadge() {
    final released = _order.status == 'delivered';
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: released ? Colors.teal.shade600 : AppColors.stockGreen,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(released ? Icons.check_circle_outline : Icons.lock_outline, color: Colors.white, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      released ? 'Escrow settled' : 'Secure escrow',
                      style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
                    ),
                    const Spacer(),
                    Text('Rs. ${_order.totalAmount.toStringAsFixed(0)}',
                        style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.primary)),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  released
                      ? 'Vendor has been paid for this order.'
                      : _order.deliveryType == 'self_pickup'
                          ? 'Payment stays in escrow until you mark the order as delivered after pickup.'
                          : 'Payment stays in escrow until rider delivery completes (module coming soon).',
                  style: GoogleFonts.poppins(fontSize: 12, color: AppColors.textSecondary),
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: _overallProgress(),
                    minHeight: 6,
                    backgroundColor: Colors.grey.shade200,
                    valueColor: AlwaysStoppedAnimation<Color>(released ? Colors.teal.shade600 : AppColors.stockGreen),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTimeline() {
    if (_order.status == 'cancelled') {
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8, offset: const Offset(0, 2))],
        ),
        child: Row(
          children: [
            Icon(Icons.cancel_outlined, color: AppColors.stockRed),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                _order.statusText,
                style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      );
    }

    final steps = [
      _TimelineStep(
        'Order placed',
        'Payment captured into escrow.',
        _stepDone(0),
        _stepActive(0),
      ),
      _TimelineStep(
        'Confirmed by vendor',
        'The store accepted your order.',
        _stepDone(1),
        _stepActive(1),
      ),
      _TimelineStep(
        'Preparing',
        'Your items are being prepared.',
        _stepDone(2),
        _stepActive(2),
      ),
      _TimelineStep(
        'Ready for pickup',
        _order.deliveryType == 'delivery'
            ? 'Awaiting rider — vendor may still prepare the order.'
            : 'Head to the store when you see this step.',
        _stepDone(3),
        _stepActive(3),
      ),
      _TimelineStep(
        'Delivered',
        _order.deliveryType == 'delivery'
            ? 'Completes automatically once rider delivery goes live.'
            : 'Tap “Mark as Delivered” after you collect your bags.',
        _stepDone(4),
        _stepActive(4),
      ),
    ];

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Progress', style: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w600)),
          const SizedBox(height: 12),
          ...List.generate(steps.length, (index) {
            final step = steps[index];
            final isLast = index == steps.length - 1;
            return IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 32,
                    child: Column(
                      children: [
                        Container(
                          width: 24,
                          height: 24,
                          decoration: BoxDecoration(
                            color: step.completed
                                ? AppColors.stockGreen
                                : step.active
                                    ? AppColors.primary
                                    : Colors.grey.shade200,
                            shape: BoxShape.circle,
                            border: step.active && !step.completed
                                ? Border.all(color: AppColors.primary, width: 3)
                                : null,
                          ),
                          child: step.completed
                              ? const Icon(Icons.check, color: Colors.white, size: 14)
                              : step.active
                                  ? Container(
                                      margin: const EdgeInsets.all(5),
                                      decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                                    )
                                  : null,
                        ),
                        if (!isLast)
                          Expanded(
                            child: Container(
                              width: 2,
                              color: step.completed ? AppColors.stockGreen : Colors.grey.shade200,
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Padding(
                      padding: EdgeInsets.only(bottom: isLast ? 0 : 20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            step.title,
                            style: GoogleFonts.poppins(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: step.active || step.completed ? AppColors.textPrimary : AppColors.textLight,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(step.subtitle, style: GoogleFonts.poppins(fontSize: 12, color: AppColors.textSecondary)),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  int _stepIndex() {
    switch (_order.status) {
      case 'pending':
        return 0;
      case 'confirmed':
        return 1;
      case 'packed':
        return 2;
      case 'ready_for_pickup':
        return 3;
      case 'picked':
        return 4;
      case 'delivered':
        return 5;
      default:
        return 0;
    }
  }

  bool _stepDone(int step) => _stepIndex() > step;

  bool _stepActive(int step) => _stepIndex() == step;

  Widget _buildDeliveryNotice() {
    if (_order.deliveryType != 'delivery') return const SizedBox.shrink();
    if (_order.status == 'delivered') return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.blueGrey.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.blueGrey.shade100),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, color: Colors.blueGrey.shade700),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Home delivery: “Mark as Delivered” stays disabled until the rider module is connected. Your payment remains safe in escrow.',
              style: GoogleFonts.poppins(fontSize: 12, color: Colors.blueGrey.shade900),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCustomerActions(BuildContext context) {
    if (_order.deliveryType != 'self_pickup') return const SizedBox.shrink();
    if (_order.status == 'delivered' || _order.status == 'cancelled') return const SizedBox.shrink();

    final bloc = context.read<OrderBloc>();

    if (_order.status == 'ready_for_pickup') {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Confirm pickup', style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () => bloc.add(CustomerMarkPickedUp(orderId: _order.id)),
            icon: const Icon(Icons.inventory_2_outlined),
            label: const Text('Mark as Picked Up'),
          ),
          const SizedBox(height: 8),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.secondary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            onPressed: () => bloc.add(CustomerConfirmDelivered(orderId: _order.id)),
            icon: const Icon(Icons.done_all),
            label: const Text('Mark as Delivered'),
          ),
        ],
      );
    }

    if (_order.status == 'picked') {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Almost done', style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.secondary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            onPressed: () => bloc.add(CustomerConfirmDelivered(orderId: _order.id)),
            icon: const Icon(Icons.done_all),
            label: const Text('Mark as Delivered'),
          ),
        ],
      );
    }

    return const SizedBox.shrink();
  }

  Widget _buildOrderSummary() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Order summary', style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w600)),
          const SizedBox(height: 16),
          ..._order.items.map((item) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppColors.secondary.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text('${item.quantity}×',
                          style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.secondary)),
                    ),
                    const SizedBox(width: 12),
                    Expanded(child: Text(item.productName ?? '', style: GoogleFonts.poppins(fontSize: 14))),
                    Text('Rs. ${(item.unitPrice * item.quantity).toStringAsFixed(0)}',
                        style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w500)),
                  ],
                ),
              )),
          const Divider(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Total charged', style: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w600)),
              Text(
                'Rs. ${_order.totalAmount.toStringAsFixed(0)}',
                style: GoogleFonts.poppins(fontSize: 20, fontWeight: FontWeight.w700, color: AppColors.primary),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TimelineStep {
  final String title;
  final String subtitle;
  final bool completed;
  final bool active;

  _TimelineStep(this.title, this.subtitle, this.completed, this.active);
}
