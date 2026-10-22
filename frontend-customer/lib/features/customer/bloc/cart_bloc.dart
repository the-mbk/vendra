// ══════════════════════════════════════════════════════════════
// Vendra App - Cart BLoC (Local State)
// Manages shopping carts without server persistence. Every order comes from
// one store, so items are grouped into a separate cart per store
// (CartState.stores / forStore); checking one out clears only that store.
// Listens to realtime public stock (FR01) so cart lines show when a
// product sold out or dropped below the requested quantity.
// ══════════════════════════════════════════════════════════════

import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:vendra_customer/vendra_core.dart';
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

/// Empties one store's cart (after its order is placed, or when the customer removes it)
class ClearStoreCart extends CartEvent {
  final int vendorId;
  const ClearStoreCart({required this.vendorId});
  @override
  List<Object?> get props => [vendorId];
}

/// Latest public stock for a product (realtime event or a 409 INSUFFICIENT_STOCK reply)
class CartStockChanged extends CartEvent {
  final int productId;
  final int publicStock;
  const CartStockChanged({required this.productId, required this.publicStock});
  @override
  List<Object?> get props => [productId, publicStock];
}

// ── State ──

/// The items from one store, checked out together as one order
class StoreCart {
  final int vendorId;
  final List<CartItemModel> items;
  const StoreCart(this.vendorId, this.items);

  ProductModel get _first => items.first.product;
  String get storeName => _first.storeName ?? 'Store';
  String? get storeAddress => _first.storeAddress;
  double? get storeLat => _first.vendorLat;
  double? get storeLng => _first.vendorLng;
  int get totalItems => items.fold(0, (sum, item) => sum + item.quantity);
  double get totalAmount => items.fold(0, (sum, item) => sum + item.total);
  bool get hasStockProblems => items.any((item) => item.exceedsStock);
}

class CartState extends Equatable {
  final List<CartItemModel> items;

  const CartState({this.items = const []});

  int get totalItems => items.fold(0, (sum, item) => sum + item.quantity);
  double get totalAmount => items.fold(0, (sum, item) => sum + item.total);
  bool get isEmpty => items.isEmpty;

  bool containsProduct(int productId) =>
      items.any((item) => item.product.id == productId);

  int quantityOf(int productId) {
    for (final item in items) {
      if (item.product.id == productId) return item.quantity;
    }
    return 0;
  }

  /// Any line asking for more than the store can currently sell
  bool get hasStockProblems => items.any((item) => item.exceedsStock);

  /// One cart per store, in the order the stores were first added
  List<StoreCart> get stores {
    final byStore = <int, List<CartItemModel>>{};
    for (final item in items) {
      byStore.putIfAbsent(item.product.vendorId, () => []).add(item);
    }
    return [for (final e in byStore.entries) StoreCart(e.key, e.value)];
  }

  /// Just this store's items, as a cart of its own
  CartState forStore(int vendorId) =>
      CartState(items: items.where((i) => i.product.vendorId == vendorId).toList());

  @override
  List<Object?> get props => [items];
}

// ── BLoC ──
class CartBloc extends Bloc<CartEvent, CartState> {
  StreamSubscription<StockUpdateEvent>? _stockSub;

  CartBloc() : super(const CartState()) {
    on<AddToCart>(_onAdd);
    on<RemoveFromCart>(_onRemove);
    on<UpdateCartQuantity>(_onUpdateQuantity);
    on<ClearCart>(_onClear);
    on<ClearStoreCart>(_onClearStore);
    on<CartStockChanged>(_onStockChanged);

    _stockSub = RealtimeService().stockUpdates.listen((e) {
      if (state.containsProduct(e.productId)) {
        add(CartStockChanged(productId: e.productId, publicStock: e.publicStock));
      }
    });
  }

  void _onStockChanged(CartStockChanged event, Emitter<CartState> emit) {
    final items = state.items
        .map((i) => i.product.id == event.productId
            ? i.copyWith(product: i.product.withStock(publicStock: event.publicStock))
            : i)
        .toList();
    emit(CartState(items: items));
  }

  @override
  Future<void> close() {
    _stockSub?.cancel();
    return super.close();
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

  void _onClearStore(ClearStoreCart event, Emitter<CartState> emit) {
    emit(CartState(items: state.items.where((i) => i.product.vendorId != event.vendorId).toList()));
  }
}
