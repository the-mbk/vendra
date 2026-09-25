// ══════════════════════════════════════════════════════════════
// Vendra Customer App - Order status building blocks
// Escrow status (FR03), rider details (FR04/FR07) and dispute
// status (FR08) shown on the order list and the tracking screen.
// ══════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:vendra_customer/vendra_core.dart';

final _when = DateFormat('d MMM, h:mm a');

/// Colour for an order status chip
Color orderStatusColor(OrderModel order) {
  switch (order.status) {
    case 'pending':
      return Colors.orange;
    case 'confirmed':
      return AppColors.secondary;
    case 'packed':
      return Colors.indigo;
    case 'ready_for_pickup':
      return order.isDelivery && order.rider == null ? Colors.amber.shade800 : Colors.teal;
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

/// Customer-facing explanation of where the money is right now
String escrowDetailText(OrderModel order) {
  switch (order.escrowStatus) {
    case 'held':
      final due = order.escrowReleaseDueAt;
      if (order.status == 'delivered' && due != null) {
        if (due.isBefore(DateTime.now())) {
          return 'Dispute window closed — releasing to the store shortly.';
        }
        return 'Releases to the store on ${_when.format(due)} unless you report an issue.';
      }
      if (order.status == 'delivered') {
        return 'Held until the dispute window closes.';
      }
      return 'Held safely until your order is delivered.';
    case 'disputed':
      return 'Frozen while an admin reviews your dispute.';
    case 'released':
      return 'Released to the store — this order is settled.';
    case 'refunded':
      return 'Refunded to your Vendra wallet.';
    default:
      return 'Processing payment…';
  }
}

IconData escrowIcon(String? escrowStatus) {
  switch (escrowStatus) {
    case 'disputed':
      return Icons.gavel_outlined;
    case 'released':
      return Icons.check_circle_outline;
    case 'refunded':
      return Icons.replay_circle_filled_outlined;
    default:
      return Icons.lock_outline;
  }
}

Color escrowColor(String? escrowStatus) {
  switch (escrowStatus) {
    case 'disputed':
      return AppColors.reservedAmber;
    case 'released':
      return Colors.teal.shade600;
    case 'refunded':
      return AppColors.secondary;
    default:
      return AppColors.stockGreen;
  }
}

/// Label for a dispute summary on an order
String disputeIssueLabel(String? issueType) =>
    DisputeModel.issueTypes[issueType] ?? (issueType ?? 'Issue').replaceAll('_', ' ');

/// Customer wording for a dispute outcome
String disputeOutcomeText(DisputeSummary d) {
  if (d.status == 'open') return 'Under review — payment is on hold';
  if (d.resolution == 'refund') return 'Resolved — refunded to your wallet';
  return 'Resolved — payment released to the store';
}

/// Compact escrow line for list tiles
class EscrowStatusLine extends StatelessWidget {
  final OrderModel order;
  const EscrowStatusLine({super.key, required this.order});

  @override
  Widget build(BuildContext context) {
    final color = escrowColor(order.escrowStatus);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(escrowIcon(order.escrowStatus), size: 16, color: color),
        const SizedBox(width: 6),
        Expanded(
          child: Text.rich(
            TextSpan(children: [
              TextSpan(text: '${order.escrowStatusText}. ', style: const TextStyle(fontWeight: FontWeight.w600)),
              TextSpan(text: escrowDetailText(order)),
            ]),
            style: GoogleFonts.poppins(fontSize: 11, color: color),
          ),
        ),
      ],
    );
  }
}

/// Escrow card for the tracking screen (mirrors the "Secure Escrow Payment" mockup card)
class EscrowStatusCard extends StatelessWidget {
  final OrderModel order;
  const EscrowStatusCard({super.key, required this.order});

  @override
  Widget build(BuildContext context) {
    final color = escrowColor(order.escrowStatus);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: cardDecoration(),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(12)),
            child: Icon(escrowIcon(order.escrowStatus), color: Colors.white, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        order.escrowStatusText,
                        style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
                      ),
                    ),
                    Text(
                      'Rs. ${order.totalAmount.toStringAsFixed(0)}',
                      style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.primary),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(escrowDetailText(order), style: GoogleFonts.poppins(fontSize: 12, color: AppColors.textSecondary)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Rider name + phone once a rider has accepted the delivery
class RiderInfoCard extends StatelessWidget {
  final OrderRider rider;
  final DateTime? lastSeen;
  const RiderInfoCard({super.key, required this.rider, this.lastSeen});

  @override
  Widget build(BuildContext context) {
    final phone = rider.phone;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: cardDecoration(),
      child: Row(
        children: [
          CircleAvatar(
            radius: 24,
            backgroundColor: AppColors.secondary.withValues(alpha: 0.12),
            child: const Icon(Icons.delivery_dining, color: AppColors.secondary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(rider.name ?? 'Your rider', style: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w600)),
                Text(
                  phone != null && phone.isNotEmpty ? phone : 'Vendra rider',
                  style: GoogleFonts.poppins(fontSize: 12, color: AppColors.textSecondary),
                ),
                if (lastSeen != null)
                  Text(
                    'Location updated ${DateFormat('h:mm:ss a').format(lastSeen!)}',
                    style: GoogleFonts.poppins(fontSize: 10, color: AppColors.textLight),
                  ),
              ],
            ),
          ),
          if (phone != null && phone.isNotEmpty)
            IconButton.filled(
              tooltip: 'Call rider',
              style: IconButton.styleFrom(backgroundColor: AppColors.secondary, foregroundColor: Colors.white),
              // Opens the dialer; copies the number where calling isn't possible
              onPressed: () => ContactLauncher.call(context, phone),
              icon: const Icon(Icons.call_outlined, size: 20),
            ),
        ],
      ),
    );
  }
}

/// Dispute status on an order, or the "Report an issue" entry point when allowed
class OrderDisputeSection extends StatelessWidget {
  final OrderModel order;
  final VoidCallback? onReport;
  final VoidCallback? onViewDisputes;
  final bool compact;

  const OrderDisputeSection({
    super.key,
    required this.order,
    this.onReport,
    this.onViewDisputes,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final d = order.latestDispute;
    if (d != null) {
      final open = d.status == 'open';
      final color = open ? AppColors.reservedAmber : (d.resolution == 'refund' ? AppColors.secondary : Colors.teal.shade700);
      return InkWell(
        onTap: onViewDisputes,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: color.withValues(alpha: 0.35)),
          ),
          child: Row(
            children: [
              Icon(Icons.gavel_outlined, color: color, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Dispute: ${disputeIssueLabel(d.issueType)}',
                      style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
                    ),
                    Text(disputeOutcomeText(d), style: GoogleFonts.poppins(fontSize: 11, color: color)),
                  ],
                ),
              ),
              if (onViewDisputes != null) Icon(Icons.chevron_right, color: color),
            ],
          ),
        ),
      );
    }

    if (!order.canDispute || onReport == null) return const SizedBox.shrink();

    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: onReport,
        icon: const Icon(Icons.report_problem_outlined, size: 18),
        label: Text(compact ? 'Report an issue' : 'Something wrong? Report an issue'),
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.error,
          side: BorderSide(color: AppColors.error.withValues(alpha: 0.6)),
        ),
      ),
    );
  }
}

BoxDecoration cardDecoration() => BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8, offset: const Offset(0, 2))],
    );
