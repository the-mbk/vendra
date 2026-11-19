// Ledger tab in plain language: stock rows (a hold never counts as stock
// leaving), money rows with the commission breakdown, day grouping, totals.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vendra_vendor/core/models/ledger_entry_model.dart';
import 'package:vendra_vendor/features/vendor/models/ledger_lines.dart';
import 'package:vendra_vendor/features/vendor/widgets/wallet_widgets.dart';
import 'package:vendra_vendor/vendra_core.dart';

LedgerEntryModel _stock(String type, int change, {int? ref, String? notes, String? at}) => LedgerEntryModel.fromJson({
      'id': 1,
      'product_id': 7,
      'product_name': 'Bridal Dupatta',
      'vendor_id': 1,
      'change_type': type,
      'quantity_change': change,
      'private_stock_after': 11,
      'public_stock_after': 9,
      'reference_id': ref,
      'notes': notes,
      'created_at': at,
    });

WalletTransaction _money(String type, double amount, {int? order, String? desc, DateTime? at}) => WalletTransaction(
      id: 1,
      orderId: order,
      type: type,
      amount: amount,
      balanceAfter: 40000,
      description: desc,
      createdAt: at,
    );

void main() {
  final now = DateTime(2026, 11, 18, 22, 30);

  group('stock rows', () {
    test('a hold sets units aside without taking them off the shelf', () {
      final held = describeStockEntry(_stock('reserve', -2, ref: 10));
      expect(held.title, 'Held for online order #10');
      expect(held.amountText, '2 held');
      expect(held.movesShelf, isFalse);
      expect(held.detail, contains('Still on your shelf'));

      final sold = describeStockEntry(_stock('sale', -2, ref: 10, notes: 'Delivered by rider'));
      expect(sold.title, 'Sold online');
      expect(sold.amountText, '−2');
      expect(sold.movesShelf, isTrue);
      expect(sold.detail, 'Order #10, handed over for delivery');
    });

    test('releases, counter sales, stock in and corrections read plainly', () {
      final freed = describeStockEntry(
          _stock('release', 4, ref: 9, notes: "Order cancelled automatically: Store didn't respond in time"));
      expect(freed.title, 'Back on sale');
      expect(freed.detail, "Order #9 cancelled: Store didn't respond in time");
      expect(freed.amountText, '4 freed');

      expect(describeStockEntry(_stock('pos_sale', -1, ref: 6)).title, 'Sold at the counter');
      expect(describeStockEntry(_stock('pos_sale', -1, ref: 6)).detail, 'Walk-in sale #6');

      final added = describeStockEntry(_stock('stock_in', 5, notes: 'Stock received'));
      expect(added.title, 'Stock added');
      expect(added.amountText, '+5');
      expect(added.detail, '5 units put on the shelf');
      expect(describeStockEntry(_stock('stock_in', 5, notes: 'Supplier invoice 44')).detail, 'Supplier invoice 44');

      final fixed = describeStockEntry(_stock('adjustment', -3));
      expect(fixed.title, 'Stock corrected');
      expect(fixed.amountText, '−3');
    });

    test('filters pick the right rows', () {
      final hold = describeStockEntry(_stock('reserve', -1));
      expect(hold.matches(StockFilter.onlineHolds), isTrue);
      expect(hold.matches(StockFilter.sold), isFalse);
      expect(describeStockEntry(_stock('pos_sale', -1)).matches(StockFilter.sold), isTrue);
      expect(describeStockEntry(_stock('adjustment', -1)).matches(StockFilter.added), isTrue);
    });

    test("today's strip counts sales and stock in, not holds", () {
      final today = now.toIso8601String();
      final s = summarizeStockToday([
        _stock('reserve', -2, at: today),
        _stock('sale', -2, at: today),
        _stock('pos_sale', -1, at: today),
        _stock('stock_in', 10, at: today),
        _stock('sale', -5, at: DateTime(2026, 11, 17, 12).toIso8601String()),
      ], now: now);
      expect(s.soldOnline, 2);
      expect(s.soldCounter, 1);
      expect(s.added, 10);
      expect(s.sold, 3);
    });
  });

  group('money rows', () {
    const breakdown = 'Escrow released for Order #10: items Rs. 25,000 − 10% commission Rs. 2,500 = Rs. 22,500';

    test('an order payout shows the commission breakdown', () {
      final b = parseReleaseBreakdown(breakdown)!;
      expect(b.items, 'Rs. 25,000');
      expect(b.percent, '10');
      expect(b.commission, 'Rs. 2,500');
      expect(b.net, 'Rs. 22,500');
      expect(b.commissionAmount, 2500);

      final line = describeVendorMoney(_money('escrow_release', 22500, order: 10, desc: breakdown));
      expect(line.title, 'Order #10 paid out');
      expect(line.isIn, isTrue);
      expect(line.detail, 'Items Rs. 25,000, minus 10% Vendra commission (Rs. 2,500)');
    });

    test('older payouts, cancellation fees and withdrawals still read plainly', () {
      final old = describeVendorMoney(
          _money('escrow_release', 4050, order: 8, desc: 'Escrow released for Order #8 (after 10% commission)'));
      expect(old.detail, 'Customer payment after the 10% Vendra commission');
      expect(old.breakdown, isNull);

      final fee = describeVendorMoney(_money('escrow_release', 250, order: 4,
          desc: 'Late cancellation fee for Order #4: 10% of items Rs. 2,500'));
      expect(fee.title, 'Cancellation fee · Order #4');

      final payoneer =
          describeVendorMoney(_money('withdrawal', 1000, desc: 'Withdrawal #3 to your Payoneer account'));
      expect(payoneer.title, 'Sent to Payoneer');
      expect(payoneer.isIn, isFalse);
      expect(payoneer.matches(MoneyFilter.moneyOut), isTrue);
      expect(payoneer.matches(MoneyFilter.moneyIn), isFalse);

      expect(describeVendorMoney(_money('withdrawal_reversal', 1000, desc: 'Withdrawal #3 returned')).title,
          'Withdrawal returned');
    });

    test('30-day totals add payouts and commission, net of returned withdrawals', () {
      final t = summarizeMoney([
        _money('escrow_release', 22500, order: 10, desc: breakdown, at: now),
        _money('escrow_release', 4050, order: 8, desc: 'after 10% commission', at: now),
        _money('withdrawal', 1000, at: now),
        _money('withdrawal_reversal', 1000, at: now),
        _money('escrow_release', 999, at: now.subtract(const Duration(days: 40))),
      ], now: now);
      expect(t.received, 26550);
      expect(t.payouts, 2);
      expect(t.commission, 2500);
      expect(t.withdrawn, 0);
    });

    testWidgets('tapping a payout opens the breakdown', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: WalletTransactionTile(tx: _money('escrow_release', 22500, order: 10, desc: breakdown, at: now)),
        ),
      ));
      expect(find.text('You received'), findsNothing);
      await tester.tap(find.text('Order #10 paid out'));
      await tester.pump();
      expect(find.text('Vendra commission (10%)'), findsOneWidget);
      expect(find.text('− Rs. 2,500'), findsOneWidget);
      expect(find.text('You received'), findsOneWidget);
    });
  });

  group('dates', () {
    test('day headings', () {
      expect(ledgerDayLabel(DateTime(2026, 11, 18, 9), now: now), 'Today');
      expect(ledgerDayLabel(DateTime(2026, 11, 17, 23), now: now), 'Yesterday');
      expect(ledgerDayLabel(DateTime(2026, 11, 16, 10), now: now), 'Mon, 16 Nov');
      expect(ledgerDayLabel(DateTime(2025, 12, 1), now: now), '1 Dec 2025');

      final groups = groupByLedgerDay<DateTime?>(
          [DateTime(2026, 11, 18, 9), DateTime(2026, 11, 18, 8), DateTime(2026, 11, 17, 9), null], (d) => d, now: now);
      expect(groups.map((g) => g.$1).toList(), ['Today', 'Yesterday', 'Earlier']);
      expect(groups.first.$2.length, 2);
    });

    test('when held money is paid out', () {
      expect(releaseTimeLabel(now.subtract(const Duration(minutes: 1)), now: now), 'Being paid out now');
      expect(releaseTimeLabel(now.add(const Duration(minutes: 25)), now: now), 'in 25 min');
      expect(releaseTimeLabel(DateTime(2026, 11, 18, 23, 50), now: now), 'today at 11:50 PM');
      expect(releaseTimeLabel(DateTime(2026, 11, 19, 9, 5), now: now), 'tomorrow at 9:05 AM');
      expect(releaseTimeLabel(DateTime(2026, 11, 25, 9, 5), now: now), '25 Nov at 9:05 AM');
    });
  });

  test('every stock row has an icon', () {
    for (final type in ['stock_in', 'adjustment', 'reserve', 'release', 'sale', 'pos_sale', 'future_kind']) {
      expect(describeStockEntry(_stock(type, -1)).icon, isA<IconData>(), reason: type);
    }
  });
}
