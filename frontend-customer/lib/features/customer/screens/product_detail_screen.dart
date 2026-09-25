// ══════════════════════════════════════════════════════════════
// Vendra App - Product Detail Screen
// Replicates the Stitch product detail design.
// Public stock stays live via realtime stock:update events (FR01).
// ══════════════════════════════════════════════════════════════

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:vendra_customer/vendra_core.dart';
import '../../../config/app_routes.dart';
import '../bloc/cart_bloc.dart';

class ProductDetailScreen extends StatefulWidget {
  final ProductModel product;

  const ProductDetailScreen({super.key, required this.product});

  @override
  State<ProductDetailScreen> createState() => _ProductDetailScreenState();
}

class _ProductDetailScreenState extends State<ProductDetailScreen> {
  late ProductModel product;
  StreamSubscription<StockUpdateEvent>? _stockSub;

  @override
  void initState() {
    super.initState();
    product = widget.product;
    _stockSub = RealtimeService()
        .stockUpdates
        .where((e) => e.productId == product.id)
        .listen((e) => setState(() => product = product.withStock(publicStock: e.publicStock)));
  }

  @override
  void dispose() {
    _stockSub?.cancel();
    super.dispose();
  }

  /// Adds one unit unless the cart already holds every available unit
  bool _addToCart(BuildContext context) {
    final inCart = context.read<CartBloc>().state.quantityOf(product.id);
    if (product.isOutOfStock || inCart >= product.publicStock) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(product.isOutOfStock
            ? '${product.name} is sold out right now'
            : 'Your cart already has all ${product.publicStock} available'),
        behavior: SnackBarBehavior.floating,
      ));
      return false;
    }
    context.read<CartBloc>().add(AddToCart(product: product));
    return true;
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
            SizedBox(
              width: double.infinity,
              height: 300,
              child: Stack(
                children: [
                  // Product photo (or a placeholder when the vendor hasn't added one)
                  Positioned.fill(child: ProductImage(product: product, iconSize: 80)),
                  // In Stock badge
                  if (product.isOutOfStock)
                    Positioned(
                      top: 16,
                      left: 16,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: AppColors.stockRed,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text('Sold out', style: GoogleFonts.poppins(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
                      ),
                    ),
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

                  if (product.categoryName != null) ...[
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppColors.secondary.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(product.categoryName!,
                          style: GoogleFonts.poppins(fontSize: 11, fontWeight: FontWeight.w500, color: AppColors.secondary)),
                    ),
                  ],

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
                      Row(
                        children: [
                          // Live indicator: this number follows the store's stock in real time
                          const Icon(Icons.circle, size: 8, color: AppColors.stockGreen),
                          const SizedBox(width: 6),
                          Text(
                            product.isOutOfStock
                                ? 'Sold out'
                                : product.publicStock <= 10
                                    ? 'Only ${product.publicStock} left'
                                    : '${product.publicStock} in stock',
                            style: GoogleFonts.poppins(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: product.publicStock <= 10 ? AppColors.stockRed : AppColors.primary,
                            ),
                          ),
                        ],
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
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 10, offset: const Offset(0, -4))],
        ),
        child: SafeArea(
          child: Row(
            children: [
              // Add to Cart
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: product.isOutOfStock
                      ? null
                      : () {
                    if (!_addToCart(context)) return;
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
                  onPressed: product.isOutOfStock
                      ? null
                      : () {
                          final inCart = context.read<CartBloc>().state.quantityOf(product.id);
                          if (inCart == 0) _addToCart(context);
                          Navigator.pushNamed(context, AppRoutes.cart);
                        },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: Text(product.isOutOfStock ? 'Sold out' : 'Buy Now'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
