// ══════════════════════════════════════════════════════════════
// Vendra Customer App - Post-delivery inspection window (FR08)
// After delivery the payment stays in escrow for the policy's dispute
// window (escrowReleaseDueAt). This badge counts it down so the customer
// knows how long they have to report damaged or missing items before the
// store is paid. Hidden once the window closes or the escrow settles.
// ══════════════════════════════════════════════════════════════

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:vendra_customer/vendra_core.dart';

/// When the order's inspection window closes, or null when there is none to show
DateTime? disputeWindowEnd(OrderModel order, [DateTime? now]) {
  final due = order.escrowReleaseDueAt;
  if (order.status != 'delivered' || order.escrowStatus != 'held' || due == null) return null;
  return due.isAfter(now ?? DateTime.now()) ? due : null;
}

/// "23 hrs 40 mins", "40 mins", "under a minute"
String formatWindowLeft(Duration d) {
  if (d.inMinutes < 1) return 'under a minute';
  final hours = d.inHours;
  final minutes = d.inMinutes % 60;
  final h = hours == 1 ? '1 hr' : '$hours hrs';
  final m = minutes == 1 ? '1 min' : '$minutes mins';
  if (hours == 0) return m;
  return minutes == 0 ? h : '$h $m';
}

class DisputeWindowBadge extends StatefulWidget {
  final OrderModel order;

  const DisputeWindowBadge({super.key, required this.order});

  @override
  State<DisputeWindowBadge> createState() => _DisputeWindowBadgeState();
}

class _DisputeWindowBadgeState extends State<DisputeWindowBadge> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    // Minute precision is enough; tick a little faster so the last minute isn't stale
    _ticker = Timer.periodic(const Duration(seconds: 20), (_) {
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
    final now = DateTime.now();
    final end = disputeWindowEnd(widget.order, now);
    if (end == null) return const SizedBox.shrink();

    final left = end.difference(now);
    final windowMinutes = AppConfig.current.disputeWindowMinutes;
    final fraction = windowMinutes > 0 ? (left.inSeconds / (windowMinutes * 60)).clamp(0.0, 1.0) : null;
    final color = AppColors.secondary;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.fact_check_outlined, size: 22, color: color),
              const SizedBox(width: 10),
              Expanded(
                child: Text.rich(
                  TextSpan(children: [
                    const TextSpan(text: 'Inspection window active: ', style: TextStyle(fontWeight: FontWeight.w600)),
                    TextSpan(
                      text: formatWindowLeft(left),
                      style: const TextStyle(fontWeight: FontWeight.w700, fontFeatures: [FontFeature.tabularFigures()]),
                    ),
                    const TextSpan(text: ' remaining to report issues'),
                  ]),
                  style: TextStyle(fontSize: 13, color: AppColors.textPrimary),
                ),
              ),
            ],
          ),
          if (fraction != null) ...[
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: fraction,
                minHeight: 5,
                color: color,
                backgroundColor: color.withValues(alpha: 0.15),
              ),
            ),
          ],
          const SizedBox(height: 8),
          Text(
            'Check your items now. Damaged or missing goods reported before the window closes keep the '
            'payment frozen in escrow until an admin reviews it.',
            style: TextStyle(fontSize: 11, height: 1.4, color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }
}
