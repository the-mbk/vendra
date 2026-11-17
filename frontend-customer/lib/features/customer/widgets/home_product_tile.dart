// ══════════════════════════════════════════════════════════════
// Vendra Customer App - Home product tile ("Today's Picks", search and
// category results)
// Photo, name + rating, the store (logo + name), distance, price and live
// stock (FR01). Tapping opens the product's own page (ProductDetailScreen),
// where "Visit store" leads on to the store.
// ══════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:vendra_customer/vendra_core.dart';

import '../screens/product_detail_screen.dart';
import 'trust_badges.dart';

/// Opens a product's page
void openProduct(BuildContext context, ProductModel product) {
  Navigator.push(context, MaterialPageRoute(builder: (_) => ProductDetailScreen(product: product)));
}

class HomeProductTile extends StatelessWidget {
  final ProductModel product;

  /// "1.2 km" from the customer, or empty when the store has no location
  final String distance;

  const HomeProductTile({super.key, required this.product, this.distance = ''});

  @override
  Widget build(BuildContext context) {
    final storeName = product.storeName ?? 'Store';
    return GestureDetector(
      onTap: () => openProduct(context, product),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, 2))],
        ),
        child: Row(
          children: [
            // Product photo (placeholder when the vendor hasn't added one)
            SizedBox(
              width: 100,
              height: 110,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: ProductImage(
                      product: product,
                      iconSize: 40,
                      borderRadius: const BorderRadius.horizontal(left: Radius.circular(14)),
                    ),
                  ),
                  // Stock badge
                  if (product.publicStock > 0 && product.publicStock <= 10)
                    Positioned(
                      top: 6,
                      left: 6,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppColors.stockRed.withValues(alpha: 0.9),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text('Low', style: GoogleFonts.poppins(fontSize: 9, fontWeight: FontWeight.w600, color: Colors.white)),
                      ),
                    ),
                ],
              ),
            ),
            // Product details
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Product name + rating
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            product.name,
                            style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w600),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (product.ratingCount > 0) ...[
                          const SizedBox(width: 6),
                          RatingBadge(average: product.averageRating, count: product.ratingCount, fontSize: 11),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    // The store: logo + name
                    Row(
                      children: [
                        StoreLogo(storeName: storeName, logoUrl: product.storeLogoUrl, size: 18),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            storeName,
                            maxLines: 1,
                            style: GoogleFonts.poppins(fontSize: 12, color: AppColors.secondary, fontWeight: FontWeight.w500),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    // Distance + delivery info
                    Row(
                      children: [
                        if (distance.isNotEmpty) ...[
                          Icon(Icons.location_on, size: 12, color: Colors.grey.shade500),
                          const SizedBox(width: 2),
                          Text(distance, style: GoogleFonts.poppins(fontSize: 11, color: AppColors.textSecondary)),
                          const SizedBox(width: 8),
                        ],
                        Icon(Icons.shield_outlined, size: 12, color: Colors.green.shade600),
                        const SizedBox(width: 2),
                        Text('Escrow', style: GoogleFonts.poppins(fontSize: 11, color: Colors.green.shade600, fontWeight: FontWeight.w500)),
                      ],
                    ),
                    const SizedBox(height: 6),
                    // Price + live public stock
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            formatRupees(product.price),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.primary),
                          ),
                        ),
                        // Live stock, synced with the store shelf (FR01)
                        const LiveDot(size: 6),
                        Text(
                          stockLabel(product),
                          style: GoogleFonts.poppins(
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                            color: product.publicStock <= 10 ? AppColors.stockRed : AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            // Arrow
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Icon(Icons.arrow_forward_ios, size: 14, color: Colors.grey.shade400),
            ),
          ],
        ),
      ),
    );
  }
}
