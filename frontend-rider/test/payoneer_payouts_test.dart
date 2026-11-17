// Payoneer as the payout provider (payments.payoutsTo == 'payoneer'): config
// parsing, the payout-account states and wording, and the whole withdrawal
// (account check → amount → POST /api/withdrawals → result dialog).
// Shapes copied from the backend (payoutAccounts.service.js, payments.service.js).
// Kept identical in the customer, vendor and rider apps (only the package import differs).
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vendra_rider/vendra_core.dart';

/// Payout-account API stand-in: answers from a queue and records what was opened and sent
class _FakePayoutAccounts extends PayoutAccounts {
  final List<PayoutAccountStatus> statuses;
  final Object? withdrawError;

  /// What POST /api/withdrawals answers with: in_transit, or paid when Payoneer was quick
  final String withdrawStatus;
  final List<String> opened = [];
  final List<double> withdrawn = [];
  int fetchCalls = 0;

  _FakePayoutAccounts(this.statuses, {this.withdrawError, this.withdrawStatus = 'in_transit'});

  @override
  Future<PayoutAccountStatus> fetch() async {
    fetchCalls++;
    return statuses.length > 1 ? statuses.removeAt(0) : statuses.first;
  }

  @override
  Future<String> onboardingUrl() async => 'https://payouts.sandbox.payoneer.com/partners/lp.aspx?token=abc';

  @override
  Future<String> dashboardUrl() async => 'https://myaccount.sandbox.payoneer.com/';

  @override
  Future<bool> openUrl(String url) async {
    opened.add(url);
    return true;
  }

  @override
  Future<WithdrawalResult> withdraw(double amount) async {
    withdrawn.add(amount);
    if (withdrawError != null) throw withdrawError!;
    return WithdrawalResult.fromJson({
      'withdrawal': {
        'id': 9,
        'amount': amount,
        'status': withdrawStatus,
        'provider': 'payoneer',
        'card': null,
        'destinationAccount': 'vendra-12',
        'gatewayAmount': 17.86,
        'gatewayCurrency': 'usd',
      },
      'walletBalance': 0,
    });
  }
}

/// GET /api/payouts/account with Payoneer; [account] null = never started
PayoutAccountStatus _payoneer([Map<String, dynamic>? account]) => PayoutAccountStatus.fromJson({
      'provider': 'payoneer',
      'required': true,
      'account': account,
      'currency': 'usd',
      'pkrPerUnit': 280,
    });

const _notRegistered = {'id': 'vendra-12', 'status': 'not_registered', 'detailsSubmitted': false, 'payoutsEnabled': false};
const _pending = {'id': 'vendra-12', 'status': 'pending', 'detailsSubmitted': true, 'payoutsEnabled': false};
const _active = {'id': 'vendra-12', 'status': 'active', 'detailsSubmitted': true, 'payoutsEnabled': true};

/// A development backend paying out through Payoneer
void _usePayoneerConfig({bool testCards = true}) => AppConfig.debugSet(AppConfig.fromJson({
      'mode': 'development',
      'features': {'testCards': testCards},
      'payments': {
        'provider': 'stripe',
        'publishableKey': 'pk_test_51abc',
        'payoutsTo': 'payoneer',
        'minWithdrawal': 500,
      },
    }));

