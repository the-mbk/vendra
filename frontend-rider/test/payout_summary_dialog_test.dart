// The "Delivery confirmed" dialog must lay out and close. It used to be an
// AlertDialog around a LayoutBuilder: the layout failed, only the dark
// barrier painted, and the rider's screen froze after every delivery.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vendra_rider/features/rider/models/rider_models.dart';
import 'package:vendra_rider/features/rider/widgets/payout_summary_dialog.dart';

const _result = {
  'orderId': 10,
  'distanceKm': 1.2,
  'distanceSource': 'gps',
  'waitMinutes': 7,
  'payout': 96,
  'payoutBreakdown': {
    'baseFee': 60,
    'perKm': 25,
    'distanceKm': 1.2,
    'distancePay': 30,
    'perWaitMin': 3,
    'freeWaitMin': 5,
    'waitMinutes': 7,
    'paidWaitMinutes': 2,
    'waitPay': 6,
    'total': 96,
    'distanceSource': 'gps',
  },
};

void main() {
  testWidgets('the payout summary shows the slip and Done closes it', (tester) async {
    final result = DeliveryResult.fromJson(Map<String, dynamic>.from(_result));
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(onPressed: () => showPayoutSummary(context, result), child: const Text('open')),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Delivery confirmed'), findsOneWidget);
    expect(find.text('PAYOUT SLIP'), findsOneWidget);

    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(find.text('Delivery confirmed'), findsNothing);
  });
}
