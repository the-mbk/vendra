// ══════════════════════════════════════════════════════════════
// Vendra App - Cart Item Model (Local State)
// Keeps the product snapshot so live stock updates (FR01) can flag
// lines that ask for more than is publicly available.
// ══════════════════════════════════════════════════════════════

import 'package:equatable/equatable.dart';
import 'package:vendra_customer/vendra_core.dart';

class CartItemModel extends Equatable {
  final ProductModel product;
  final int quantity;

  const CartItemModel({
    required this.product,
    this.quantity = 1,
  });

  double get total => product.price * quantity;

  /// Units the marketplace can still sell for this product
  int get available => product.publicStock < 0 ? 0 : product.publicStock;

  /// True when stock dropped below what this line asks for
  bool get exceedsStock => quantity > available;

  CartItemModel copyWith({int? quantity, ProductModel? product}) {
    return CartItemModel(
      product: product ?? this.product,
      quantity: quantity ?? this.quantity,
    );
  }

  @override
  List<Object?> get props => [product.id, product.publicStock, quantity];
}
