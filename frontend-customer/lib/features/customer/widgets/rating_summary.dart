// ══════════════════════════════════════════════════════════════
// Vendra Customer App - Rating summary and review tiles (FR06)
// RatingSummary  big average, stars, count and 5 → 1 breakdown bars
// ReviewTile     one customer review ("Ahmed R.", stars, date, comment)
// ══════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:vendra_customer/vendra_core.dart';

import '../bloc/product_detail_bloc.dart';

/// "1 rating" / "12 ratings"
String ratingCountLabel(int n) => '$n rating${n == 1 ? '' : 's'}';

class RatingSummary extends StatelessWidget {
  final double? average;
  final int count;
  final Map<int, int> distribution;

  const RatingSummary({super.key, required this.average, required this.count, required this.distribution});

  @override
  Widget build(BuildContext context) {
    if (average == null || count == 0) {
      return const Row(
        children: [
          Icon(Icons.star_outline_rounded, color: starColor, size: 28),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'No reviews yet. Customers can rate this product after it\'s delivered.',
              style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
            ),
          ),
        ],
      );
    }

    final hasBreakdown = distribution.values.any((n) => n > 0);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(
          width: 96,
          child: Column(
            children: [
              Text(average!.toStringAsFixed(1),
                  style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
              FittedBox(child: RatingStars(rating: average!, size: 16)),
              const SizedBox(height: 2),
              Text(ratingCountLabel(count), style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
            ],
          ),
        ),
        if (hasBreakdown) ...[
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              children: [
                for (final star in const [5, 4, 3, 2, 1])
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 12,
                          child: Text('$star', style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
                        ),
                        const Icon(Icons.star_rounded, size: 12, color: starColor),
                        const SizedBox(width: 6),
                        Expanded(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: LinearProgressIndicator(
                              value: ratingFraction(distribution, star),
                              minHeight: 7,
                              color: starColor,
                              backgroundColor: AppColors.hairline,
                            ),
                          ),
                        ),
                        SizedBox(
                          width: 32,
                          child: Text(
                            '${distribution[star] ?? 0}',
                            textAlign: TextAlign.right,
                            style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class ReviewTile extends StatelessWidget {
  final ReviewModel review;
  const ReviewTile({super.key, required this.review});

  static final _date = DateFormat('d MMM yyyy');

  @override
  Widget build(BuildContext context) {
    final name = review.customerName.trim().isEmpty ? 'Customer' : review.customerName.trim();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 16,
            backgroundColor: AppColors.secondary.withValues(alpha: 0.1),
            child: Text(name[0].toUpperCase(),
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.secondary)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                    ),
                    if (review.createdAt != null)
                      Text(_date.format(review.createdAt!),
                          style: const TextStyle(fontSize: 11, color: AppColors.textLight)),
                  ],
                ),
                const SizedBox(height: 2),
                RatingStars(rating: review.rating.toDouble(), size: 14),
                if ((review.comment ?? '').trim().isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(review.comment!.trim(),
                      style: const TextStyle(fontSize: 13, height: 1.4, color: AppColors.textSecondary)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
