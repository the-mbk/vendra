// Tests for the delivery handover code: turning OTP_REQUIRED / WRONG_OTP /
// OTP_LOCKED replies into dialog feedback, and the 4-box code form
// (Confirm only with 4 digits, attempts left, locked until).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vendra_rider/features/rider/models/handover_code.dart';
import 'package:vendra_rider/features/rider/models/rider_models.dart';
import 'package:vendra_rider/features/rider/widgets/handover_code_dialog.dart';

void main() {
  final now = DateTime(2026, 11, 15, 15, 0);

  group('HandoverCodeFeedback.fromError', () {
    test('wrong code keeps the attempts left', () {
      final f = HandoverCodeFeedback.fromError(1,
          code: 'WRONG_OTP', data: {'attemptsLeft': 3}, message: 'Wrong delivery code. 3 attempt(s) left.', now: now)!;
      expect(f.attemptsLeft, 3);
      expect(f.isLocked(now), isFalse);
    });

    test('the last wrong code locks for about 10 minutes', () {
      final f = HandoverCodeFeedback.fromError(1, code: 'WRONG_OTP', data: {'attemptsLeft': 0}, message: 'x', now: now)!;
      expect(f.lockedUntil, now.add(const Duration(minutes: 10)));
      expect(f.isLocked(now), isTrue);
    });

    test('a lockout carries the server time', () {
      final until = DateTime.utc(2026, 11, 15, 10, 8);
      final f = HandoverCodeFeedback.fromError(1,
          code: 'OTP_LOCKED', data: {'lockedUntil': until.toIso8601String()}, message: 'Locked', now: now)!;
      expect(f.lockedUntil, until.toLocal());
    });

    test('a missing code asks for it; other errors are not code errors', () {
      expect(HandoverCodeFeedback.fromError(1, code: 'OTP_REQUIRED', data: null, message: 'Ask')?.message, 'Ask');
      expect(HandoverCodeFeedback.fromError(1, code: 'OUTSIDE_GEOFENCE', data: null, message: 'Far'), isNull);
    });

    test('active orders say when a code is needed', () {
      expect(RiderOrder.fromJson(const {'id': 1, 'status': 'on_the_way', 'otpRequired': true}).otpRequired, isTrue);
      expect(RiderOrder.fromJson(const {'id': 1, 'status': 'on_the_way'}).otpRequired, isFalse);
    });
  });

  group('HandoverCodeForm', () {
    Future<void> pump(WidgetTester tester, {HandoverCodeFeedback? feedback, ValueChanged<String>? onSubmit}) =>
        tester.pumpWidget(MaterialApp(
          home: Scaffold(
            body: HandoverCodeForm(
              busy: false,
              feedback: feedback,
              onSubmit: onSubmit ?? (_) {},
              onCancel: () {},
              onUnavailable: () {},
            ),
          ),
        ));

    ElevatedButton confirm(WidgetTester tester) => tester.widget<ElevatedButton>(find.byType(ElevatedButton));

    testWidgets('confirms only once 4 digits are entered', (tester) async {
      String? sent;
      await pump(tester, onSubmit: (c) => sent = c);
      expect(find.textContaining('Ask the customer for their delivery code'), findsOneWidget);
      expect(confirm(tester).onPressed, isNull);

      await tester.enterText(find.byType(TextField), '12a3');
      await tester.pump();
      expect(confirm(tester).onPressed, isNull); // letters are dropped: only 3 digits

      await tester.enterText(find.byType(TextField), '12345');
      await tester.pump();
      expect(find.text('5'), findsNothing); // capped at 4
      await tester.tap(find.text('Confirm delivery'));
      expect(sent, '1234');
    });

    testWidgets('shows the attempts left after a wrong code', (tester) async {
      await pump(tester, feedback: const HandoverCodeFeedback(1, 'Wrong delivery code.', attemptsLeft: 2));
      expect(find.text('Wrong code. 2 attempts left.'), findsOneWidget);
    });

    testWidgets('a locked handover says until when and cannot be confirmed', (tester) async {
      final until = DateTime.now().add(const Duration(minutes: 9));
      await pump(tester, feedback: HandoverCodeFeedback(1, 'Locked', lockedUntil: until));
      expect(find.textContaining('locked until'), findsOneWidget);
      await tester.enterText(find.byType(TextField), '1234');
      await tester.pump();
      expect(confirm(tester).onPressed, isNull);
      // Dispose the form (cancels its lock timer)
      await tester.pumpWidget(const SizedBox());
    });
  });
}
