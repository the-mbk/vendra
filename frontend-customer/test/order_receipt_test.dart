// The customer's order receipt: the stamp and payment wording for each
// way an order can end, the refund maths, the PDF, and the screen in
// light and dark mode at phone width. Shapes copied from the backend
// (customer.controller.js formatCustomerOrder).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vendra_customer/features/customer/models/order_receipt.dart';
import 'package:vendra_customer/features/customer/screens/order_receipt_screen.dart';
import 'package:vendra_customer/features/customer/services/order_receipt_pdf.dart';
import 'package:vendra_customer/vendra_core.dart';

OrderModel _order({
  String status = 'delivered',
  String escrow = 'released',
  double refunded = 0,
  String payment = 'wallet',
  String? card,
  int items = 2,
}) =>
    OrderModel.fromJson({
      'id': 10,
      'storeName': 'Lahore Fashion Store',
      'storeAddress': 'MM Alam Road, Gulberg III, Lahore',
      'status': status,
      'deliveryType': 'delivery',
      'deliveryAddress': 'Near Lahore Store (Gulberg 1.2 km)',
      'subtotal': 25000,
      'deliveryFee': 180,
      'totalAmount': 25180,
      'escrowStatus': escrow,
      'cancellationReason': status == 'cancelled' ? 'Cancelled by customer' : null,
      'createdAt': '2026-11-18T17:00:43.157Z',
      'deliveredAt': status == 'delivered' ? '2026-11-18T17:04:00.000Z' : null,
      'paymentMethod': payment,
      'cardLabel': card,
      'refundedAmount': refunded,
      'items': [
        for (var i = 0; i < items; i++)
          {
            'id': i + 1,
            'productId': i + 1,
            'productName': 'Bridal Dupatta ${i + 1}',
            'quantity': 1,
            'unitPrice': 25000 / items
          },
      ],
    });

String _detail(OrderReceipt r, String label) => r.details.firstWhere((d) => d.label == label).value;

void main() {
  group('stamp and payment wording', () {
    test('delivered and settled: PAID, paid to the store', () {
      final r = OrderReceipt(_order());
      expect(r.stamp, ReceiptStamp.paid);
      expect(r.number, '#VDR-00010');
      expect(r.fileName, 'Vendra-Order-10');
      expect(_detail(r, 'Paid with'), 'Vendra wallet');
      expect(_detail(r, 'Payment'), 'Paid to the store');
      expect(r.details.any((d) => d.label == 'Delivered'), isTrue);
      expect(r.refunded, 0);
      expect(r.netPaid, 25180);
    });

    test('in progress: PAID, held by Vendra until delivery', () {
      final r = OrderReceipt(_order(status: 'on_the_way', escrow: 'held'));
      expect(r.stamp, ReceiptStamp.paid);
      expect(_detail(r, 'Payment'), 'Held by Vendra until your order is delivered');
      expect(_detail(r, 'Status'), 'On the Way');
    });

    test('card checkout names the card', () {
      final r = OrderReceipt(_order(payment: 'card', card: 'Visa ending 4242'));
      expect(_detail(r, 'Paid with'), 'Visa ending 4242');
      expect(OrderReceipt(_order(payment: 'card')).paymentMethod, 'Debit / credit card');
    });

    test('cancelled and refunded in full: REFUNDED', () {
      final r = OrderReceipt(_order(status: 'cancelled', escrow: 'refunded', refunded: 25180));
      expect(r.stamp, ReceiptStamp.refunded);
      expect(r.netPaid, 0);
      expect(r.lateCancellationFee, 0);
      expect(_detail(r, 'Reason'), 'Cancelled by customer');
      expect(_detail(r, 'Payment'), 'Refunded to your Vendra wallet');
    });

    test('late cancellation: PART REFUNDED, the store fee is explained', () {
      final r = OrderReceipt(_order(status: 'cancelled', escrow: 'refunded', refunded: 22680));
      expect(r.stamp, ReceiptStamp.partlyRefunded);
      expect(r.lateCancellationFee, 2500);
      expect(r.netPaid, 2500);
      expect(r.footnote, contains('Rs. 2,500'));
    });

    test('cancelled with nothing refunded: CANCELLED', () {
      expect(OrderReceipt(_order(status: 'cancelled', escrow: 'refunded')).stamp, ReceiptStamp.cancelled);
    });

    test('dispute open: UNDER REVIEW; split ruling: PART REFUNDED', () {
      expect(OrderReceipt(_order(escrow: 'disputed')).stamp, ReceiptStamp.underReview);
      final split = OrderReceipt(_order(refunded: 12500));
      expect(split.stamp, ReceiptStamp.partlyRefunded);
      expect(split.refundLabel, 'Dispute refund to your wallet');
      expect(OrderReceipt(_order(escrow: 'refunded', refunded: 25000)).stamp, ReceiptStamp.refunded);
    });
  });

  test('PDF text keeps to what the built-in font can draw', () {
    expect(OrderReceipt.pdfSafe('2 × Rs. 1,500 — paid · ok'), '2 x Rs. 1,500 - paid - ok');
    expect(OrderReceipt.pdfSafe('اردو'), '????');
  });

  test('the PDF is built, including a long order over several pages', () async {
    final short = await OrderReceiptPdf.build(OrderReceipt(_order()));
    expect(String.fromCharCodes(short.take(5)), '%PDF-');
    final long = await OrderReceiptPdf.build(
      OrderReceipt(_order(status: 'cancelled', escrow: 'refunded', refunded: 22680, items: 60)),
    );
    expect(long.length, greaterThan(short.length));
  });

  for (final brightness in Brightness.values) {
    testWidgets('the receipt screen lays out at phone width (${brightness.name})', (tester) async {
      tester.view.physicalSize = const Size(360 * 3, 780 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      applyThemeBrightness(brightness);
      addTearDown(() => applyThemeBrightness(Brightness.light));

      await tester.pumpWidget(MaterialApp(
        theme: brightness == Brightness.dark ? AppTheme.darkTheme : AppTheme.lightTheme,
        home: OrderReceiptScreen(order: _order(status: 'cancelled', escrow: 'refunded', refunded: 22680)),
      ));
      await tester.pump();

      expect(find.text('PART REFUNDED'), findsOneWidget);
      expect(find.text('Lahore Fashion Store'), findsOneWidget);
      expect(find.text('Total charged'), findsOneWidget);
      expect(find.text('You paid'), findsOneWidget);
      expect(find.text('Print'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
