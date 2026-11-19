// ══════════════════════════════════════════════════════════════
// Vendra Rider App - Payout slip (FR04)
// Receipt-style lines: base fee, distance × rate, paid waiting × rate,
// a dashed rule and the total. Notes when the distance was a straight-
// line estimate. Orders from before slips existed show the total only.
// Also the expandable "estimated slip" on a task card.
// ══════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:vendra_rider/vendra_core.dart';

import '../models/rider_models.dart';

class PayoutSlip extends StatelessWidget {
  /// Null for an old order: only [total] is shown
  final PayoutBreakdown? breakdown;
  final double total;

  /// A task card's estimate (straight line, no waiting) rather than a paid slip
  final bool estimate;

  const PayoutSlip({super.key, required this.breakdown, required this.total, this.estimate = false});

  @override
  Widget build(BuildContext context) {
    final b = breakdown;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: AppColors.surfaceMuted,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(estimate ? 'ESTIMATED PAYOUT SLIP' : 'PAYOUT SLIP',
              style: GoogleFonts.poppins(
                  fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 1, color: AppColors.textSecondary)),
          const SizedBox(height: 6),
          if (b != null)
            for (final line in b.lines) _SlipRow(line: line)
          else
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Text('No itemised slip for this older delivery.',
                  style: GoogleFonts.poppins(fontSize: 12, color: AppColors.textSecondary)),
            ),
          const SizedBox(height: 6),
          const _DashedRule(),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: Text(estimate ? 'Estimated total' : 'Total',
                    style: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
              ),
              Text(rs(b?.total ?? total),
                  style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.success)),
            ],
          ),
          if (estimate)
            _note(Icons.info_outline,
                'Straight-line distance, no waiting. The final payout uses the distance actually ridden and any waiting time.')
          else if (b != null && b.isStraightLine)
            _note(Icons.straighten,
                'Distance is a straight-line estimate: too few GPS points were recorded on this trip.'),
        ],
      ),
    );
  }

  Widget _note(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 14, color: AppColors.textLight),
          const SizedBox(width: 6),
          Expanded(child: Text(text, style: GoogleFonts.poppins(fontSize: 11, height: 1.35, color: AppColors.textSecondary))),
        ],
      ),
    );
  }
}

class _SlipRow extends StatelessWidget {
  final PayoutSlipLine line;
  const _SlipRow({required this.line});

  @override
  Widget build(BuildContext context) {
    final negative = line.amount < 0;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(line.label,
                    style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w500, color: AppColors.textPrimary)),
                if (line.detail != null)
                  Text(line.detail!, style: GoogleFonts.poppins(fontSize: 11, color: AppColors.textSecondary)),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Text(negative ? '− ${rs(-line.amount)}' : rs(line.amount),
              style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
        ],
      ),
    );
  }
}

/// Painted, not laid out from the parent's width: a LayoutBuilder here can't
/// report an intrinsic size, which blanks any dialog that measures its content.
class _DashedRule extends StatelessWidget {
  const _DashedRule();

  @override
  Widget build(BuildContext context) {
    return SizedBox(height: 1, width: double.infinity, child: CustomPaint(painter: _DashPainter(AppColors.textLight)));
  }
}

class _DashPainter extends CustomPainter {
  final Color color;
  _DashPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    for (var x = 0.0; x < size.width; x += 7) {
      canvas.drawRect(Rect.fromLTWH(x, 0, 4, size.height), paint);
    }
  }

  @override
  bool shouldRepaint(_DashPainter old) => old.color != color;
}

/// "See estimated slip" toggle under a task card's payout
class EstimatedSlipToggle extends StatefulWidget {
  final PayoutBreakdown breakdown;
  final double total;
  const EstimatedSlipToggle({super.key, required this.breakdown, required this.total});

  @override
  State<EstimatedSlipToggle> createState() => _EstimatedSlipToggleState();
}

class _EstimatedSlipToggleState extends State<EstimatedSlipToggle> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          onTap: () => setState(() => _open = !_open),
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.receipt_long_outlined, size: 16, color: AppColors.secondary),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(_open ? 'Hide estimated slip' : 'See estimated slip',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.secondary)),
                ),
                Icon(_open ? Icons.expand_less : Icons.expand_more, size: 18, color: AppColors.secondary),
              ],
            ),
          ),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 180),
          alignment: Alignment.topCenter,
          child: _open
              ? PayoutSlip(breakdown: widget.breakdown, total: widget.total, estimate: true)
              : const SizedBox(width: double.infinity),
        ),
      ],
    );
  }
}
