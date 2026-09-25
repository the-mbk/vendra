// ══════════════════════════════════════════════════════════════
// Vendra Rider App - Incoming task card (Stitch rider home mockup)
// Pickup → drop-off route, distances, estimated payout, Accept/Decline.
// ══════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:vendra_rider/vendra_core.dart';

import '../models/rider_models.dart';

class TaskCard extends StatelessWidget {
  final RiderOrder task;
  final bool accepting;
  final bool disabled;
  final VoidCallback onAccept;
  final VoidCallback onDecline;

  const TaskCard({
    super.key,
    required this.task,
    required this.onAccept,
    required this.onDecline,
    this.accepting = false,
    this.disabled = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.35), width: 1.5),
        boxShadow: [BoxShadow(color: AppColors.primary.withValues(alpha: 0.10), blurRadius: 16, offset: const Offset(0, 6))],
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.crisis_alert, color: AppColors.primary, size: 22),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'New Delivery Request',
                    style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.secondary.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '#${task.id} · ${task.itemCount} item${task.itemCount == 1 ? '' : 's'}',
                    style: GoogleFonts.poppins(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.secondary),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _RouteStop(
              color: AppColors.secondary,
              label: 'PICKUP',
              title: task.storeName ?? 'Store',
              subtitle: [
                if (task.storeAddress != null) task.storeAddress!,
                '${km(task.distanceToStoreKm)} away',
              ].join(' • '),
              showLine: true,
            ),
            _RouteStop(
              color: AppColors.primary,
              label: 'DROP-OFF',
              title: task.deliveryAddress ?? 'Customer location',
              subtitle: '${km(task.tripDistanceKm)} trip',
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: AppColors.background, borderRadius: BorderRadius.circular(12)),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Estimated payout', style: GoogleFonts.poppins(fontSize: 12, color: AppColors.textSecondary)),
                        Text(
                          task.estimatedPayout != null ? rs(task.estimatedPayout!) : '—',
                          style: GoogleFonts.poppins(fontSize: 22, fontWeight: FontWeight.w700, color: AppColors.success),
                        ),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text('Payment', style: GoogleFonts.poppins(fontSize: 12, color: AppColors.textSecondary)),
                      Row(
                        children: [
                          const Icon(Icons.account_balance_wallet_outlined, size: 16, color: AppColors.secondary),
                          const SizedBox(width: 4),
                          Text('To wallet', style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  flex: 2,
                  child: SizedBox(
                    height: 54,
                    child: OutlinedButton(
                      onPressed: accepting || disabled ? null : onDecline,
                      style: OutlinedButton.styleFrom(
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        foregroundColor: AppColors.textSecondary,
                      ),
                      child: Text('Decline', style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 3,
                  child: VendraButton(
                    text: 'Accept',
                    icon: Icons.check_circle,
                    isLoading: accepting,
                    onPressed: disabled ? null : onAccept,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _RouteStop extends StatelessWidget {
  final Color color;
  final String label;
  final String title;
  final String subtitle;
  final bool showLine;

  const _RouteStop({
    required this.color,
    required this.label,
    required this.title,
    required this.subtitle,
    this.showLine = false,
  });

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 20,
            child: Column(
              children: [
                const SizedBox(height: 4),
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                ),
                if (showLine) Expanded(child: Container(width: 2, color: Colors.grey.shade300)),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: GoogleFonts.poppins(
                          fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 0.8, color: AppColors.textLight)),
                  Text(title,
                      style: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                  Text(subtitle, style: GoogleFonts.poppins(fontSize: 12, color: AppColors.textSecondary)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
