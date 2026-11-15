// ══════════════════════════════════════════════════════════════
// Vendra App - Star ratings
//   RatingStars   read-only stars with half steps (4.5 → ★★★★½)
//   RatingBadge   compact "★ 4.5 (12)" for cards and lists
//   RatingInput   tap to choose 1–5 stars
// ══════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';

import '../../config/app_theme.dart';

const Color starColor = Color(0xFFFFB400);

class RatingStars extends StatelessWidget {
  final double rating;
  final double size;

  const RatingStars({super.key, required this.rating, this.size = 16});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '${rating.toStringAsFixed(1)} out of 5 stars',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: List.generate(5, (i) {
          final fill = rating - i;
          final icon = fill >= 0.75
              ? Icons.star_rounded
              : fill >= 0.25
                  ? Icons.star_half_rounded
                  : Icons.star_outline_rounded;
          return Icon(icon, size: size, color: starColor);
        }),
      ),
    );
  }
}

class RatingBadge extends StatelessWidget {
  final double? average;
  final int count;
  final double fontSize;

  const RatingBadge({super.key, required this.average, required this.count, this.fontSize = 12});

  @override
  Widget build(BuildContext context) {
    if (average == null || count == 0) return const SizedBox.shrink();
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.star_rounded, size: fontSize + 3, color: starColor),
        const SizedBox(width: 2),
        Text(
          average!.toStringAsFixed(1),
          style: TextStyle(fontSize: fontSize, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
        ),
        Text(' ($count)', style: TextStyle(fontSize: fontSize, color: AppColors.textSecondary)),
      ],
    );
  }
}

class RatingInput extends StatelessWidget {
  final int value; // 0 = not chosen yet
  final ValueChanged<int> onChanged;
  final double size;

  const RatingInput({super.key, required this.value, required this.onChanged, this.size = 36});

  static const _labels = ['', 'Poor', 'Fair', 'Good', 'Very good', 'Excellent'];

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(5, (i) {
            final n = i + 1;
            return IconButton(
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              tooltip: '$n star${n == 1 ? '' : 's'}',
              onPressed: () => onChanged(n),
              icon: Icon(
                n <= value ? Icons.star_rounded : Icons.star_outline_rounded,
                size: size,
                color: starColor,
              ),
            );
          }),
        ),
        if (value > 0)
          Text(_labels[value], style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
      ],
    );
  }
}
