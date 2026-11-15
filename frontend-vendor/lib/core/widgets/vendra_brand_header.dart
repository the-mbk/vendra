// ══════════════════════════════════════════════════════════════
// Vendra Brand Header & Pakistan Flag Badge
// Vector-crisp, responsive brand mark with authentic Pakistan flag
// ══════════════════════════════════════════════════════════════

import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../config/app_theme.dart';

/// Authentic vector-drawn Pakistan Flag badge with crescent & 5-pointed star.
/// Works cleanly on white backgrounds (via subtle border) and dark backgrounds.
class PakistanFlagBadge extends StatelessWidget {
  final double width;
  final double height;
  final double borderRadius;
  final double borderWidth;
  final bool isDark;

  const PakistanFlagBadge({
    super.key,
    this.width = 28,
    this.height = 18,
    this.borderRadius = 3.0,
    this.borderWidth = 0.8,
    this.isDark = false,
  });

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size(width, height),
      painter: _PakistanFlagPainter(
        borderColor: isDark ? Colors.white24 : const Color(0x22000000),
        borderWidth: borderWidth,
        borderRadius: borderRadius,
      ),
    );
  }
}

class _PakistanFlagPainter extends CustomPainter {
  final Color borderColor;
  final double borderWidth;
  final double borderRadius;

  _PakistanFlagPainter({
    required this.borderColor,
    required this.borderWidth,
    required this.borderRadius,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final rrect = RRect.fromRectAndRadius(rect, Radius.circular(borderRadius));

    canvas.save();
    canvas.clipRRect(rrect);

    // 1. Hoist: pure white vertical stripe (1/4 width)
    final hoistWidth = size.width * 0.25;
    final whitePaint = Paint()
      ..color = Colors.white
      ..isAntiAlias = true;
    canvas.drawRect(Rect.fromLTWH(0, 0, hoistWidth, size.height), whitePaint);

    // 2. Fly: Pakistan dark green field (3/4 width)
    final greenPaint = Paint()
      ..color = AppColors.pakistanGreen
      ..isAntiAlias = true;
    canvas.drawRect(
      Rect.fromLTWH(hoistWidth, 0, size.width - hoistWidth, size.height),
      greenPaint,
    );

    // 3. Center of green field
    final flyCenter = Offset(hoistWidth + (size.width - hoistWidth) / 2, size.height / 2);
    final outerRadius = size.height * 0.29;
    final innerRadius = size.height * 0.245;

    // Angle of crescent & star: rotated 45 degrees towards top-right
    const angle = -math.pi / 4;
    final offsetDistance = outerRadius * 0.36;
    final innerCenter = Offset(
      flyCenter.dx + offsetDistance * math.cos(angle),
      flyCenter.dy + offsetDistance * math.sin(angle),
    );

    final outerPath = Path()..addOval(Rect.fromCircle(center: flyCenter, radius: outerRadius));
    final innerPath = Path()..addOval(Rect.fromCircle(center: innerCenter, radius: innerRadius));
    final crescentPath = Path.combine(PathOperation.difference, outerPath, innerPath);
    canvas.drawPath(crescentPath, whitePaint);

    // 4. 5-pointed star facing the top-right corner
    final starCenter = Offset(
      flyCenter.dx + outerRadius * 0.68 * math.cos(angle),
      flyCenter.dy + outerRadius * 0.68 * math.sin(angle),
    );
    final starRadius = size.height * 0.12;
    final starPath = _buildStarPath(starCenter, starRadius, starRadius * 0.42, angle);
    canvas.drawPath(starPath, whitePaint);

    canvas.restore();

    // 5. Crisp border outline
    if (borderWidth > 0) {
      final borderPaint = Paint()
        ..color = borderColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = borderWidth
        ..isAntiAlias = true;
      canvas.drawRRect(rrect, borderPaint);
    }
  }

  Path _buildStarPath(Offset center, double outerR, double innerR, double tipAngle) {
    final path = Path();
    for (int i = 0; i < 10; i++) {
      final r = (i % 2 == 0) ? outerR : innerR;
      final currentAngle = tipAngle + (i * math.pi / 5);
      final x = center.dx + r * math.cos(currentAngle);
      final y = center.dy + r * math.sin(currentAngle);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    path.close();
    return path;
  }

  @override
  bool shouldRepaint(covariant _PakistanFlagPainter oldDelegate) =>
      oldDelegate.borderColor != borderColor ||
      oldDelegate.borderWidth != borderWidth ||
      oldDelegate.borderRadius != borderRadius;
}

enum HeaderIconStyle { top, inline, none }

/// Unified Vendra Brand Header for Auth, Splash, and Landing screens
class VendraBrandHeader extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData? icon;
  final HeaderIconStyle iconStyle;
  final bool isDark;
  final double titleSize;
  final bool showFlag;

  const VendraBrandHeader({
    super.key,
    this.title = 'Vendra',
    required this.subtitle,
    this.icon,
    this.iconStyle = HeaderIconStyle.inline,
    this.isDark = false,
    this.titleSize = 34,
    this.showFlag = true,
  });

  @override
  Widget build(BuildContext context) {
    final iconWidget = (icon != null)
        ? Container(
            width: iconStyle == HeaderIconStyle.top ? 64 : 42,
            height: iconStyle == HeaderIconStyle.top ? 64 : 42,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: isDark
                    ? const [AppColors.primary, Color(0xFFFF8543)]
                    : const [AppColors.primary, Color(0xFFFA5716)],
              ),
              borderRadius: BorderRadius.circular(iconStyle == HeaderIconStyle.top ? 18 : 12),
              boxShadow: [
                BoxShadow(
                  color: AppColors.primary.withValues(alpha: isDark ? 0.35 : 0.25),
                  blurRadius: iconStyle == HeaderIconStyle.top ? 20 : 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Icon(
              icon,
              color: Colors.white,
              size: iconStyle == HeaderIconStyle.top ? 34 : 24,
            ),
          )
        : null;

    final wordmarkRow = Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        if (iconStyle == HeaderIconStyle.inline && iconWidget != null) ...[
          iconWidget,
          const SizedBox(width: 10),
        ],
        Text(
          title,
          style: GoogleFonts.poppins(
            fontSize: titleSize,
            fontWeight: FontWeight.w700,
            color: isDark ? Colors.white : AppColors.secondary,
            letterSpacing: -0.5,
          ),
        ),
        if (showFlag) ...[
          const SizedBox(width: 8),
          PakistanFlagBadge(
            width: (titleSize * 0.72).clamp(24.0, 36.0),
            height: (titleSize * 0.48).clamp(16.0, 24.0),
            isDark: isDark,
          ),
        ],
      ],
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        if (iconStyle == HeaderIconStyle.top && iconWidget != null) ...[
          iconWidget,
          const SizedBox(height: 16),
        ],
        wordmarkRow,
        const SizedBox(height: 4),
        Text(
          subtitle,
          style: GoogleFonts.poppins(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: isDark ? Colors.white70 : AppColors.textSecondary,
            letterSpacing: 0.2,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}
