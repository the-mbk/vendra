// ══════════════════════════════════════════════════════════════
// Vendra App - Loading Shimmer Widget
// Skeleton loading animation for content placeholders
// ══════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';

import '../../config/app_theme.dart';

class LoadingShimmer extends StatelessWidget {
  final int itemCount;
  final bool isGrid;

  const LoadingShimmer({
    super.key,
    this.itemCount = 6,
    this.isGrid = true,
  });

  @override
  Widget build(BuildContext context) {
    if (isGrid) {
      return GridView.builder(
        padding: const EdgeInsets.all(16),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          childAspectRatio: 0.72,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
        ),
        itemCount: itemCount,
        itemBuilder: (context, index) => _buildShimmerCard(),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: itemCount,
      itemBuilder: (context, index) => _buildShimmerListTile(),
    );
  }

  Widget _buildShimmerCard() {
    return Shimmer.fromColors(
      baseColor: AppColors.hairline,
      highlightColor: AppColors.surfaceMuted,
      child: Card(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 3,
              child: Container(
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                ),
              ),
            ),
            Expanded(
              flex: 2,
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(height: 14, width: double.infinity, color: AppColors.surface),
                    const SizedBox(height: 8),
                    Container(height: 14, width: 80, color: AppColors.surface),
                    const Spacer(),
                    Container(height: 16, width: 60, color: AppColors.surface),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildShimmerListTile() {
    return Shimmer.fromColors(
      baseColor: AppColors.hairline,
      highlightColor: AppColors.surfaceMuted,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Container(width: 50, height: 50, decoration: BoxDecoration(color: AppColors.surface, shape: BoxShape.circle)),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(height: 14, width: double.infinity, color: AppColors.surface),
                  const SizedBox(height: 8),
                  Container(height: 12, width: 120, color: AppColors.surface),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
