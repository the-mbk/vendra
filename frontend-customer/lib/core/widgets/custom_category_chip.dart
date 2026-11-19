// ══════════════════════════════════════════════════════════════
// Vendra Customer App - Category chips
// Squircle tiles: one clear Material icon per category on a soft tint of
// its colour; the selected tile fills with the colour.
// ══════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../config/app_theme.dart';
import '../models/category_model.dart';

class CategoryStyle {
  final IconData icon;
  final Color tone;

  const CategoryStyle(this.icon, this.tone);

  static const _electrical = CategoryStyle(Icons.devices_rounded, Color(0xFF3B82F6));            // Royal Blue
  static const _mobile = CategoryStyle(Icons.headphones_rounded, Color(0xFF6366F1));             // Indigo
  static const _grocery = CategoryStyle(Icons.local_grocery_store_rounded, Color(0xFF10B981));   // Emerald Green
  static const _fashion = CategoryStyle(Icons.checkroom_rounded, Color(0xFFEC4899));             // Rose Pink
  static const _health = CategoryStyle(Icons.medical_services_rounded, Color(0xFF14B8A6));       // Teal
  static const _kitchen = CategoryStyle(Icons.restaurant_rounded, Color(0xFFF59E0B));           // Amber
  static const _books = CategoryStyle(Icons.menu_book_rounded, Color(0xFF8B5CF6));               // Purple
  static const _other = CategoryStyle(Icons.category_rounded, Color(0xFF64748B));                // Slate

  /// "All categories" tile
  static const all = CategoryStyle(Icons.dashboard_rounded, AppColors.primary);

  static CategoryStyle of(CategoryModel category) {
    switch (category.icon) {
      case 'devices':
        return _electrical;
      case 'phone_android':
        return _mobile;
      case 'local_grocery_store':
        return _grocery;
      case 'checkroom':
        return _fashion;
      case 'spa':
        return _health;
      case 'kitchen':
        return _kitchen;
      case 'menu_book':
        return _books;
    }
    final name = category.name.toLowerCase();
    if (name.contains('electr')) return _electrical;
    if (name.contains('mobile') || name.contains('phone')) return _mobile;
    if (name.contains('grocer') || name.contains('kiryana')) return _grocery;
    if (name.contains('fashion') || name.contains('apparel')) return _fashion;
    if (name.contains('pharma') || name.contains('health') || name.contains('beauty')) return _health;
    if (name.contains('kitchen') || name.contains('dining') || name.contains('home')) return _kitchen;
    if (name.contains('book') || name.contains('station')) return _books;
    return _other;
  }
}

class CustomCategoryChip extends StatelessWidget {
  final String label;
  final CategoryStyle style;
  final bool selected;
  final VoidCallback onTap;

  const CustomCategoryChip({
    super.key,
    required this.label,
    required this.style,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final tone = style.tone;
    final isDark = AppColors.isDark;

    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: SizedBox(
          width: 72,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOutCubic,
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: selected
                      ? tone
                      : (isDark ? tone.withValues(alpha: 0.16) : tone.withValues(alpha: 0.10)),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: selected
                        ? tone
                        : (isDark ? tone.withValues(alpha: 0.28) : tone.withValues(alpha: 0.18)),
                    width: selected ? 2.0 : 1.2,
                  ),
                  boxShadow: selected
                      ? [
                          BoxShadow(
                            color: tone.withValues(alpha: 0.35),
                            blurRadius: 8,
                            offset: const Offset(0, 3),
                          )
                        ]
                      : null,
                ),
                child: Center(
                  child: Icon(
                    style.icon,
                    size: 26,
                    color: selected
                        ? Colors.white
                        : (isDark ? Color.lerp(tone, Colors.white, 0.45)! : tone),
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: GoogleFonts.poppins(
                  fontSize: 11.5,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                  color: selected
                      ? (isDark ? Colors.white : AppColors.textPrimary)
                      : AppColors.textSecondary,
                  letterSpacing: -0.2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
