// One cart per store: grouping, totals, clearing one store, and the delivery radius check

import 'package:flutter_test/flutter_test.dart';
import 'package:vendra_customer/core/models/cart_item_model.dart';
import 'package:vendra_customer/features/customer/bloc/cart_bloc.dart';
import 'package:vendra_customer/vendra_core.dart';

ProductModel product(int id, int vendorId, double price) => ProductModel(
      id: id,
      vendorId: vendorId,
      storeName: 'Store $vendorId',
      name: 'Product $id',
      price: price,
      publicStock: 50,
    );

void main() {
  test('items are grouped into one cart per store, in the order stores were added', () {
    final state = CartState(items: [
      for (final p in [product(1, 7, 100), product(2, 9, 250), product(3, 7, 50)]) CartItemModel(product: p),
    ]);
    final stores = state.stores;
    expect(stores.map((s) => s.vendorId), [7, 9]);
    expect(stores.first.storeName, 'Store 7');
    expect(stores.first.totalAmount, 150);
    expect(state.forStore(9).items.single.product.id, 2);
  });

  test('checking out one store clears only that store', () async {
    final bloc = CartBloc();
    addTearDown(bloc.close);
    bloc
      ..add(AddToCart(product: product(1, 7, 100)))
      ..add(AddToCart(product: product(2, 9, 250)))
      ..add(const ClearStoreCart(vendorId: 7));
    final last = await bloc.stream.elementAt(2);
    expect(last.stores.map((c) => c.vendorId), [9]);
  });

  test('a store beyond the max delivery distance offers pickup only', () {
    const config = AppConfig(maxDeliveryKm: 15);
    expect(config.deliversAt(14.9), isTrue);
    expect(config.deliversAt(15.1), isFalse);
    expect(const AppConfig().deliversAt(500), isTrue, reason: '0 means no limit');
  });
}
