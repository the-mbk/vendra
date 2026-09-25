// ══════════════════════════════════════════════════════════════
// Vendra Rider App - Payout summary (FR04)
// Shown after a confirmed delivery: tracked distance, how it was
// measured, waiting time, and the payout credited to the wallet.
// ══════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:vendra_rider/vendra_core.dart';

import '../models/rider_models.dart';

Future<void> showPayoutSummary(BuildContext context, DeliveryResult result) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (context) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      contentPadding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(color: AppColors.success.withValues(alpha: 0.12), shape: BoxShape.circle),
            child: const Icon(Icons.check_circle, color: AppColors.success, size: 40),
          ),
          const SizedBox(height: 12),
          Text('Delivery confirmed', style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.w700)),
          Text('Order #${result.orderId}', style: GoogleFonts.poppins(fontSize: 13, color: AppColors.textSecondary)),
          const SizedBox(height: 16),
          Text(rs(result.payout),
              style: GoogleFonts.poppins(fontSize: 32, fontWeight: FontWeight.w700, color: AppColors.success)),
          Text('added to your wallet', style: GoogleFonts.poppins(fontSize: 12, color: AppColors.textSecondary)),
          const SizedBox(height: 16),
          _row(Icons.route, 'Distance', km(result.distanceKm)),
          _row(
            result.isGps ? Icons.gps_fixed : Icons.straighten,
            'Measured by',
            result.isGps ? 'GPS track' : 'Straight line (too few GPS points)',
          ),
          _row(Icons.schedule, 'Waiting at store', '${result.waitMinutes.toStringAsFixed(result.waitMinutes % 1 == 0 ? 0 : 1)} min'),
          const SizedBox(height: 8),
          Text(
            'The vendor is paid once the customer\'s dispute window closes.',
            textAlign: TextAlign.center,
            style: GoogleFonts.poppins(fontSize: 11, color: AppColors.textLight),
          ),
        ],
      ),
      actions: [
        SizedBox(
          width: double.infinity,
          child: VendraButton(text: 'Done', onPressed: () => Navigator.of(context).pop()),
        ),
      ],
    ),
  );
}

Widget _row(IconData icon, String label, String value) {
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
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
