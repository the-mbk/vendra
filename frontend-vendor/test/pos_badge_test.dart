// POS tile warnings: nearly empty counter, all units promised online, or no stock
import 'package:flutter_test/flutter_test.dart';
import 'package:vendra_vendor/features/vendor/screens/pos_screen.dart';
import 'package:vendra_vendor/vendra_core.dart';

ProductModel _p({required int shelf, int reserved = 0}) => ProductModel(
      id: 1,
      vendorId: 1,
      name: 'Redmi Buds 5',
      price: 6999,
      privateStock: shelf,
      buffer: 0,
      reservedQuantity: reserved,
      publicStock: 0,
    );

void main() {
  test('badges follow what the counter can still sell', () {
    expect(posStockBadge(_p(shelf: 10)), PosStockBadge.none);
    expect(posStockBadge(_p(shelf: 4, reserved: 2)), PosStockBadge.low, reason: '2 sellable');
    expect(posStockBadge(_p(shelf: 1, reserved: 1)), PosStockBadge.allReserved);
    expect(posStockBadge(_p(shelf: 0)), PosStockBadge.soldOut);
  });
}
