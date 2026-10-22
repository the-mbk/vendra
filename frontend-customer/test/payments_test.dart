// Card payments, withdrawals, wallet ledger and platform-config parsing —
// shapes copied from the live development backend and the Vendra Pay sandbox.
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vendra_customer/vendra_core.dart';

void main() {
  group('WalletTransaction', () {
    WalletTransaction tx(String type, {String? reference, int? orderId}) => WalletTransaction.fromJson({
          'id': 1,
          'orderId': orderId,
          'type': type,
          'amount': 500,
          'balanceAfter': 1500,
          'description': 'x',
          'reference': reference,
          'createdAt': '2026-10-12T18:50:49.530Z',
        });

    test('every type has a readable label, icon and sign', () {
      const expected = {
        'deposit': ('Card top-up', false),
        'opening_balance': ('Opening balance', false),
        'escrow_hold': ('Paid into escrow', true),
        'escrow_refund': ('Refund', false),
        'escrow_release': ('Payment received', false),
        'rider_payout': ('Delivery earnings', false),
        'withdrawal': ('Withdrawal', true),
        'withdrawal_reversal': ('Withdrawal returned', false),
      };
      expected.forEach((type, e) {
        final t = tx(type);
        expect(t.label, e.$1, reason: type);
        expect(t.isDebit, e.$2, reason: type);
        expect(t.signedAmount, e.$2 ? -500 : 500, reason: type);
        expect(t.icon, isNot(Icons.swap_vert), reason: type);
      });
      expect(tx('withdrawal').amountText, '− Rs. 500');
      expect(tx('deposit').amountText, '+ Rs. 500');
    });

    test('unknown types fall back to a humanised label', () {
      final t = tx('loyalty_bonus');
      expect(t.label, 'Loyalty bonus');
      expect(t.isDebit, isFalse);
      expect(t.icon, Icons.swap_vert);
    });

    test('reference is kept, blank reference becomes null, order shown in title', () {
      expect(tx('deposit', reference: 'pi_7WZb1pputG4QLCdK').reference, 'pi_7WZb1pputG4QLCdK');
      expect(tx('withdrawal', reference: '  ').reference, isNull);
      expect(tx('escrow_hold', orderId: 3).title, 'Paid into escrow · Order #3');
      expect(tx('deposit').title, 'Card top-up');
    });

    test('WalletSummary parses the /api/wallet body', () {
      final s = WalletSummary.fromJson({
        'balance': '115953.00',
        'transactions': [
          {'id': 10, 'orderId': null, 'type': 'withdrawal', 'amount': 500, 'balanceAfter': 115953, 'reference': 'po_A'},
        ],
      });
      expect(s.balance, 115953);
      expect(s.transactions.single.reference, 'po_A');
    });
  });

  group('PaymentModel / PaymentResult', () {
    final otpBody = {
      'success': true,
      'data': {
        'payment': {
          'id': 2,
          'purpose': 'topup',
          'amount': 100,
          'status': 'requires_action',
          'card': {'brand': 'visa', 'last4': '3184'},
          'gatewayIntentId': 'pi_7WZb1pputG4QLCdK',
          'nextAction': {'type': 'otp', 'attemptsLeft': 3, 'hint': 'Sandbox code: 123456'},
          'failureMessage': null,
          'orderId': null,
          'orderError': null,
          'createdAt': '2026-10-12T18:50:39.369Z',
        },
        'order': null,
        'walletBalance': 116353,
      },
    };

    test('requires_action carries the OTP step', () {
      final r = PaymentResult.fromBody(otpBody)!;
      expect(r.payment.needsOtp, isTrue);
      expect(r.payment.nextAction!.attemptsLeft, 3);
      expect(r.payment.nextAction!.hint, 'Sandbox code: 123456');
      expect(r.payment.cardLabel, 'Visa •••• 3184');
      expect(r.order, isNull);
      expect(r.walletBalance, 116353);
    });

    test('a 402 decline body still parses', () {
      final r = PaymentResult.fromBody({
        'success': false,
        'message': 'Your card was declined.',
        'data': {
          'payment': {
            'id': 4,
            'purpose': 'topup',
            'amount': 100,
            'status': 'failed',
            'card': {'brand': 'visa', 'last4': '0002'},
            'failureMessage': 'Your card was declined.',
          },
          'order': null,
          'walletBalance': 116453,
        },
      })!;
      expect(r.payment.isFailed, isTrue);
      expect(r.payment.failureMessage, 'Your card was declined.');
      expect(PaymentResult.fromBody({'success': false, 'message': 'x', 'code': 'TOKEN_EXPIRED'}), isNull);
    });

    test('card checkout with an order, and one that could not be placed', () {
      final placed = PaymentResult.fromJson({
        'payment': {'id': 5, 'purpose': 'checkout', 'amount': '10148.00', 'status': 'succeeded', 'orderId': 9},
        'order': {'id': 9, 'status': 'pending', 'totalAmount': 10148, 'items': []},
        'walletBalance': 0,
      });
      expect(placed.payment.isSucceeded, isTrue);
      expect(placed.payment.amount, 10148);
      expect(placed.order!.id, 9);
      expect(placed.payment.cardLabel, 'card');

      final notPlaced = PaymentModel.fromJson({
        'id': 6,
        'purpose': 'checkout',
        'amount': 500,
        'status': 'succeeded',
        'orderError': 'Only 0 left of Anker PowerCore.',
      });
      expect(notPlaced.orderError, isNotNull);
      expect(notPlaced.orderId, isNull);
    });

    test('CardPaymentOutcome messages', () {
      final ok = CardPaymentOutcome(result: PaymentResult.fromJson({
        'payment': {'id': 1, 'amount': 500, 'status': 'succeeded', 'card': {'brand': 'mastercard', 'last4': '4444'}},
        'walletBalance': 900,
      }));
      expect(ok.succeeded, isTrue);
      expect(ok.message, 'Paid Rs. 500 with Mastercard •••• 4444.');
      expect(ok.walletBalance, 900);
      const refused = CardPaymentOutcome(errorMessage: 'Not enough stock', errorCode: 'INSUFFICIENT_STOCK');
      expect(refused.succeeded, isFalse);
      expect(refused.message, 'Not enough stock');
    });
  });

  group('WithdrawalModel', () {
    test('parses POST /api/withdrawals and maps statuses', () {
      final r = WithdrawalResult.fromJson({
        'withdrawal': {
          'id': 2,
          'amount': 500,
          'status': 'in_transit',
          'card': {'brand': 'visa', 'last4': '5556'},
          'gatewayPayoutId': 'po_AtgYQzZrIhIYM7RV',
          'failureMessage': null,
          'createdAt': '2026-10-12T18:50:49.530Z',
          'settledAt': null,
        },
        'walletBalance': 115953,
      });
      expect(r.withdrawal.isOnItsWay, isTrue);
      expect(r.withdrawal.statusLabel, 'In transit');
      expect(r.withdrawal.cardLabel, 'Visa •••• 5556');
      expect(r.walletBalance, 115953);

      expect(WithdrawalModel.fromJson({'id': 1, 'amount': 1, 'status': 'paid'}).statusLabel, 'Paid');
      final failed = WithdrawalModel.fromJson({'id': 1, 'amount': 1, 'status': 'failed', 'failureMessage': 'Bounced'});
      expect(failed.statusLabel, 'Returned');
      expect(failed.isFailed, isTrue);
      expect(failed.cardLabel, 'your card');
    });
  });

  group('Gateway objects', () {
    test('CardToken and TestCardList', () {
      final t = CardToken.fromJson({
        'id': 'tok_9DD0RZjX5N1KLekf',
        'card': {'brand': 'visa', 'last4': '3184', 'funding': 'credit', 'exp_month': 12, 'exp_year': 2030},
      });
      expect(t.id, 'tok_9DD0RZjX5N1KLekf');
      expect(t.card.expMonth, 12);
      expect(t.card.funding, 'credit');

      final list = TestCardList.fromJson({
        'object': 'list',
        'otp': '123456',
        'data': [
          {'number': '4000056655665556', 'brand': 'visa', 'funding': 'debit', 'label': 'Debit card — payments and payouts succeed'},
          {'number': '4242424242424242', 'brand': 'visa', 'funding': 'credit', 'label': 'Payment succeeds'},
        ],
      });
      expect(list.otp, '123456');
      expect(list.cards.first.formattedNumber, '4000 0566 5566 5556');
      expect(list.cards.first.isDebit, isTrue);
      expect(list.cards.first.mentionsPayouts, isTrue);
      expect(list.cards.last.last4, '4242');
    });

    test('gateway URL uses the API host for loopback addresses', () {
      expect(CardGateway.resolveGatewayUrl('http://localhost:4242', 'http://10.0.2.2:3000'), 'http://10.0.2.2:4242');
      expect(CardGateway.resolveGatewayUrl('http://127.0.0.1:4242/', 'http://192.168.1.20:3000'),
          'http://192.168.1.20:4242');
      expect(CardGateway.resolveGatewayUrl('http://localhost:4242', 'http://localhost:3000'), 'http://localhost:4242');
      expect(CardGateway.resolveGatewayUrl('https://pay.vendra.pk', 'http://10.0.2.2:3000'), 'https://pay.vendra.pk');
    });

    test('gateway errors become readable exceptions', () {
      DioException err(int status, Map<String, dynamic> body) {
        final req = RequestOptions(path: '/v1/tokens');
        return DioException(
          requestOptions: req,
          response: Response(requestOptions: req, statusCode: status, data: body),
          type: DioExceptionType.badResponse,
        );
      }

      final otp = CardGateway.toException(err(402, {
        'error': {'type': 'card_error', 'code': 'incorrect_otp', 'message': 'That code is incorrect. 2 attempts left.'},
      }));
      expect(otp.isIncorrectOtp, isTrue);
      expect(otp.message, 'That code is incorrect. 2 attempts left.');

      final testOnly = CardGateway.toException(err(402, {
        'error': {'type': 'card_error', 'code': 'test_card_required', 'message': 'raw'},
      }));
      expect(testOnly.message, contains('test cards'));

      final offline = CardGateway.toException(DioException(
        requestOptions: RequestOptions(path: '/'),
        type: DioExceptionType.connectionError,
      ));
      expect(offline.code, 'network');
    });
  });

  group('AppConfig', () {
    test('parses /api/public-config', () {
      final c = AppConfig.fromJson({
        'mode': 'development',
        'features': {'manualLocation': true, 'testCards': true, 'fastTimers': true, 'demoLogin': true},
        'deliveryFee': 150,
        'disputeWindowMinutes': 2,
        'geofenceMeters': 200,
        'taskRadiusKm': 5,
        'defaultBuffer': 5,
        'vendorAcceptTimeoutMinutes': 5,
        'riderAssignTimeoutMinutes': 10,
        'payments': {
          'gatewayUrl': 'http://localhost:4242',
          'publishableKey': 'pk_test_vendra',
          'minTopup': 100,
          'maxTopup': 500000,
          'minWithdrawal': 500,
        },
        'demoAccounts': [
          {'role': 'customer', 'name': 'Ahmed Raza', 'email': 'ahmed@customer.pk', 'note': 'Clifton, Karachi', 'password': 'password123'},
          {'role': 'vendor', 'name': 'V', 'email': 'v@vendor.pk', 'password': 'password123'},
        ],
      });
      expect(c.isDevelopment, isTrue);
      expect(c.fromServer, isTrue);
      expect(c.features.testCards, isTrue);
      expect(c.payments.isAvailable, isTrue);
      expect(c.payments.minWithdrawal, 500);
      expect(c.deliveryFee, 150);
      expect(c.riderAssignTimeoutMinutes, 10);
      expect(c.demoAccountsFor('customer').single.email, 'ahmed@customer.pk');
    });

    test('defaults are production-safe', () {
      const c = AppConfig.fallback;
      expect(c.isDevelopment, isFalse);
      expect(c.fromServer, isFalse);
      expect(c.features.testCards || c.features.demoLogin || c.features.manualLocation, isFalse);
      expect(c.payments.isAvailable, isFalse);
      expect(c.demoAccounts, isEmpty);

      final prod = AppConfig.fromJson({'mode': 'production', 'demoAccounts': []});
      expect(prod.isDevelopment, isFalse);
      expect(prod.features.demoLogin, isFalse);
    });
  });

  group('CardUtils', () {
    test('formats numbers in groups of four', () {
      expect(CardUtils.formatNumber('4242424242424242'), '4242 4242 4242 4242');
      expect(CardUtils.formatNumber('4242 42a'), '4242 42');
      expect(CardUtils.formatNumber('1' * 25).replaceAll(' ', '').length, CardUtils.maxDigits);
    });

    test('detects the brand', () {
      expect(CardUtils.detectBrand('4242'), 'visa');
      expect(CardUtils.detectBrand('5555 5555'), 'mastercard');
      expect(CardUtils.detectBrand('2221000000000009'), 'mastercard');
      expect(CardUtils.detectBrand('3782'), 'amex');
      expect(CardUtils.detectBrand('6011'), 'unknown');
      expect(CardUtils.maskedLabel('visa', '4242'), 'Visa •••• 4242');
    });

    test('validates number, expiry and CVC', () {
      expect(CardUtils.validateNumber('4242 4242 4242 4242'), isNull);
      expect(CardUtils.validateNumber('4000 0027 6000 3184'), isNull);
      expect(CardUtils.validateNumber('4242 4242 4242 4241'), isNotNull);
      expect(CardUtils.validateNumber('4242'), isNotNull);

      final now = DateTime(2026, 10, 12);
      expect(CardUtils.formatExpiry('1230'), '12/30');
      expect(CardUtils.parseExpiry('12/30'), (month: 12, year: 2030));
      expect(CardUtils.validateExpiry('10/26', now: now), isNull);
      expect(CardUtils.validateExpiry('09/26', now: now), 'This card has expired');
      expect(CardUtils.validateExpiry('13/30', now: now), 'Use MM/YY');

      expect(CardUtils.validateCvc('123'), isNull);
      expect(CardUtils.validateCvc('12'), isNotNull);
      expect(CardUtils.validateCvc('123', brand: 'amex'), isNotNull);
    });
  });

  group('DevBanner', () {
    tearDown(() => AppConfig.debugSet(AppConfig.fallback));

    testWidgets('shows only in development mode', (tester) async {
      AppConfig.debugSet(AppConfig.fallback);
      await tester.pumpWidget(const MaterialApp(home: DevBanner(child: Text('app'))));
      expect(find.text('DEVELOPMENT MODE'), findsNothing);

      AppConfig.debugSet(AppConfig.fromJson({'mode': 'development'}));
      await tester.pump();
      expect(find.text('DEVELOPMENT MODE'), findsOneWidget);
      expect(find.text('app'), findsOneWidget);
    });
  });

  group('Amounts', () {
    test('formatRupees and validateAmount', () {
      expect(formatRupees(500000), 'Rs. 500,000');
      expect(formatRupees(1234.5), 'Rs. 1,234.50');
      expect(validateAmount('99', min: 100, max: 500000), contains('minimum'));
      expect(validateAmount('600000', min: 100, max: 500000), contains('maximum'));
      expect(validateAmount('1,000', min: 100, max: 500000), isNull);
      expect(validateAmount('10.555', min: 1, max: 500), isNotNull);
      expect(validateAmount('', min: 1, max: 5), isNotNull);
    });
  });
}
