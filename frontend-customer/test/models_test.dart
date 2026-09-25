// Model parsing tests — the API returns camelCase on customer routes and
// snake_case rows (with numeric strings) on vendor routes.
import 'package:flutter_test/flutter_test.dart';
import 'package:vendra_customer/vendra_core.dart';

void main() {
  test('OrderModel parses the customer (camelCase) shape', () {
    final o = OrderModel.fromJson({
      'id': 7,
      'status': 'on_the_way',
      'deliveryType': 'delivery',
      'subtotal': 9998,
      'deliveryFee': 150,
      'totalAmount': 10148,
      'escrowStatus': 'held',
      'rider': {'id': 6, 'name': 'Bilal Hussain', 'phone': '0301-2223344'},
      'latestDispute': null,
      'items': [
        {'id': 1, 'productId': 2, 'productName': 'Anker PowerCore', 'quantity': 2, 'unitPrice': 4999},
      ],
    });
    expect(o.totalAmount, 10148);
    expect(o.rider?.name, 'Bilal Hussain');
    expect(o.canDispute, isTrue);
    expect(o.items.single.total, 9998);
  });

  test('OrderModel parses the vendor (snake_case) shape with numeric strings', () {
    final o = OrderModel.fromJson({
      'id': 3,
      'status': 'ready_for_pickup',
      'delivery_type': 'delivery',
      'total_amount': '9650.00',
      'delivery_fee': '150.00',
      'escrow_status': 'disputed',
      'rider_user_id': 7,
      'rider_name': 'Hamza Sheikh',
      'latest_dispute': {'id': 1, 'status': 'open', 'issue_type': 'damaged_item'},
      'items': [
        {'id': 4, 'product_id': 5, 'product_name': 'Lawn Suit', 'quantity': 1, 'unit_price': '4500.00'},
      ],
    });
    expect(o.totalAmount, 9650);
    expect(o.deliveryFee, 150);
    expect(o.rider?.name, 'Hamza Sheikh');
    expect(o.hasOpenDispute, isTrue);
    expect(o.canDispute, isFalse);
    expect(o.statusText, 'Rider Assigned');
    expect(o.items.single.unitPrice, 4500);
  });

  test('ProductModel: cashier can sell the buffer but not reserved units', () {
    final p = ProductModel.fromJson({
      'id': 3,
      'vendor_id': 1,
      'name': 'JBL Tune 510BT',
      'price': '8499.00',
      'private_stock': 29,
      'buffer': 3,
      'reserved_quantity': 26,
      'public_stock': 0,
      'is_approved': true,
    });
    expect(p.sellableInStore, 3);
    expect(p.isOutOfStock, isTrue);
    final after = p.withStock(privateStock: 26, publicStock: 0);
    expect(after.sellableInStore, 0);
  });
}
