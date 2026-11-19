// ══════════════════════════════════════════════════════════════
// Vendra Vendor App - Restock alerts (SRDS Fig 2.11 vendor dashboard)
// Products whose free shelf units (shelf − reserved) are at or below the
// low_stock_units policy, emptiest first. The server sends the same alert
// as a notification when a product crosses the line.
// ══════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:vendra_vendor/vendra_core.dart';

import 'stock_in_sheet.dart';

/// Active products that need restocking, emptiest first
List<ProductModel> productsToRestock(Iterable<ProductModel> products, int threshold) {
  final low = products.where((p) => p.isActive && freeUnits(p) <= threshold).toList()
    ..sort((a, b) => freeUnits(a).compareTo(freeUnits(b)));
  return low;
}

class RestockCard extends StatelessWidget {
  final List<ProductModel> products;

  /// Whether this user may receive stock (owner or inventory manager)
  final bool canRestock;

  static const _shown = 4;

  const RestockCard({super.key, required this.products, required this.canRestock});

  @override
  Widget build(BuildContext context) {
    if (products.isEmpty) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.warning.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.inventory_2_outlined, size: 20, color: AppColors.warningInk),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Restock soon (${products.length})',
                  style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
                ),
              ),
              if (canRestock)
                TextButton.icon(
                  onPressed: () => startStockIn(context),
                  icon: const Icon(Icons.qr_code_scanner, size: 18),
                  label: const Text('Scan in'),
                ),
            ],
          ),
          for (final p in products.take(_shown))
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(p.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w500, color: AppColors.textPrimary)),
                        Text(
                          freeUnits(p) <= 0
                              ? 'None left to sell'
                              : '${freeUnits(p)} left to sell · ${p.publicStock} online',
                          style: GoogleFonts.poppins(
                            fontSize: 12,
                            color: freeUnits(p) <= 0 ? AppColors.error : AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (canRestock)
                    OutlinedButton(
                      onPressed: () => startStockIn(context, product: p),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                        minimumSize: const Size(0, 34),
                        textStyle: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w600),
                      ),
                      child: const Text('Restock'),
                    ),
                ],
              ),
            ),
          if (products.length > _shown)
            Padding(
              padding: const EdgeInsets.only(top: 2, bottom: 6),
              child: Text('and ${products.length - _shown} more', style: GoogleFonts.poppins(fontSize: 12, color: AppColors.textLight)),
            ),
        ],
      ),
    );
  }
}
