// Vendor wallet: readable ledger rows with a copyable payout reference,
// which notifications reload the balance, and the development-only demo
// logins on the login screen.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vendra_vendor/features/auth/bloc/auth_bloc.dart';
import 'package:vendra_vendor/features/auth/screens/login_screen.dart';
import 'package:vendra_vendor/features/vendor/widgets/wallet_widgets.dart';
import 'package:vendra_vendor/vendra_core.dart';

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: SingleChildScrollView(child: child)));

void main() {
  tearDown(() => AppConfig.debugSet(AppConfig.fallback));

  test('escrow releases and payout results count as wallet notifications', () {
    for (final type in ['escrow_released', 'withdrawal_paid', 'withdrawal_failed', 'withdrawal_reversal']) {
      expect(isWalletNotification(type), isTrue, reason: type);
    }
    expect(isWalletNotification('new_order'), isFalse);
    expect(isWalletNotification('order_status'), isFalse);
  });

  testWidgets('an escrow release row shows a readable title and a credit', (tester) async {
    final tx = WalletTransaction.fromJson(const {
      'id': 1,
      'order_id': 12,
      'type': 'escrow_release',
      'amount': '4275.00',
      'balance_after': '9275.00',
      'description': 'Order #12 subtotal minus commission',
    });
    await tester.pumpWidget(_wrap(WalletTransactionTile(tx: tx)));

    expect(find.text('Payment received · Order #12'), findsOneWidget);
    expect(find.text('+ Rs. 4,275'), findsOneWidget);
    expect(find.textContaining('Ref.'), findsNothing);
  });

  testWidgets('a withdrawal row is a debit and its payout reference can be copied', (tester) async {
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') copied = (call.arguments as Map)['text'] as String?;
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));

    final tx = WalletTransaction.fromJson(const {
      'id': 2,
      'type': 'withdrawal',
      'amount': 1500,
      'balanceAfter': 7775,
      'description': 'Withdrawal to Visa •••• 5556',
      'reference': 'po_test123',
    });
    await tester.pumpWidget(_wrap(WalletTransactionTile(tx: tx)));

    expect(find.text('Withdrawal'), findsOneWidget);
    expect(find.text('− Rs. 1,500'), findsOneWidget);
    expect(find.text('Ref. po_test123'), findsOneWidget);

    await tester.tap(find.text('Ref. po_test123'));
    await tester.pump();
    expect(copied, 'po_test123');
    expect(find.text('Copied po_test123'), findsOneWidget);
  });

  testWidgets('demo vendor logins appear only in development', (tester) async {
    Future<void> pumpLogin() => tester.pumpWidget(BlocProvider<AuthBloc>(
          create: (_) => AuthBloc(),
          child: const MaterialApp(home: LoginScreen()),
        ));

    AppConfig.debugSet(AppConfig.fallback); // production defaults
    await pumpLogin();
    expect(find.text('Demo accounts'), findsNothing);
    expect(find.text('Usman Traders'), findsNothing);

    AppConfig.debugSet(AppConfig.fromJson(const {
      'mode': 'development',
      'features': {'demoLogin': true},
      'demoAccounts': [
        {'role': 'vendor', 'name': 'Usman Traders', 'email': 'usman@vendor.pk', 'password': 'password123'},
      ],
    }));
    await tester.pump();
    expect(find.text('Demo accounts'), findsOneWidget);
    expect(find.text('Usman Traders'), findsOneWidget);
  });
}
