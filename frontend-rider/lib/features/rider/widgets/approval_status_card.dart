// ══════════════════════════════════════════════════════════════
// Vendra Rider App - Approval status card
// Shown on Home instead of delivery requests until an admin approves
// the rider's documents: "Documents under review" while pending, or the
// admin's reason plus "Update documents" when they were rejected.
// ══════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:vendra_rider/vendra_core.dart';

class ApprovalStatusCard extends StatelessWidget {
  /// pending | rejected
  final String status;
  final String? rejectionReason;
  final VoidCallback? onUpdateDocuments;
  final VoidCallback? onCheckStatus;

  const ApprovalStatusCard({
    super.key,
    required this.status,
    this.rejectionReason,
    this.onUpdateDocuments,
    this.onCheckStatus,
  });

  bool get _rejected => status == 'rejected';

  @override
  Widget build(BuildContext context) {
    final color = _rejected ? AppColors.error : AppColors.reservedAmber;
    final reason = rejectionReason?.trim();
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: color.withValues(alpha: 0.35)),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 12, offset: const Offset(0, 4))],
      ),
      child: Column(
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(color: color.withValues(alpha: 0.12), shape: BoxShape.circle),
            child: Icon(_rejected ? Icons.assignment_late_outlined : Icons.hourglass_top_rounded, color: color, size: 32),
          ),
          const SizedBox(height: 14),
          Text(_rejected ? 'Documents not approved' : 'Documents under review',
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(fontSize: 17, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
          const SizedBox(height: 6),
          Text(
            _rejected
                ? 'An admin could not approve your documents. Fix them and send them again to start delivering.'
                : 'An admin is checking your CNIC, driving licence and vehicle registration. '
                    'You can go online once you are approved — we will notify you.',
            textAlign: TextAlign.center,
            style: GoogleFonts.poppins(fontSize: 13, height: 1.45, color: AppColors.textSecondary),
          ),
          if (_rejected && reason != null && reason.isNotEmpty) ...[
            const SizedBox(height: 14),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.error.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.error.withValues(alpha: 0.2)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('REASON FROM ADMIN',
                      style: GoogleFonts.poppins(
                          fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 0.8, color: AppColors.error)),
                  const SizedBox(height: 2),
                  Text(reason,
                      style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w500, color: AppColors.textPrimary)),
                ],
              ),
            ),
          ],
          const SizedBox(height: 18),
          if (_rejected)
            VendraButton(text: 'Update documents', icon: Icons.edit_document, onPressed: onUpdateDocuments)
          else
            VendraButton(text: 'Check status', icon: Icons.refresh, isOutlined: true, onPressed: onCheckStatus),
        ],
      ),
    );
  }
}
