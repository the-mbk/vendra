// ══════════════════════════════════════════════════════════════
// Vendra Rider App - Parcel profile (SRDS §2.4.3, PR 03)
// Shown on a delivery request before the rider accepts, so a rider on a
// 70cc bike doesn't take a 20 kg flour order and cancel at the store.
// Weight comes from the products' listed weights (optional for vendors).
// ══════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:vendra_rider/vendra_core.dart';

import '../models/rider_models.dart';

String formatKg(int grams) {
  final kg = grams / 1000;
  return '${kg >= 10 ? kg.toStringAsFixed(0) : kg.toStringAsFixed(1)} kg';
}

class ParcelProfileChip extends StatelessWidget {
  final RiderOrder task;
  const ParcelProfileChip({super.key, required this.task});

  @override
  Widget build(BuildContext context) {
    final parcel = task.parcelClass;
    final (IconData icon, Color color) = switch (parcel) {
      ParcelClass.standard => (Icons.two_wheeler, AppColors.secondary),
      ParcelClass.medium => (Icons.inventory_2_outlined, AppColors.secondary),
      ParcelClass.heavy => (Icons.luggage_outlined, AppColors.reservedAmber),
      ParcelClass.unknown => (Icons.help_outline, AppColors.textSecondary),
    };
    final grams = task.parcelWeightGrams;
    final weight = grams <= 0 ? null : '${task.parcelWeightComplete ? '' : 'at least '}${formatKg(grams)}';
    final detail = switch (parcel) {
      ParcelClass.unknown => weight == null
          ? '${task.itemCount} item${task.itemCount == 1 ? '' : 's'} · the store hasn\'t listed weights'
          : '$weight listed · some items have no weight',
      _ => '${parcel.range}${weight != null ? ' · $weight' : ''}',
    };

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: AppColors.isDark ? 0.16 : 0.07),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          if (parcel == ParcelClass.heavy)
            Stack(
              clipBehavior: Clip.none,
              children: [
                Icon(icon, size: 22, color: color),
                Positioned(right: -6, top: -6, child: Icon(Icons.warning_amber_rounded, size: 13, color: color)),
              ],
            )
          else
            Icon(icon, size: 22, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(parcel.label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                Text(detail, style: TextStyle(fontSize: 11, color: AppColors.textSecondary)),
                if (parcel == ParcelClass.heavy)
                  Text('Check your vehicle can carry it safely before accepting.',
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: AppColors.warningInk)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