/// Pumps a button that runs [onPressed] (which opens a sheet) and taps it
Future<void> _tapToOpen(WidgetTester tester, Future<void> Function(BuildContext context) onPressed) async {
  await tester.pumpWidget(MaterialApp(
    home: Builder(
      builder: (context) => Scaffold(
        body: Center(child: ElevatedButton(onPressed: () => onPressed(context), child: const Text('open'))),
      ),
    ),
  ));
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  tearDown(() => AppConfig.debugSet(AppConfig.fallback));

  group('PaymentSettings', () {
    test('payoutsTo payoneer: withdrawals go to the Payoneer account', () {
      final s = PaymentSettings.fromJson({'provider': 'stripe', 'publishableKey': 'pk_test_51abc', 'payoutsTo': 'payoneer'});
      expect(s.payoutsTo, 'payoneer');
      expect(s.payoutProvider, PayoutProvider.payoneer);
      expect(s.paysOutToAccount, isTrue);
      expect(s.paysOutToPayoneer, isTrue);
      expect(s.paysOutToStripeAccount, isFalse);
      expect(s.withdrawLabel, 'Withdraw to Payoneer');
      expect(s.payoutDestination, 'your Payoneer account');
    });

    test('Stripe accounts and cards keep their wording; anything unknown pays out to a card', () {
      final stripe = PaymentSettings.fromJson({'provider': 'stripe', 'payoutsTo': 'stripe_account'});
      expect(stripe.paysOutToAccount, isTrue);
      expect(stripe.paysOutToPayoneer, isFalse);
      expect(stripe.withdrawLabel, 'Withdraw to Stripe');
      expect(stripe.payoutDestination, 'your Stripe account');

      final card = PaymentSettings.fromJson({'provider': 'vendrapay', 'payoutsTo': 'card'});
      expect(card.paysOutToAccount, isFalse);
      expect(card.withdrawLabel, 'Withdraw to card');
      expect(card.payoutDestination, 'a debit card');
      expect(PaymentSettings.fromJson({'payoutsTo': 'paypal'}).payoutsTo, 'card');
    });
  });

  group('Payoneer payout account', () {
    test('parses each Payoneer status into a state', () {
      expect(_payoneer().state, PayoutAccountState.none);
      expect(_payoneer(_notRegistered).state, PayoutAccountState.incomplete);
      expect(_payoneer(_pending).state, PayoutAccountState.checking);
      final active = _payoneer(_active);
      expect(active.state, PayoutAccountState.ready);
      expect(active.isReady, isTrue);
      expect(active.account!.id, 'vendra-12');
      expect(active.account!.status, 'active');
      expect(active.isPayoneer, isTrue);
      expect(active.providerName, 'Payoneer');
      expect(active.conversionText(5000), r'≈ $17.86 at Rs 280/USD');
    });

    test('the provider names follow the API: stripe_connect is Stripe, card needs nothing', () {
      final stripe = PayoutAccountStatus.fromJson({'provider': 'stripe_connect', 'required': true, 'account': null});
      expect(stripe.isPayoneer, isFalse);
      expect(stripe.providerName, 'Stripe');
      final card = PayoutAccountStatus.fromJson({'provider': 'card', 'required': false, 'account': null});
      expect(card.payoutProvider, PayoutProvider.card);
      expect(card.state, PayoutAccountState.notRequired);
    });

    test('a Payoneer withdrawal shows what the account received', () {
      final w = WithdrawalModel.fromJson({
        'id': 9,
        'amount': 5000,
        'status': 'paid',
        'provider': 'payoneer',
        'card': null,
        'destinationAccount': 'vendra-12',
        'gatewayAmount': 17.86,
        'gatewayCurrency': 'usd',
      });
      expect(w.toPayoneer, isTrue);
      expect(w.toPayoutAccount, isTrue);
      expect(w.toStripeAccount, isFalse);
      expect(w.cardLabel, 'your Payoneer account');
      expect(w.convertedLabel, r'$17.86');
      expect(w.destinationAccount, 'vendra-12');
    });
  });

  group('PayoutAccountSheet with Payoneer', () {
    testWidgets('never started: links the Payoneer account, then closes once it is active', (tester) async {
      _usePayoneerConfig();
      final accounts = _FakePayoutAccounts([_payoneer(_active)]);
      final results = <PayoutAccountStatus?>[];
      await _tapToOpen(tester, (context) async {
        results.add(await showPayoutAccountSheet(context, status: _payoneer(), accounts: accounts));
      });

      expect(find.text('Link your Payoneer account'), findsNWidgets(2)); // title and button
      expect(find.textContaining('withdraw them to your bank in Pakistan'), findsOneWidget);
      expect(find.textContaining('create a free Payoneer account'), findsOneWidget);
      expect(find.text('Payoneer sandbox: any password works; use an email containing +fail to see a failed payout.'),
          findsOneWidget);
      expect(find.textContaining('Stripe'), findsNothing);

      await tester.tap(find.widgetWithText(VendraButton, 'Link your Payoneer account'));
      await tester.pumpAndSettle();
      expect(accounts.opened, ['https://payouts.sandbox.payoneer.com/partners/lp.aspx?token=abc']);
      expect(find.textContaining("Payoneer's page opened in your browser"), findsOneWidget);
      expect(find.text('Open Payoneer again'), findsOneWidget);

      await tester.tap(find.text("I've finished"));
      await tester.pumpAndSettle();
      expect(results.single?.isReady, isTrue);
    });

    testWidgets('not finished: "Finish linking on Payoneer" with the payee id; no sandbox hint in production',
        (tester) async {
      _usePayoneerConfig(testCards: false);
      final accounts = _FakePayoutAccounts([_payoneer(_notRegistered)]);
      await _tapToOpen(tester, (context) => showPayoutAccountSheet(context, status: _payoneer(_notRegistered), accounts: accounts));

      expect(find.text('Finish linking on Payoneer'), findsOneWidget);
      expect(find.text('Payoneer payee ID vendra-12'), findsOneWidget);
      expect(find.textContaining('Payoneer sandbox'), findsNothing);

      await tester.tap(find.text('Check again'));
      await tester.pumpAndSettle();
      expect(find.text("Payoneer says your account isn't linked yet."), findsOneWidget);
    });

    testWidgets('pending: Payoneer is reviewing, with "Check again" and the account page', (tester) async {
      _usePayoneerConfig();
      final accounts = _FakePayoutAccounts([_payoneer(_pending)]);
      final results = <PayoutAccountStatus?>[];
      await _tapToOpen(tester, (context) async {
        results.add(await showPayoutAccountSheet(context, status: _payoneer(_pending), accounts: accounts));
      });

      expect(find.text('Payoneer is reviewing your account'), findsOneWidget);
      expect(find.textContaining('Payoneer sandbox'), findsNothing); // only while setting up
      await tester.tap(find.text('Check again'));
      await tester.pumpAndSettle();
      expect(accounts.fetchCalls, 1);
      expect(find.textContaining("Payoneer hasn't approved your account yet"), findsOneWidget);
      expect(results, isEmpty);

      await tester.tap(find.text('View Payoneer account'));
      await tester.pumpAndSettle();
      expect(accounts.opened, ['https://myaccount.sandbox.payoneer.com/']);
    });
  });

  group('Withdraw to Payoneer', () {
    testWidgets('amount with the USD estimate, then "On its way to Payoneer"', (tester) async {
      _usePayoneerConfig();
      final accounts = _FakePayoutAccounts([_payoneer(_active)]);
      final results = <WithdrawalResult?>[];
      await _tapToOpen(tester, (context) async {
        results.add(await showWithdrawSheet(context, balance: 5000, accounts: accounts));
      });

      expect(find.text('Withdraw to Payoneer'), findsOneWidget);
      expect(find.textContaining('from Payoneer you can withdraw it to your bank in Pakistan'), findsOneWidget);
      expect(find.text(r'≈ $17.86 at Rs 280/USD'), findsOneWidget);
      expect(find.text('View Payoneer account'), findsOneWidget);

      await tester.tap(find.text('Withdraw'));
      await tester.pumpAndSettle();
      expect(accounts.withdrawn, [5000]);
      expect(find.text('On its way to Payoneer'), findsOneWidget);
      expect(find.textContaining(r'received as $17.86'), findsOneWidget);
      expect(find.textContaining('"View Payoneer account"'), findsOneWidget);

      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      expect(results.single?.withdrawal.toPayoneer, isTrue);
    });

    testWidgets('already transferred: "Sent to your Payoneer balance"', (tester) async {
      _usePayoneerConfig();
      final accounts = _FakePayoutAccounts([_payoneer(_active)], withdrawStatus: 'paid');
      await _tapToOpen(tester, (context) => showWithdrawSheet(context, balance: 5000, accounts: accounts));

      await tester.tap(find.text('Withdraw'));
      await tester.pumpAndSettle();
      expect(find.text('Sent to your Payoneer balance'), findsOneWidget);
    });

    testWidgets('PAYOUT_ACCOUNT_PENDING: shows the backend message, then where the account stands', (tester) async {
      _usePayoneerConfig();
      const message = "Payoneer is still checking your account. You can withdraw as soon as it's approved.";
      final options = RequestOptions(path: '/api/withdrawals');
      final accounts = _FakePayoutAccounts(
        [_payoneer(_active), _payoneer(_pending)],
        withdrawError: DioException(
          requestOptions: options,
          type: DioExceptionType.badResponse,
          response: Response(
            requestOptions: options,
            statusCode: 409,
            data: {'success': false, 'message': message, 'code': 'PAYOUT_ACCOUNT_PENDING'},
          ),
        ),
      );
      final results = <WithdrawalResult?>[];
      await _tapToOpen(tester, (context) async {
        results.add(await showWithdrawSheet(context, balance: 5000, accounts: accounts));
      });

      await tester.tap(find.text('Withdraw'));
      await tester.pumpAndSettle();
      expect(find.text("Couldn't withdraw"), findsOneWidget);
      expect(find.text(message), findsOneWidget);

      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(find.text('Payoneer is reviewing your account'), findsOneWidget);
    });
  });
}
