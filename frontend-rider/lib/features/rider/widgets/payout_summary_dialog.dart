// ══════════════════════════════════════════════════════════════
// Vendra Rider App - Payout summary (FR04)
// Shown after a confirmed delivery: the payout credited to the wallet
// and its itemised slip (base fee, distance × rate, paid waiting × rate),
// noting when the distance was a straight-line estimate.
// ══════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:vendra_rider/vendra_core.dart';

import '../models/rider_models.dart';
import 'payout_slip.dart';

Future<void> showPayoutSummary(BuildContext context, DeliveryResult result) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    // A plain Dialog with a fixed width: AlertDialog measures its content's
    // intrinsic width, and a failed measurement leaves only the dark barrier.
    builder: (context) => Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 8),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 64,
                      height: 64,
                      decoration: BoxDecoration(color: AppColors.success.withValues(alpha: 0.12), shape: BoxShape.circle),
                      child: const Icon(Icons.check_circle, color: AppColors.success, size: 40),
                    ),
                    const SizedBox(height: 12),
                    Text('Delivery confirmed',
                        style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                    Text('Order #${result.orderId}',
                        style: GoogleFonts.poppins(fontSize: 13, color: AppColors.textSecondary)),
                    const SizedBox(height: 12),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(rs(result.payout),
                          style:
                              GoogleFonts.poppins(fontSize: 32, fontWeight: FontWeight.w700, color: AppColors.success)),
                    ),
                    Text('added to your wallet', style: GoogleFonts.poppins(fontSize: 12, color: AppColors.textSecondary)),
                    const SizedBox(height: 16),
                    PayoutSlip(breakdown: result.breakdown, total: result.payout),
                    if (result.breakdown == null) ...[
                      // No slip from the server: at least the trip figures
                      const SizedBox(height: 8),
                      _row(Icons.route, 'Distance', km(result.distanceKm)),
                      _row(result.isGps ? Icons.gps_fixed : Icons.straighten, 'Measured by',
                          result.isGps ? 'GPS track' : 'Straight line'),
                      _row(Icons.schedule, 'Waiting at store', '${slipMinutes(result.waitMinutes)} min'),
                    ],
                    const SizedBox(height: 10),
                    Text(
                      "The vendor is paid once the customer's dispute window closes.",
                      textAlign: TextAlign.center,
                      style: GoogleFonts.poppins(fontSize: 11, color: AppColors.textLight),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
              child: VendraButton(text: 'Done', onPressed: () => Navigator.of(context).pop()),
            ),
          ],
        ),
      ),
    ),
  );
}

Widget _row(IconData icon, String label, String value) {
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      children: [
        Icon(icon, size: 18, color: AppColors.secondary),
        const SizedBox(width: 10),
        Text(label, style: GoogleFonts.poppins(fontSize: 13, color: AppColors.textSecondary)),
        const SizedBox(width: 12),
        Expanded(
          child: Text(value,
              textAlign: TextAlign.right,
              style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
        ),
      ],
    ),
  );
}
