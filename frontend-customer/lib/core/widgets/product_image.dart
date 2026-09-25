// ══════════════════════════════════════════════════════════════
// Vendra App - Product Image
// Shows the product photo when there is one, otherwise a coloured
// placeholder icon. Use it anywhere a product is pictured.
// ══════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import '../../config/api_config.dart';
import '../models/product_model.dart';

class ProductImage extends StatelessWidget {
  final ProductModel product;
  final BoxFit fit;
  final double iconSize;
  final BorderRadius? borderRadius;

  const ProductImage({
    super.key,
    required this.product,
    this.fit = BoxFit.cover,
    this.iconSize = 48,
    this.borderRadius,
  });

  static const _placeholderColors = [
    Color(0xFFE8F5E9), Color(0xFFFFF3E0),
    Color(0xFFE3F2FD), Color(0xFFFCE4EC),
    Color(0xFFF3E5F5), Color(0xFFE0F2F1),
    Color(0xFFFFF8E1), Color(0xFFE8EAF6),
  ];

  static const _placeholderIcons = [
    Icons.shopping_bag_outlined, Icons.fastfood_outlined,
    Icons.local_grocery_store_outlined, Icons.storefront_outlined,
    Icons.inventory_2_outlined, Icons.category_outlined,
  ];

  Widget _placeholder() => Container(
        color: _placeholderColors[product.name.length % _placeholderColors.length],
        alignment: Alignment.center,
        child: Icon(
          _placeholderIcons[product.id % _placeholderIcons.length],
          size: iconSize,
          color: Colors.grey.shade400,
        ),
      );

  @override
  Widget build(BuildContext context) {
    final url = product.imageUrl;
    final child = url == null || url.isEmpty
        ? _placeholder()
        : Image.network(
            ApiConfig.fileUrl(url),
            fit: fit,
            width: double.infinity,
            height: double.infinity,
            errorBuilder: (_, __, ___) => _placeholder(),
            loadingBuilder: (context, img, progress) => progress == null ? img : _placeholder(),
          );
    return borderRadius == null ? child : ClipRRect(borderRadius: borderRadius!, child: child);
  }
}
