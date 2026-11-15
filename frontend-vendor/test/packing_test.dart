// Packing checklist (FR07): progress text, checkbox states, when "Mark as
// packed" opens up, and how packing errors from the API are read.
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vendra_vendor/features/vendor/bloc/vendor_order_bloc.dart';
import 'package:vendra_vendor/features/vendor/models/packing.dart';
import 'package:vendra_vendor/vendra_core.dart';

/// A vendor order row (snake_case) with lines of (quantity, packed_quantity)
OrderModel _order(List<(int, int)> lines, {String status = 'confirmed'}) => OrderModel.fromJson({
      'id': 9,
      'status': status,
      'total_amount': '500.00',
      'packed_by_name': status == 'packed' ? 'Sana Iqbal' : null,
      'otp_required': true,
      'items': [
        for (var i = 0; i < lines.length; i++)
          {
            'id': i + 1,
            'product_id': 100 + i,
            'product_name': 'Item $i',
            'quantity': lines[i].$1,
            'packed_quantity': lines[i].$2,
            'unit_price': '50.00',
            'barcode': '88000$i',
          },
      ],
    });

void main() {
  test('progress counts units, not lines', () {
    final o = _order([(2, 1), (3, 2)]);
    expect(packingProgressLabel(o), '3/5 units packed');
    expect(packingFraction(o), closeTo(0.6, 1e-9));
    expect(packingProgressLabel(_order([(1, 0)])), '0/1 unit packed');
    expect(packingFraction(_order([])), 0);
  });

  test('checkbox: packed, part-packed (tristate), not started', () {
    final o = _order([(2, 2), (3, 1), (1, 0)]);
    expect(packCheckboxValue(o.items[0]), isTrue);
    expect(packCheckboxValue(o.items[1]), isNull);
    expect(packCheckboxValue(o.items[2]), isFalse);
    // A full line is unticked; anything else is packed in full
    expect(packTargetFor(o.items[0]), isFalse);
    expect(packTargetFor(o.items[1]), isTrue);
    expect(packTargetFor(o.items[2]), isTrue);
  });

  test('"Mark as packed" only for a confirmed order with every unit packed', () {
    expect(canMarkPacked(_order([(2, 2), (1, 1)])), isTrue);
    expect(canMarkPacked(_order([(2, 2), (1, 0)])), isFalse);
    expect(canMarkPacked(_order([])), isFalse);
    expect(canMarkPacked(_order([(1, 1)], status: 'packed')), isFalse);
  });

  test('vendor rows carry who packed it and whether a handover code is needed', () {
    final o = _order([(1, 1)], status: 'packed');
    expect(o.packedByName, 'Sana Iqbal');
    expect(o.otpRequired, isTrue);
    expect(o.items.first.barcode, '880000');
  });

  test('PACKING_INCOMPLETE lists what is still missing', () {
    final options = RequestOptions(path: '/api/vendor/orders/9/prepare');
    final error = VendorOrderActionError.from(DioException(
      requestOptions: options,
      response: Response(requestOptions: options, statusCode: 409, data: {
        'success': false,
        'message': 'Pack every item first.',
        'code': 'PACKING_INCOMPLETE',
        'missing': [
          {'item_id': 2, 'product_name': 'Milk 1L', 'missing': 2},
        ],
      }),
    ));
    expect(error.code, 'PACKING_INCOMPLETE');
    expect(error.message, 'Pack every item first.');
    expect(error.missing, ['2 × Milk 1L']);
  });

  test('WRONG_ITEM keeps the server message and code', () {
    final options = RequestOptions(path: '/api/vendor/orders/9/scan');
    final error = VendorOrderActionError.from(DioException(
      requestOptions: options,
      response: Response(requestOptions: options, statusCode: 422, data: {
        'success': false,
        'message': 'Barcode 123 is not in Order #9.',
        'code': 'WRONG_ITEM',
      }),
    ));
    expect(error.code, 'WRONG_ITEM');
    expect(error.missing, isEmpty);
  });
}
