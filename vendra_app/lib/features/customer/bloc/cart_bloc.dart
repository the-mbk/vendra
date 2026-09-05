// ══════════════════════════════════════════════════════════════
// Vendra App - Cart BLoC (Local State)
// Manages shopping cart without server persistence
// ══════════════════════════════════════════════════════════════

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';
import '../../../core/models/product_model.dart';
import '../../../core/models/cart_item_model.dart';

// ── Events ──
abstract class CartEvent extends Equatable {
  const CartEvent();
  @override
  List<Object?> get props => [];
}

class AddToCart extends CartEvent {
  final ProductModel product;
  const AddToCart({required this.product});
  @override
  List<Object?> get props => [product.id];
}

class RemoveFromCart extends CartEvent {
  final int productId;
  const RemoveFromCart({required this.productId});
  @override
  List<Object?> get props => [productId];
}

class UpdateCartQuantity extends CartEvent {
  final int productId;
  final int quantity;
  const UpdateCartQuantity({required this.productId, required this.quantity});
  @override
  List<Object?> get props => [productId, quantity];
}

class ClearCart extends CartEvent {}

// ── State ──
class CartState extends Equatable {
  final List<CartItemModel> items;

  const CartState({this.items = const []});

  int get totalItems => items.fold(0, (sum, item) => sum + item.quantity);
  double get totalAmount => items.fold(0, (sum, item) => sum + item.total);
  bool get isEmpty => items.isEmpty;

  bool containsProduct(int productId) =>
      items.any((item) => item.product.id == productId);

  @override
  List<Object?> get props => [items];
}

// ── BLoC ──
class CartBloc extends Bloc<CartEvent, CartState> {
  CartBloc() : super(const CartState()) {
    on<AddToCart>(_onAdd);
    on<RemoveFromCart>(_onRemove);
    on<UpdateCartQuantity>(_onUpdateQuantity);
    on<ClearCart>(_onClear);
  }

  void _onAdd(AddToCart event, Emitter<CartState> emit) {
    final items = List<CartItemModel>.from(state.items);
    final existingIndex = items.indexWhere((i) => i.product.id == event.product.id);

    if (existingIndex >= 0) {
      // Increment quantity
      final existing = items[existingIndex];
      items[existingIndex] = existing.copyWith(quantity: existing.quantity + 1);
    } else {
      items.add(CartItemModel(product: event.product));
    }

    emit(CartState(items: items));
  }

  void _onRemove(RemoveFromCart event, Emitter<CartState> emit) {
    final items = state.items.where((i) => i.product.id != event.productId).toList();
    emit(CartState(items: items));
  }

  void _onUpdateQuantity(UpdateCartQuantity event, Emitter<CartState> emit) {
    if (event.quantity <= 0) {
      add(RemoveFromCart(productId: event.productId));
      return;
    }

    final items = List<CartItemModel>.from(state.items);
    final index = items.indexWhere((i) => i.product.id == event.productId);

    if (index >= 0) {
      items[index] = items[index].copyWith(quantity: event.quantity);
      emit(CartState(items: items));
    }
  }

  void _onClear(ClearCart event, Emitter<CartState> emit) {
    emit(const CartState());
  }
}
