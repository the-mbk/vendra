// ══════════════════════════════════════════════════════════════
// Vendra App - A person's profile photo
// The photo when they set one (relative /uploads path or a full URL),
// otherwise their initials on the brand navy. Used in the chat header,
// the customer's rider card and the profile screens.
// ══════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../config/api_config.dart';
import '../../config/app_theme.dart';

/// "Bilal H." → "BH", "Ahmed" → "A"
String personInitials(String? name) {
  final words = (name ?? '').trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
  if (words.isEmpty) return '?';
  final first = words.first[0];
  final last = words.length > 1 ? words.last.replaceAll('.', '') : '';
  return (first + (last.isNotEmpty ? last[0] : '')).toUpperCase();
}

class UserAvatar extends StatelessWidget {
  final String? name;
  final String? photoUrl;
  final double size;

  /// Shown in the corner, e.g. a delivery icon for a rider
  final IconData? badge;

  const UserAvatar({super.key, required this.name, this.photoUrl, this.size = 44, this.badge});

  Widget _initials() => Container(
        color: AppColors.secondary.withValues(alpha: 0.14),
        alignment: Alignment.center,
        child: Text(
          personInitials(name),
          style: GoogleFonts.poppins(
            fontSize: size * 0.36,
            fontWeight: FontWeight.w600,
            color: AppColors.secondary,
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final url = photoUrl;
    final circle = ClipOval(
      child: SizedBox(
        width: size,
        height: size,
        child: url == null || url.isEmpty
            ? _initials()
            : Image.network(
                ApiConfig.fileUrl(url),
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => _initials(),
                loadingBuilder: (context, img, progress) => progress == null ? img : _initials(),
              ),
      ),
    );
    if (badge == null) return circle;
    final badgeSize = (size * 0.4).clamp(16.0, 28.0);
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          circle,
          Positioned(
            right: -2,
            bottom: -2,
            child: Container(
              width: badgeSize,
              height: badgeSize,
              decoration: BoxDecoration(
                color: AppColors.primary,
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.surface, width: 2),
              ),
              child: Icon(badge, size: badgeSize * 0.6, color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }
}
