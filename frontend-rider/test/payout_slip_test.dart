// Unit and widget tests for the itemised payout slip (FR04): parsing the
// server's payoutBreakdown, the slip lines and their wording, the rounding
// line, and old orders without a slip.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vendra_rider/features/rider/models/rider_models.dart';
import 'package:vendra_rider/features/rider/widgets/payout_slip.dart';
import 'package:vendra_rider/features/rider/widgets/task_card.dart';

const _slipJson = {
  'baseFee': 60,
  'perKm': 25,
  'distanceKm': 5.123,
  'distancePay': 128.08,
  'perWaitMin': 3,
  'freeWaitMin': 5,
  'waitMinutes': 7,
  'paidWaitMinutes': 2,
  'waitPay': 6,
  'total': 194.08,
  'distanceSource': 'gps',
};

void main() {
  group('PayoutBreakdown', () {
    test('parses numbers sent as numbers or strings', () {
      final b = PayoutBreakdown.fromJson({..._slipJson, 'baseFee': '60.00', 'distanceSource': 'straight_line'});
      expect(b.baseFee, 60);
      expect(b.distanceKm, 5.123);
      expect(b.total, 194.08);
      expect(b.isStraightLine, isTrue);
    });

    test('null (orders before slips) parses to null', () {
      expect(PayoutBreakdown.tryParse(null), isNull);
      expect(RiderOrder.fromJson(const {'id': 1, 'status': 'delivered', 'payout': 150}).payoutBreakdown, isNull);
    });

    test('lines read like a receipt', () {
      final lines = PayoutBreakdown.fromJson(_slipJson).lines;
      expect(lines.map((l) => l.label), ['Base fee', 'Distance', 'Waiting']);
      expect(lines[1].detail, '5.12 km × Rs. 25/km');
      expect(lines[1].amount, 128.08);
      expect(lines[2].detail, '7 min (5 free) × Rs. 3/min');
      expect(lines[2].amount, 6);
    });

    test('adds a rounding line only when the rounded lines miss the exact total', () {
      expect(PayoutBreakdown.fromJson(_slipJson).roundingDifference, 0);
      final off = PayoutBreakdown.fromJson({..._slipJson, 'total': 194.09});
      expect(off.roundingDifference, closeTo(0.01, 1e-9));
      expect(off.lines.last.label, 'Rounding');
    });

    test('formats fractional rates and minutes', () {
      expect(slipRate(2.5), 'Rs. 2.5');
      expect(slipMinutes(7.25), '7.3');
      expect(slipMinutes(3), '3');
      expect(slipKm(12), '12.00 km');
    });

    test('orders and the deliver response carry the slip', () {
      final order = RiderOrder.fromJson(const {
        'id': 9,
        'status': 'delivered',
        'payout': 194.08,
        'payoutBreakdown': _slipJson,
        'customerRating': 4,
        'otpRequired': false,
      });
      expect(order.payoutBreakdown?.total, 194.08);
      expect(order.customerRating, 4);
      final result = DeliveryResult.fromJson(const {'orderId': 9, 'payout': 194.08, 'payoutBreakdown': _slipJson});
      expect(result.breakdown?.waitPay, 6);
    });
  });

  group('PayoutSlip widget', () {
    Future<void> pump(WidgetTester tester, Widget child) => tester.pumpWidget(
          MaterialApp(home: Scaffold(body: SizedBox(width: 300, child: SingleChildScrollView(child: child)))),
        );

    testWidgets('shows each line, the total and the straight-line note', (tester) async {
      final b = PayoutBreakdown.fromJson({..._slipJson, 'distanceSource': 'straight_line'});
      await pump(tester, PayoutSlip(breakdown: b, total: b.total));

      expect(find.text('Base fee'), findsOneWidget);
      expect(find.text('Rs. 60'), findsOneWidget);
      expect(find.text('5.12 km × Rs. 25/km'), findsOneWidget);
      expect(find.text('Rs. 128.08'), findsOneWidget);
      expect(find.text('Total'), findsOneWidget);
      expect(find.text('Rs. 194.08'), findsOneWidget);
      expect(find.textContaining('straight-line estimate'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('an old order shows the total only', (tester) async {
      await pump(tester, const PayoutSlip(breakdown: null, total: 150));
      expect(find.text('Rs. 150'), findsOneWidget);
      expect(find.text('Base fee'), findsNothing);
      expect(find.textContaining('older delivery'), findsOneWidget);
    });

    testWidgets('a task card expands its estimated slip', (tester) async {
      final b = PayoutBreakdown.fromJson({..._slipJson, 'waitMinutes': 0, 'waitPay': 0, 'distanceSource': null});
      await pump(tester, EstimatedSlipToggle(breakdown: b, total: b.total));
      expect(find.text('Base fee'), findsNothing);

      await tester.tap(find.text('See estimated slip'));
      await tester.pumpAndSettle();
      expect(find.text('Base fee'), findsOneWidget);
      expect(find.text('Estimated total'), findsOneWidget);
    });
  });

  testWidgets('task card expands its estimated slip without overflowing', (tester) async {
    // The test font (every glyph a full square) is far wider than Poppins, so the
    // card's existing Accept button needs ~400 px here; the slip alone is checked at 300 px above
    tester.view.physicalSize = const Size(400, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final task = RiderOrder.fromJson({
      'id': 7,
      'status': 'ready_for_pickup',
      'storeName': 'A store with a rather long name in Gulberg III',
      'deliveryAddress': 'House 12, Street 34, Sector F-11/2, Islamabad',
      'itemCount': 2,
      'distanceToStoreKm': 1.2,
      'tripDistanceKm': 12.34,
      'estimatedPayout': 1308.5,
      'estimatedPayoutBreakdown': {..._slipJson, 'distanceKm': 12.34, 'distancePay': 1248.5, 'total': 1308.5},
    });
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: TaskCard(task: task, onAccept: () {}, onDecline: () {}),
        ),
      ),
    ));
    await tester.tap(find.text('See estimated slip'));
    await tester.pumpAndSettle();
    expect(find.text('Estimated total'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
