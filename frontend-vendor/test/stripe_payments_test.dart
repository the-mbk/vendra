// Stripe as the card provider: config parsing, the stripe_sdk 3-D Secure step,
// Stripe payout accounts and withdrawals, and the Stripe card / payout sheets.
// Shapes copied from the backend (payments.service.js, payoutAccounts.service.js).
// Kept identical in the customer, vendor and rider apps (only the package import differs).
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_stripe/flutter_stripe.dart' show FailureCode, LocalizedErrorMessage, StripeConfigException, StripeException;
import 'package:flutter_test/flutter_test.dart';
import 'package:vendra_vendor/vendra_core.dart';

/// Payout-account API stand-in: answers from a queue and records what was opened
class _FakePayoutAccounts extends PayoutAccounts {
  final List<PayoutAccountStatus> statuses;
  final bool openSucceeds;
  final List<String> opened = [];
  int onboardingCalls = 0;
  int fetchCalls = 0;

  _FakePayoutAccounts(this.statuses, {this.openSucceeds = true});

  @override
  Future<PayoutAccountStatus> fetch() async {
    fetchCalls++;
    return statuses.length > 1 ? statuses.removeAt(0) : statuses.first;
  }

  @override
  Future<String> onboardingUrl() async {
    onboardingCalls++;
    return 'https://connect.stripe.com/setup/e/acct_1/abc';
  }

  @override
  Future<String> dashboardUrl() async => 'https://connect.stripe.com/express/acct_1/xyz';

  @override
  Future<bool> openUrl(String url) async {
    opened.add(url);
    return openSucceeds;
  }
}

PayoutAccountStatus _status({Map<String, dynamic>? account, String? currency = 'usd'}) =>
    PayoutAccountStatus.fromJson({
      'provider': 'stripe',
      'required': true,
      'account': account,
      'currency': currency,
      'pkrPerUnit': 280,
    });

