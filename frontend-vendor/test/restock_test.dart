// Restock alerts and stock-in preview: free units = shelf − reserved;
// online = shelf − buffer − reserved, never below 0
import 'package:flutter_test/flutter_test.dart';
import 'package:vendra_vendor/features/vendor/widgets/restock_card.dart';
import 'package:vendra_vendor/features/vendor/widgets/stock_in_sheet.dart';
import 'package:vendra_vendor/vendra_core.dart';

ProductModel _p(int id, {required int shelf, int reserved = 0, int buffer = 2, bool active = true}) => ProductModel(
      id: id,
      vendorId: 1,
      name: 'Product $id',
      price: 100,
      privateStock: shelf,
      buffer: buffer,
      reservedQuantity: reserved,
      publicStock: 0,
      isActive: active,
    );

void main() {
  test('products at or below the threshold need restocking, emptiest first', () {
    final list = productsToRestock([
      _p(1, shelf: 20),
      _p(2, shelf: 6, reserved: 1), // 5 free: at the threshold
      _p(3, shelf: 2, reserved: 2), // 0 free
      _p(4, shelf: 1, active: false), // deleted products don't count
    ], 5);
    expect(list.map((p) => p.id), [3, 2]);
  });

  test('stock-in preview shows online stock after the delivery', () {
    final p = _p(1, shelf: 3, reserved: 2, buffer: 2);
    expect(freeUnits(p), 1);
    expect(onlineAfter(p, 0), 0, reason: 'never negative');
    expect(onlineAfter(p, 10), 9);
  });
}
