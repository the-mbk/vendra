// ══════════════════════════════════════════════════════════════
// Vendra App - Product Detail Screen
// Replicates the Stitch product detail design
// ══════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../config/app_theme.dart';
import '../../../core/models/product_model.dart';
import '../bloc/cart_bloc.dart';

class ProductDetailScreen extends StatelessWidget {
  final ProductModel product;

  const ProductDetailScreen({super.key, required this.product});

  Color _getPlaceholderColor() {
    final colors = [
      const Color(0xFFF5F0E8), const Color(0xFFE8F0F5),
      const Color(0xFFF5E8F0), const Color(0xFFE8F5E8),
    ];
    return colors[product.name.length % colors.length];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text('Product Details', style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
        actions: [
          IconButton(icon: const Icon(Icons.share_outlined), onPressed: () {}),
          IconButton(icon: const Icon(Icons.favorite_border), onPressed: () {}),
        ],
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Product Image
            Container(
              width: double.infinity,
              height: 300,
              decoration: BoxDecoration(color: _getPlaceholderColor()),
              child: Stack(
                children: [
                  Center(
                    child: Icon(Icons.shopping_bag_outlined, size: 80, color: Colors.grey.shade400),
                  ),
                  // In Stock badge
                  if (product.publicStock > 0)
                    Positioned(
                      top: 16,
                      left: 16,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: AppColors.stockGreen,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.check_circle, color: Colors.white, size: 14),
                            const SizedBox(width: 4),
                            Text('In Stock', style: GoogleFonts.poppins(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),

            // Product Info
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Vendor info
                  Row(
                    children: [
                      const Icon(Icons.storefront_outlined, size: 16, color: AppColors.textSecondary),
                      const SizedBox(width: 6),
                      Text('Sold by ', style: GoogleFonts.poppins(fontSize: 13, color: AppColors.textSecondary)),
                      Text(
                        product.storeName ?? 'Vendor',
                        style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.secondary),
                      ),
                    ],
                  ),

                  const SizedBox(height: 8),

                  // Product name
                  Text(
                    product.name,
                    style: GoogleFonts.poppins(fontSize: 22, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
                  ),

                  const SizedBox(height: 8),

                  // Rating (static placeholder)
                  Row(
                    children: [
                      const Icon(Icons.star, color: AppColors.primary, size: 18),
                      const SizedBox(width: 4),
                      Text('4.3', style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.primary)),
                      Text(' • 128 Reviews • 2.1k Sold',
                          style: GoogleFonts.poppins(fontSize: 13, color: AppColors.textSecondary)),
                    ],
                  ),

                  const SizedBox(height: 16),

                  // Price
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        'Rs.${product.price.toStringAsFixed(0)}',
                        style: GoogleFonts.poppins(fontSize: 28, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
                      ),
                    ],
                  ),

                  const SizedBox(height: 16),
                  const Divider(),
                  const SizedBox(height: 16),

                  // Escrow info banner
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEBF0FA),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 44,
                          height: 44,
                          decoration: const BoxDecoration(
                            color: AppColors.secondary,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.shield_outlined, color: Colors.white, size: 22),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Payment secured by Vendra Escrow',
                                style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.secondary),
                              ),
                              Text(
                                'Funds are held until you confirm delivery.',
                                style: GoogleFonts.poppins(fontSize: 12, color: AppColors.textSecondary),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 20),

                  // Available stock
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Available Stock', style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w600)),
                      Text(
                        'Only ${product.publicStock} left',
                        style: GoogleFonts.poppins(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: product.publicStock <= 10 ? AppColors.stockRed : AppColors.primary,
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 16),

                  // Description
                  if (product.description != null && product.description!.isNotEmpty) ...[
                    Text('Description', style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 8),
                    Text(product.description!, style: GoogleFonts.poppins(fontSize: 13, color: AppColors.textSecondary, height: 1.5)),
                  ],

                  const SizedBox(height: 80), // Space for bottom buttons
                ],
              ),
            ),
          ],
        ),
      ),

      // Bottom action buttons
      bottomNavigationBar: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 10, offset: const Offset(0, -4))],
        ),
        child: SafeArea(
          child: Row(
            children: [
              // Add to Cart
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () {
                    context.read<CartBloc>().add(AddToCart(product: product));
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('${product.name} added to cart'),
                        backgroundColor: AppColors.success,
                        behavior: SnackBarBehavior.floating,
                        duration: const Duration(seconds: 1),
                      ),
                    );
                  },
                  icon: const Icon(Icons.shopping_cart_outlined),
                  label: const Text('Add to Cart'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.secondary,
                    side: const BorderSide(color: AppColors.secondary, width: 1.5),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              // Buy Now
              Expanded(
                child: ElevatedButton(
                  onPressed: () {
                    context.read<CartBloc>().add(AddToCart(product: product));
                    Navigator.pushNamed(context, '/customer/cart');
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text('Buy Now'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
