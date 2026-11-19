// ══════════════════════════════════════════════════════════════
// Vendra Rider App - Pickup deadline (task hoarding guard)
// After accepting, the rider has `riderPickupTimeoutMinutes` to reach the
// store; otherwise the server gives the delivery to other riders and it
// counts against this rider. Arriving at the store stops the clock and
// starts the store wait limit (`riderStoreWaitMaxMinutes`): collect within
// it, or the delivery goes to another rider with no waiting pay.
// ══════════════════════════════════════════════════════════════

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:vendra_rider/vendra_core.dart';

import '../models/rider_models.dart';

/// When the rider must be at the store by (null once arrived, or with no deadline)
DateTime? pickupDeadline(RiderOrder order, int timeoutMinutes) {
  if (timeoutMinutes <= 0 || order.assignedAt == null || order.step != DeliveryStep.headingToStore) return null;
  return order.assignedAt!.add(Duration(minutes: timeoutMinutes));
}

/// Time left to collect after checking in at the store (zero once passed; null with no limit)
Duration? storeWaitLeft(DateTime arrivedAt, int limitMinutes, DateTime now) {
  if (limitMinutes <= 0) return null;
  final left = arrivedAt.add(Duration(minutes: limitMinutes)).difference(now);
  return left.isNegative ? Duration.zero : left;
}

class PickupDeadlineCard extends StatefulWidget {
  final DateTime deadline;
  const PickupDeadlineCard({super.key, required this.deadline});

  @override
  State<PickupDeadlineCard> createState() => _PickupDeadlineCardState();
}

class _PickupDeadlineCardState extends State<PickupDeadlineCard> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final left = widget.deadline.difference(DateTime.now());
    final passed = left <= Duration.zero;
    final urgent = left < const Duration(minutes: 3);
    final color = passed || urgent ? AppColors.error : AppColors.warning;
    final mm = left.inMinutes.toString().padLeft(2, '0');
    final ss = (left.inSeconds % 60).toString().padLeft(2, '0');

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          Icon(Icons.schedule_rounded, size: 26, color: color),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  passed ? 'Pickup deadline passed' : 'Reach the store by ${DateFormat.jm().format(widget.deadline.toLocal())}',
                  style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
                ),
                const SizedBox(height: 2),
                Text(
                  passed
                      ? 'This delivery is being offered to other riders.'
                      : '$mm:$ss left. Tap "Arrived at store" when you get there, or it goes to another rider.',
                  style: GoogleFonts.poppins(fontSize: 12, color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
