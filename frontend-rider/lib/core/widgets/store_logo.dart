// ══════════════════════════════════════════════════════════════
// Vendra App - Store pictures
// StoreLogo: the store's logo in a circle (or rounded square), or its
//   initials on a colour picked from the name when it has none.
// StoreCover: the store's wide cover photo, or a brand gradient.
// Paths are what the API returns (/uploads/... or a full URL).
// ══════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import '../../config/api_config.dart';
import '../../config/app_theme.dart';

const _initialColors = [
  Color(0xFF1B4F8A), Color(0xFFFF6B35), Color(0xFF2E7D32), Color(0xFF6A1B9A),
  Color(0xFFC62828), Color(0xFF00838F), Color(0xFF5D4037), Color(0xFF283593),
];

/// "Karachi Electronics Hub" → "KE"
String storeInitials(String name) {
  final words = name.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty && RegExp(r'[A-Za-z0-9]').hasMatch(w[0])).toList();
  if (words.isEmpty) return '?';
  return (words.length == 1 ? words[0].substring(0, words[0].length.clamp(1, 2)) : '${words[0][0]}${words[1][0]}')
      .toUpperCase();
}

class StoreLogo extends StatelessWidget {
  final String storeName;
  final String? logoUrl;
  final double size;
  /// Rounded square instead of a circle
  final bool square;
  /// White ring around it (on top of a cover photo)
  final bool ring;

  const StoreLogo({
    super.key,
    required this.storeName,
    this.logoUrl,
    this.size = 40,
    this.square = false,
    this.ring = false,
  });

  Widget _initials() => Container(
        color: _initialColors[storeName.codeUnits.fold<int>(0, (a, c) => a + c) % _initialColors.length],
        alignment: Alignment.center,
        child: Text(
          storeInitials(storeName),
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: size * 0.36, letterSpacing: 0.5),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final url = logoUrl;
    final image = url == null || url.isEmpty
        ? _initials()
        : Image.network(ApiConfig.fileUrl(url), fit: BoxFit.cover, errorBuilder: (_, __, ___) => _initials());
    final radius = square ? BorderRadius.circular(size * 0.22) : BorderRadius.circular(size);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: radius,
        border: ring ? Border.all(color: Colors.white, width: size > 56 ? 3 : 2) : null,
        boxShadow: ring ? [BoxShadow(color: Colors.black.withValues(alpha: 0.18), blurRadius: 8)] : null,
      ),
      child: ClipRRect(borderRadius: radius, child: SizedBox.expand(child: image)),
    );
  }
}

class StoreCover extends StatelessWidget {
  final String? coverUrl;
  /// Darkens the bottom so white text on top stays readable
  final bool shade;

  const StoreCover({super.key, this.coverUrl, this.shade = false});

  static final _fallback = DecoratedBox(
    decoration: BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [AppColors.secondary, const Color(0xFF0D2847)],
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final url = coverUrl;
    return Stack(
      fit: StackFit.expand,
      children: [
        if (url == null || url.isEmpty)
          _fallback
        else
          Image.network(ApiConfig.fileUrl(url), fit: BoxFit.cover, errorBuilder: (_, __, ___) => _fallback),
        if (shade)
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Colors.black.withValues(alpha: 0.15), Colors.black.withValues(alpha: 0.65)],
              ),
            ),
          ),
      ],
    );
  }
}
