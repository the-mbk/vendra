// ══════════════════════════════════════════════════════════════
// Vendra Rider App - Past delivery details (FR04)
// Opened by tapping a delivery in Earnings → History: route, when it was
// delivered, the customer's rating and the itemised payout slip.
// ══════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:vendra_rider/vendra_core.dart';

import '../models/rider_models.dart';
import 'payout_slip.dart';

final _dateFmt = DateFormat('d MMM yyyy, h:mm a');

Future<void> showDeliverySlip(BuildContext context, RiderOrder order) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (context) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.75,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      builder: (context, controller) => DeliverySlipView(order: order, controller: controller),
    ),
  );
}

class DeliverySlipView extends StatelessWidget {
  final RiderOrder order;
  final ScrollController? controller;
  const DeliverySlipView({super.key, required this.order, this.controller});

  @override
  Widget build(BuildContext context) {
    final o = order;
    final when = o.deliveredAt ?? o.assignedAt;
    return ListView(
      controller: controller,
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      children: [
        Text('Delivery #${o.id}',
            style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
        if (when != null)
          Text('${o.isDelivered ? 'Delivered' : o.statusText} · ${_dateFmt.format(when)}',
              style: GoogleFonts.poppins(fontSize: 12, color: AppColors.textSecondary)),
        const SizedBox(height: 14),
        _line(Icons.storefront, AppColors.secondary, 'From', o.storeName ?? 'Store'),
        _line(Icons.home_outlined, AppColors.success, 'To', o.deliveryAddress ?? o.customerName ?? 'Customer'),
        const SizedBox(height: 6),
        Row(
          children: [
            Text('Customer rating', style: GoogleFonts.poppins(fontSize: 13, color: AppColors.textSecondary)),
            const Spacer(),
            if (o.customerRating != null)
              RatingStars(rating: o.customerRating!.toDouble(), size: 18)
            else
              Text('Not rated yet', style: GoogleFonts.poppins(fontSize: 13, color: AppColors.textLight)),
          ],
        ),
        const SizedBox(height: 16),
        if (o.isDelivered)
          PayoutSlip(breakdown: o.payoutBreakdown, total: o.payout)
        else
          Text('No payout: this order was ${o.statusText.toLowerCase()}.',
              style: GoogleFonts.poppins(fontSize: 13, color: AppColors.textSecondary)),
      ],
    );
  }

  Widget _line(IconData icon, Color color, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 10),
          SizedBox(
            width: 40,
            child: Text(label, style: GoogleFonts.poppins(fontSize: 13, color: AppColors.textSecondary)),
          ),
          Expanded(
            child: Text(value,
                style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
          ),
        ],
      ),
    );
  }
}
