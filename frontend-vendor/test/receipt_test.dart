// POS receipt: parsing the server's `receipt`, the slip's text formatting,
// Latin-1 clean-up for the PDF font, and the 80 mm PDF itself.
import 'package:flutter_test/flutter_test.dart';
import 'package:vendra_vendor/features/vendor/models/pos_receipt.dart';
import 'package:vendra_vendor/features/vendor/models/pos_sale_model.dart';
import 'package:vendra_vendor/features/vendor/services/receipt_pdf.dart';

Map<String, dynamic> _receiptJson({bool withQr = true}) => {
      'receipt_number': 'POS-000042',
      'store': {
        'name': 'Usman Electronics',
        'address': 'Shop 4, Hall Road, Lahore',
        'phone': '0300-1112233',
        'header': 'Open 10am–10pm',
        'footer': '',
      },
      'sale': {
        'id': 42,
        'total_amount': 1349.5,
        'created_at': '2026-11-14T10:30:00Z',
        'cashier_name': 'Ali Raza',
        'items': [
          {'product_name': 'USB-C Cable', 'barcode': '8800001', 'quantity': 2, 'unit_price': 450},
          {'product_name': 'Phone Case', 'barcode': null, 'quantity': 1, 'unit_price': '449.50'},
        ],
      },
      'cashier': 'Ali Raza',
      'payment_qr': withQr
          ? {
              'account': 'PK36SCBL0000001123456702',
              'title': 'Usman Electronics',
              'payload': 'vendra-pay:PK36SCBL0000001123456702?name=Usman%20Electronics&amount=1349.50&ref=POS-42',
            }
          : null,
    };

void main() {
  test('PosReceipt parses the store, sale lines and scan-to-pay QR', () {
    final r = PosReceipt.fromJson(_receiptJson());
    expect(r.receiptNumber, 'POS-000042');
    expect(r.storeName, 'Usman Electronics');
    expect(r.header, 'Open 10am–10pm');
    expect(r.footer, isNull); // blank → the default footer is printed
    expect(r.cashier, 'Ali Raza');
    expect(r.saleId, 42);
    expect(r.total, 1349.5);
    expect(r.items, hasLength(2));
    expect(r.items[1].unitPrice, 449.5);
    expect(r.unitCount, 3);
    expect(r.paymentQr!.payload, contains('amount=1349.50'));
    expect(r.paymentQr!.account, 'PK36SCBL0000001123456702');
  });

  test('no payment account → no QR on the slip', () {
    expect(PosReceipt.fromJson(_receiptJson(withQr: false)).paymentQr, isNull);
  });

  test('PosSale carries the receipt and cashier from POST /pos/sales', () {
    final sale = PosSale.fromJson({
      'id': 42,
      'total_amount': 1349.5,
      'created_at': '2026-11-14T10:30:00Z',
      'cashier_name': 'Ali Raza',
      'items': [],
      'receipt': _receiptJson(),
    });
    expect(sale.cashierName, 'Ali Raza');
    expect(sale.receipt!.receiptNumber, 'POS-000042');
    expect(PosSale.fromJson({'id': 1, 'total_amount': 10}).receipt, isNull);
  });

  test('slip lines: qty × unit = line total, item count', () {
    final r = PosReceipt.fromJson(_receiptJson());
    expect(ReceiptFormat.qtyLine(r.items[0]), '2 × Rs. 450');
    expect(ReceiptFormat.money(r.items[0].total), 'Rs. 900');
    expect(ReceiptFormat.qtyLine(r.items[1]), '1 × Rs. 449.50');
    expect(ReceiptFormat.money(r.total), 'Rs. 1,349.50');
    expect(ReceiptFormat.itemCount(r), '3 items');
    expect(ReceiptFormat.dateTime(null), '');
  });

  test('pdfSafe keeps Latin-1 and swaps / drops the rest', () {
    expect(ReceiptFormat.pdfSafe('2 × Rs. 450 — café'), '2 x Rs. 450 - café');
    expect(ReceiptFormat.pdfSafe('دکان Shop'), '???? Shop');
  });

  test('the 80 mm PDF builds, with and without a QR, even with non-Latin text', () async {
    final withQr = await ReceiptPdf.build(PosReceipt.fromJson(_receiptJson()));
    expect(String.fromCharCodes(withQr.take(4)), '%PDF');

    final json = _receiptJson(withQr: false);
    (json['store'] as Map)['name'] = 'عثمان الیکٹرانکس';
    final plain = await ReceiptPdf.build(PosReceipt.fromJson(json));
    expect(String.fromCharCodes(plain.take(4)), '%PDF');
  });
}