/// Opens [sheet] as a bottom sheet and records what it closed with
Future<List<Object?>> _openSheet(WidgetTester tester, Widget sheet) async {
  final results = <Object?>[];
  await tester.pumpWidget(MaterialApp(
    home: Builder(
      builder: (context) => Scaffold(
        body: Center(
          child: ElevatedButton(
            onPressed: () async => results.add(await showModalBottomSheet<Object?>(
              context: context,
              isScrollControlled: true,
              builder: (_) => sheet,
            )),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return results;
}

void main() {
  tearDown(() => AppConfig.debugSet(AppConfig.fallback));

  group('PaymentSettings', () {
    test('Stripe needs only the publishable key and pays out to Stripe accounts', () {
      final s = PaymentSettings.fromJson({
        'provider': 'stripe',
        'publishableKey': 'pk_test_51abc',
        'gatewayUrl': null,
        'payoutsTo': 'stripe_account',
        'minTopup': 100,
        'maxTopup': 500000,
        'minWithdrawal': 500,
      });
      expect(s.isStripe, isTrue);
      expect(s.isAvailable, isTrue);
      expect(s.gatewayUrl, '');
      expect(s.paysOutToStripeAccount, isTrue);
      expect(StripePayments.shouldInitialise(s), isTrue);
    });

    test('Stripe without a key is unavailable and not initialised', () {
      final s = PaymentSettings.fromJson({'provider': 'stripe', 'publishableKey': '', 'payoutsTo': 'stripe_account'});
      expect(s.isAvailable, isFalse);
      expect(StripePayments.shouldInitialise(s), isFalse);
    });

    test('Vendra Pay is unchanged: needs the gateway URL, pays out to cards', () {
      final s = PaymentSettings.fromJson({
        'provider': 'vendrapay',
        'gatewayUrl': 'http://localhost:4242',
        'publishableKey': 'pk_test_vendra',
        'payoutsTo': 'card',
      });
      expect(s.isStripe, isFalse);
      expect(s.isAvailable, isTrue);
      expect(s.paysOutToStripeAccount, isFalse);
      expect(StripePayments.shouldInitialise(s), isFalse);
      // An older backend without provider/payoutsTo
      final old = PaymentSettings.fromJson({'gatewayUrl': 'http://localhost:4242', 'publishableKey': 'pk_test_vendra'});
      expect(old.provider, 'vendrapay');
      expect(old.payoutsTo, 'card');
      expect(old.isAvailable, isTrue);
      expect(PaymentSettings.fromJson({'publishableKey': 'pk_test_vendra'}).isAvailable, isFalse);
    });
  });

  group('Stripe 3-D Secure', () {
    test('a requires_action payment with stripe_sdk carries the client secret', () {
      final p = PaymentModel.fromJson({
        'id': 9,
        'purpose': 'topup',
        'amount': 5000,
        'status': 'requires_action',
        'gatewayIntentId': 'pi_3Qabc',
        'nextAction': {'type': 'stripe_sdk', 'clientSecret': 'pi_3Qabc_secret_xyz'},
      });
      expect(p.needsStripeAction, isTrue);
      expect(p.needsOtp, isFalse);
      expect(p.nextAction!.clientSecret, 'pi_3Qabc_secret_xyz');
    });

    test('the Vendra Pay OTP step is unchanged', () {
      final p = PaymentModel.fromJson({
        'id': 1,
        'status': 'requires_action',
        'nextAction': {'type': 'otp', 'attemptsLeft': 3, 'hint': '123456'},
      });
      expect(p.needsOtp, isTrue);
      expect(p.needsStripeAction, isFalse);
      expect(p.nextAction!.clientSecret, isNull);
    });

    test('runStripeAction: an answer refreshes, a closed check counts as cancelled', () async {
      Future<String?> ok(String _) async => 'succeeded';
      Future<String?> fails(String _) async =>
          throw const CardGatewayException('We are unable to authenticate your payment method.',
              code: 'payment_intent_authentication_failure');
      Future<String?> closed(String _) async => throw const CardGatewayException('closed', code: 'canceled');
      Future<String?> offline(String _) async => throw const CardGatewayException('offline', code: 'network');

      expect(await CardPaymentFlow.runStripeAction('pi_secret', handleNextAction: ok), isTrue);
      expect(await CardPaymentFlow.runStripeAction('pi_secret', handleNextAction: fails), isTrue);
      expect(await CardPaymentFlow.runStripeAction('pi_secret', handleNextAction: closed), isFalse);
      expect(await CardPaymentFlow.runStripeAction('pi_secret', handleNextAction: offline), isFalse);
      expect(await CardPaymentFlow.runStripeAction(null, handleNextAction: ok), isFalse);
      expect(await CardPaymentFlow.runStripeAction('', handleNextAction: ok), isFalse);
    });
  });

  group('StripePayments helpers', () {
    test('brand names match the gateway ones', () {
      expect(StripePayments.normaliseBrand('Visa'), 'visa');
      expect(StripePayments.normaliseBrand('MasterCard'), 'mastercard');
      expect(StripePayments.normaliseBrand('AmericanExpress'), 'amex');
      expect(StripePayments.normaliseBrand('amex'), 'amex');
      expect(StripePayments.normaliseBrand(null), 'unknown');
      expect(CardInfo(brand: StripePayments.normaliseBrand('Visa'), last4: '4242').label, contains('4242'));
    });

    test('Stripe errors become readable CardGatewayExceptions', () {
      final cancelled = StripePayments.toException(
          const StripeException(error: LocalizedErrorMessage(code: FailureCode.Canceled, message: 'The payment has been canceled')));
      expect(cancelled.isCancelled, isTrue);

      final declined = StripePayments.toException(const StripeException(
        error: LocalizedErrorMessage(
          code: FailureCode.Failed,
          message: 'Your card was declined.',
          localizedMessage: 'Your card was declined.',
          stripeErrorCode: 'card_declined',
        ),
      ));
      expect(declined.message, 'Your card was declined.');
      expect(declined.code, 'card_declined');
      expect(declined.isCancelled, isFalse);

      expect(StripePayments.toException(const StripeConfigException('Publishable key is not set')).code, 'not_configured');
      const own = CardGatewayException('x', code: 'network');
      expect(identical(StripePayments.toException(own), own), isTrue);
      expect(StripePayments.toException(_JsLikeError()).message, 'Your card number is incomplete.');
      expect(StripePayments.toException(Object()).message, isNotEmpty);
    });

    test('test cards cover success, 3-D Secure and a decline', () {
      expect(StripePayments.testCards.map((c) => c.number), [
        '4242 4242 4242 4242',
        '4000 0025 0000 3155',
        '4000 0000 0000 9995',
      ]);
    });
  });

  group('Stripe payout accounts', () {
    test('parses GET /api/payouts/account and works out the state', () {
      expect(_status().state, PayoutAccountState.none);
      expect(_status(account: {'id': 'acct_1Qxyz9', 'detailsSubmitted': false, 'payoutsEnabled': false}).state,
          PayoutAccountState.incomplete);
      expect(_status(account: {'id': 'acct_1Qxyz9', 'detailsSubmitted': true, 'payoutsEnabled': false}).state,
          PayoutAccountState.checking);
      final ready = _status(account: {'id': 'acct_1Qxyz9', 'detailsSubmitted': true, 'payoutsEnabled': true});
      expect(ready.state, PayoutAccountState.ready);
      expect(ready.isReady, isTrue);
      expect(ready.account!.shortId, '…xyz9');
      final card = PayoutAccountStatus.fromJson({'provider': 'vendrapay', 'required': false, 'account': null});
      expect(card.state, PayoutAccountState.notRequired);
      expect(card.isReady, isTrue);
    });

    test('converts rupees like the backend does', () {
      final s = _status();
      expect(s.convert(5000), 17.86); // 500000 paisa / 280 = 1785.7 → 1786 cents
      expect(s.convert(500), 1.79);
      expect(s.convert(0.01), 0.01); // at least one cent
      expect(s.conversionText(5000), r'≈ $17.86 at Rs 280/USD');
      expect(_status(currency: null).conversionText(5000), isNull);
      expect(formatForeignAmount(5, 'eur'), '€5.00');
      expect(formatForeignAmount(12.5, 'aed'), '12.50 AED');
    });

    test('a withdrawal to a Stripe account shows what it received', () {
      final w = WithdrawalModel.fromJson({
        'id': 4,
        'amount': 5000,
        'status': 'paid',
        'provider': 'stripe',
        'card': null,
        'destinationAccount': 'acct_1Qxyz9',
        'gatewayAmount': 17.86,
        'gatewayCurrency': 'usd',
        'gatewayPayoutId': 'tr_1Qabc',
      });
      expect(w.toStripeAccount, isTrue);
      expect(w.cardLabel, 'your Stripe account');
      expect(w.convertedLabel, r'$17.86');
      expect(w.destinationAccount, 'acct_1Qxyz9');

      final card = WithdrawalModel.fromJson({
        'id': 5,
        'amount': 1000,
        'status': 'in_transit',
        'provider': 'vendrapay',
        'card': {'brand': 'visa', 'last4': '4242'},
        'gatewayAmount': null,
        'gatewayCurrency': null,
      });
      expect(card.toStripeAccount, isFalse);
      expect(card.cardLabel, contains('4242'));
      expect(card.convertedLabel, isNull);
    });
  });

  group('StripeCardSheet', () {
    testWidgets('pays only once the card is complete and returns the PaymentMethod', (tester) async {
      late ValueChanged<bool> setComplete;
      final results = await _openSheet(
        tester,
        StripeCardSheet(
          actionLabel: 'Pay Rs. 500',
          cardFieldBuilder: (onComplete) {
            setComplete = onComplete;
            return const SizedBox(height: 48, child: Text('stripe card field'));
          },
          createPaymentMethod: () async =>
              const CardToken(id: 'pm_1Qabc', card: CardInfo(brand: 'visa', last4: '4242')),
        ),
      );
      expect(find.text('stripe card field'), findsOneWidget);
      expect(find.text('Stripe test cards'), findsNothing); // production config

      await tester.tap(find.text('Pay Rs. 500'));
      await tester.pumpAndSettle();
      expect(results, isEmpty); // incomplete card: the button does nothing

      setComplete(true);
      await tester.pump();
      await tester.tap(find.text('Pay Rs. 500'));
      await tester.pumpAndSettle();
      expect(results.single, isA<CardToken>());
      expect((results.single as CardToken).id, 'pm_1Qabc');
    });

    testWidgets('shows a refused card and the test cards in development', (tester) async {
      AppConfig.debugSet(AppConfig.fromJson({
        'mode': 'development',
        'features': {'testCards': true},
      }));
      final copied = <String>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') copied.add((call.arguments as Map)['text'] as String);
        return null;
      });
      addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));

      late ValueChanged<bool> setComplete;
      final results = await _openSheet(
        tester,
        StripeCardSheet(
          actionLabel: 'Pay',
          cardFieldBuilder: (onComplete) {
            setComplete = onComplete;
            return const SizedBox(height: 48);
          },
          createPaymentMethod: () async => throw const CardGatewayException('Your card number is invalid.'),
        ),
      );
      expect(find.text('Stripe test cards'), findsOneWidget);
      await tester.tap(find.text('4000 0025 0000 3155'));
      await tester.pump();
      expect(copied, ['4000002500003155']);

      setComplete(true);
      await tester.pump();
      await tester.tap(find.text('Pay'));
      await tester.pumpAndSettle();
      expect(find.text('Your card number is invalid.'), findsOneWidget);
      expect(results, isEmpty);
    });
  });

  group('PayoutAccountSheet', () {
    testWidgets('no account: sets up on Stripe, then closes once the account is ready', (tester) async {
      final ready = _status(account: {'id': 'acct_1Qxyz9', 'detailsSubmitted': true, 'payoutsEnabled': true});
      final accounts = _FakePayoutAccounts([ready]);
      final results = await _openSheet(tester, PayoutAccountSheet(status: _status(), accounts: accounts));

      expect(find.text('Set up payouts'), findsOneWidget);
      await tester.tap(find.text('Set up payouts with Stripe'));
      await tester.pumpAndSettle();
      expect(accounts.opened, ['https://connect.stripe.com/setup/e/acct_1/abc']);
      expect(find.text("I've finished"), findsOneWidget);

      await tester.tap(find.text("I've finished"));
      await tester.pumpAndSettle();
      expect(results.single, isA<PayoutAccountStatus>());
      expect((results.single as PayoutAccountStatus).isReady, isTrue);
    });

    testWidgets('still checking: says so and stays open', (tester) async {
      final checking = _status(account: {'id': 'acct_1Qxyz9', 'detailsSubmitted': true, 'payoutsEnabled': false});
      final accounts = _FakePayoutAccounts([checking]);
      final results = await _openSheet(tester, PayoutAccountSheet(status: checking, accounts: accounts));

      expect(find.text('Stripe is checking your details'), findsOneWidget);
      expect(find.text('Update details on Stripe'), findsOneWidget);
      await tester.tap(find.text('Check again'));
      await tester.pumpAndSettle();
      expect(accounts.fetchCalls, 1);
      expect(find.textContaining("hasn't finished checking"), findsOneWidget);
      expect(results, isEmpty);
    });

    testWidgets('setup not finished offers "Finish setup"; a blocked tab gets an "Open Stripe" button',
        (tester) async {
      final incomplete = _status(account: {'id': 'acct_1Qxyz9', 'detailsSubmitted': false, 'payoutsEnabled': false});
      final accounts = _FakePayoutAccounts([incomplete], openSucceeds: false);
      await _openSheet(tester, PayoutAccountSheet(status: incomplete, accounts: accounts));

      await tester.tap(find.text('Finish setup'));
      await tester.pumpAndSettle();
      expect(accounts.onboardingCalls, 1);
      expect(find.text('Open Stripe'), findsOneWidget);
      await tester.tap(find.text('Open Stripe'));
      await tester.pumpAndSettle();
      expect(accounts.opened.length, 2);
    });
  });

  group('Amount sheet note', () {
    testWidgets('shows the converted amount for a valid amount only', (tester) async {
      final status = _status(account: {'id': 'acct_1', 'detailsSubmitted': true, 'payoutsEnabled': true});
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: ElevatedButton(
              onPressed: () => showAmountSheet(
                context,
                title: 'Withdraw to Stripe',
                min: 500,
                max: 10000,
                initial: 5000,
                note: status.conversionText,
                footer: PayoutDashboardLink(accounts: _FakePayoutAccounts([status])),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text(r'≈ $17.86 at Rs 280/USD'), findsOneWidget);
      expect(find.text('View Stripe account'), findsOneWidget);

      await tester.enterText(find.byType(TextFormField), '100'); // below the minimum
      await tester.pump();
      expect(find.textContaining('≈'), findsNothing);
    });
  });
}

/// Stripe.js reports errors on the web as plain `{ type, code, message }` objects
class _JsLikeError {
  String get message => 'Your card number is incomplete.';
  String get code => 'incomplete_number';
}
