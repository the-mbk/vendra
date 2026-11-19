// ══════════════════════════════════════════════════════════════
// Vendra Vendor App - Ledger rows in plain language
// Turns raw ledger rows into what a shop owner would say:
//
// Stock (GET /api/vendor/inventory/ledger)
//   stock_in    "Stock added"            +N on the shelf
//   adjustment  "Stock corrected"        -N on the shelf
//   reserve     "Held for online order"  N held: still on the shelf, kept aside for the rider
//   release     "Back on sale"           N freed: the online order was cancelled
//   sale        "Sold online"            -N on the shelf (handed to the rider / customer)
//   pos_sale    "Sold at the counter"    -N on the shelf
// A reservation does not move the shelf count; only the sale does, so
// "held" and "sold" are never both shown as stock leaving.
//
// Money (GET /api/wallet)
//   escrow_release  "Order #12 paid out" with the commission breakdown
//                   the backend writes ("items Rs. X − 10% commission Rs. Y = Rs. Z"),
//                   or "Cancellation fee" when the customer cancelled late
//   withdrawal      "Sent to Payoneer" / "Sent to your card"
//   withdrawal_reversal  "Withdrawal returned"
// ══════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:vendra_vendor/vendra_core.dart';

import '../../../core/models/ledger_entry_model.dart';

// ── Dates ───────────────────────────────────────────────────────

DateTime _day(DateTime t) => DateTime(t.year, t.month, t.day);

/// Section heading for a ledger day: "Today", "Yesterday", "Mon, 16 Nov", "16 Nov 2025"
String ledgerDayLabel(DateTime at, {DateTime? now}) {
  final t = at.toLocal();
  final n = (now ?? DateTime.now()).toLocal();
  final days = _day(n).difference(_day(t)).inDays;
  if (days <= 0) return 'Today';
  if (days == 1) return 'Yesterday';
  if (t.year == n.year) return DateFormat('EEE, d MMM').format(t);
  return DateFormat('d MMM yyyy').format(t);
}

/// Consecutive runs of [items] (newest first) under their day headings; undated rows go last
List<(String, List<T>)> groupByLedgerDay<T>(List<T> items, DateTime? Function(T) dateOf, {DateTime? now}) {
  final groups = <(String, List<T>)>[];
  for (final item in items) {
    final at = dateOf(item);
    final label = at == null ? 'Earlier' : ledgerDayLabel(at, now: now);
    if (groups.isEmpty || groups.last.$1 != label) {
      groups.add((label, [item]));
    } else {
      groups.last.$2.add(item);
    }
  }
  return groups;
}

/// When held escrow is paid out: "Being paid out now", "in 25 min", "today at 3:40 PM", "18 Nov at 3:40 PM"
String releaseTimeLabel(DateTime due, {DateTime? now}) {
  final t = due.toLocal();
  final n = (now ?? DateTime.now()).toLocal();
  final left = t.difference(n);
  if (left.inSeconds <= 0) return 'Being paid out now';
  if (left.inMinutes < 60) return 'in ${left.inMinutes < 1 ? 1 : left.inMinutes} min';
  final clock = DateFormat('h:mm a').format(t);
  final days = _day(t).difference(_day(n)).inDays;
  if (days == 0) return 'today at $clock';
  if (days == 1) return 'tomorrow at $clock';
  return '${DateFormat('d MMM').format(t)} at $clock';
}

// ── Stock ───────────────────────────────────────────────────────

/// What a stock row did, for filtering
enum StockMoveKind { added, corrected, held, freed, soldOnline, soldCounter, other }

/// Filter chips on the stock ledger
enum StockFilter { all, sold, added, onlineHolds }

extension StockFilterLabel on StockFilter {
  String get label => switch (this) {
        StockFilter.all => 'All',
        StockFilter.sold => 'Sold',
        StockFilter.added => 'Added / corrected',
        StockFilter.onlineHolds => 'Online holds',
      };
}

class StockMove {
  final StockMoveKind kind;

  /// "Sold online", "Held for online order"...
  final String title;

  /// "Order #10 · handed to the rider"
  final String detail;
  final IconData icon;
  final Color color;

  /// "+5", "−2", "2 held", "4 freed"
  final String amountText;

  /// True when the shelf count changed (a hold / release only sets units aside)
  final bool movesShelf;

  const StockMove({
    required this.kind,
    required this.title,
    required this.detail,
    required this.icon,
    required this.color,
    required this.amountText,
    required this.movesShelf,
  });

  bool matches(StockFilter f) => switch (f) {
        StockFilter.all => true,
        StockFilter.sold => kind == StockMoveKind.soldOnline || kind == StockMoveKind.soldCounter,
        StockFilter.added => kind == StockMoveKind.added || kind == StockMoveKind.corrected,
        StockFilter.onlineHolds => kind == StockMoveKind.held || kind == StockMoveKind.freed,
      };
}

String _units(int n) => n == 1 ? '1 unit' : '$n units';

/// "Order cancelled automatically: Store didn't respond in time" → "Store didn't respond in time"
String _cancelReason(String? notes) {
  final text = (notes ?? '').trim();
  final colon = text.indexOf(':');
  final reason = colon >= 0 ? text.substring(colon + 1).trim() : '';
  if (reason.isEmpty) return '';
  return reason[0].toUpperCase() + reason.substring(1);
}

/// The plain-language reading of one inventory ledger row
StockMove describeStockEntry(LedgerEntryModel e) {
  final qty = e.quantityChange.abs();
  final ref = e.referenceId;
  final notes = e.notes?.trim();
  switch (e.changeType) {
    case 'stock_in':
      final custom = notes != null && notes.isNotEmpty && notes != 'Manual stock update' && notes != 'Stock received';
      return StockMove(
        kind: StockMoveKind.added,
        title: 'Stock added',
        detail: custom ? notes : '${_units(qty)} put on the shelf',
        icon: Icons.add_box_outlined,
        color: AppColors.success,
        amountText: '+$qty',
        movesShelf: true,
      );
    case 'adjustment':
      final up = e.quantityChange > 0;
      return StockMove(
        kind: StockMoveKind.corrected,
        title: 'Stock corrected',
        detail: up ? 'Count raised by hand' : 'Count lowered by hand (damaged, lost or recounted)',
        icon: Icons.tune,
        color: up ? AppColors.success : AppColors.error,
        amountText: '${up ? '+' : '−'}$qty',
        movesShelf: true,
      );
    case 'reserve':
      return StockMove(
        kind: StockMoveKind.held,
        title: ref != null ? 'Held for online order #$ref' : 'Held for an online order',
        detail: 'Still on your shelf. Keep ${qty == 1 ? 'it' : 'them'} aside for the rider.',
        icon: Icons.lock_outline,
        color: AppColors.warningInk,
        amountText: '$qty held',
        movesShelf: false,
      );
    case 'release':
      final reason = _cancelReason(notes);
      return StockMove(
        kind: StockMoveKind.freed,
        title: 'Back on sale',
        detail: [
          if (ref != null) 'Order #$ref cancelled' else 'Online order cancelled',
          if (reason.isNotEmpty) reason,
        ].join(': '),
        icon: Icons.lock_open,
        color: AppColors.info,
        amountText: '$qty freed',
        movesShelf: false,
      );
    case 'sale':
      return StockMove(
        kind: StockMoveKind.soldOnline,
        title: 'Sold online',
        detail: ref != null ? 'Order #$ref, handed over for delivery' : 'Online order handed over',
        icon: Icons.local_shipping_outlined,
        color: AppColors.secondary,
        amountText: '−$qty',
        movesShelf: true,
      );
    case 'pos_sale':
      return StockMove(
        kind: StockMoveKind.soldCounter,
        title: 'Sold at the counter',
        detail: ref != null ? 'Walk-in sale #$ref' : 'Walk-in sale',
        icon: Icons.point_of_sale,
        color: AppColors.primary,
        amountText: '−$qty',
        movesShelf: true,
      );
    default:
      final up = e.quantityChange >= 0;
      return StockMove(
        kind: StockMoveKind.other,
        title: e.changeTypeDisplay,
        detail: notes ?? '',
        icon: Icons.swap_vert,
        color: AppColors.textSecondary,
        amountText: '${up ? '+' : '−'}$qty',
        movesShelf: true,
      );
  }
}

/// Today's counts for the stock summary strip
class StockDaySummary {
  final int soldOnline;
  final int soldCounter;
  final int added;
  const StockDaySummary({this.soldOnline = 0, this.soldCounter = 0, this.added = 0});
  int get sold => soldOnline + soldCounter;
}

StockDaySummary summarizeStockToday(List<LedgerEntryModel> entries, {DateTime? now}) {
  final n = (now ?? DateTime.now()).toLocal();
  var online = 0, counter = 0, added = 0;
  for (final e in entries) {
    final at = e.createdAt != null ? DateTime.tryParse(e.createdAt!)?.toLocal() : null;
    if (at == null || _day(at) != _day(n)) continue;
    final qty = e.quantityChange.abs();
    switch (e.changeType) {
      case 'sale':
        online += qty;
      case 'pos_sale':
        counter += qty;
      case 'stock_in':
        added += qty;
    }
  }
  return StockDaySummary(soldOnline: online, soldCounter: counter, added: added);
}

// ── Money ───────────────────────────────────────────────────────

/// Filter chips on the money ledger
enum MoneyFilter { all, moneyIn, moneyOut }

extension MoneyFilterLabel on MoneyFilter {
  String get label => switch (this) {
        MoneyFilter.all => 'All',
        MoneyFilter.moneyIn => 'Money in',
        MoneyFilter.moneyOut => 'Money out',
      };
}

/// "items Rs. 25,000 − 10% commission Rs. 2,500 = Rs. 22,500", taken apart
class ReleaseBreakdown {
  final String items;
  final String percent;
  final String commission;
  final String net;
  final double commissionAmount;
  const ReleaseBreakdown({
    required this.items,
    required this.percent,
    required this.commission,
    required this.net,
    required this.commissionAmount,
  });
}

final _breakdownPattern = RegExp(r'items (Rs\. [\d,.]+) [−-] ([\d.]+)% commission (Rs\. [\d,.]+) = (Rs\. [\d,.]+)');

/// "Rs. 2,500.50" → 2500.5 (the "Rs." dot is not a decimal point)
double _rupees(String text) =>
    double.tryParse(text.replaceFirst(RegExp(r'^\s*Rs\.?\s*'), '').replaceAll(RegExp(r'[^\d.]'), '')) ?? 0;

ReleaseBreakdown? parseReleaseBreakdown(String? description) {
  final m = _breakdownPattern.firstMatch(description ?? '');
  if (m == null) return null;
  return ReleaseBreakdown(
    items: m.group(1)!,
    percent: m.group(2)!,
    commission: m.group(3)!,
    net: m.group(4)!,
    commissionAmount: _rupees(m.group(3)!),
  );
}

class MoneyLine {
  final String title;
  final String detail;
  final bool isIn;
  final IconData icon;
  final Color color;

  /// Only on an order payout written with the itemised breakdown
  final ReleaseBreakdown? breakdown;
  const MoneyLine({
    required this.title,
    required this.detail,
    required this.isIn,
    required this.icon,
    required this.color,
    this.breakdown,
  });

  bool matches(MoneyFilter f) => switch (f) {
        MoneyFilter.all => true,
        MoneyFilter.moneyIn => isIn,
        MoneyFilter.moneyOut => !isIn,
      };
}

/// The plain-language reading of one wallet row, as the store sees it
MoneyLine describeVendorMoney(WalletTransaction t) {
  final desc = t.description?.trim() ?? '';
  final order = t.orderId != null ? 'Order #${t.orderId}' : 'An order';
  switch (t.type) {
    case 'escrow_release':
      if (desc.startsWith('Late cancellation fee')) {
        return MoneyLine(
          title: 'Cancellation fee · $order',
          detail: 'The customer cancelled after you accepted, so you keep part of the order.',
          isIn: true,
          icon: Icons.event_busy_outlined,
          color: AppColors.success,
        );
      }
      final b = parseReleaseBreakdown(desc);
      final pct = b?.percent ?? RegExp(r'([\d.]+)% commission').firstMatch(desc)?.group(1);
      return MoneyLine(
        title: '$order paid out',
        detail: b != null
            ? 'Items ${b.items}, minus ${b.percent}% Vendra commission (${b.commission})'
            : pct != null
                ? 'Customer payment after the $pct% Vendra commission'
                : 'Customer payment released after the dispute window',
        isIn: true,
        icon: Icons.storefront_outlined,
        color: AppColors.success,
        breakdown: b,
      );
    case 'withdrawal':
      final lower = desc.toLowerCase();
      final where = lower.contains('payoneer')
          ? 'Payoneer'
          : lower.contains('stripe')
              ? 'your payout account'
              : lower.contains('card') || lower.contains('••••') || lower.contains('visa') || lower.contains('mastercard')
                  ? 'your card'
                  : 'your account';
      return MoneyLine(
        title: 'Sent to $where',
        detail: desc.isNotEmpty ? desc : 'Withdrawal from your Vendra balance',
        isIn: false,
        icon: Icons.north_east,
        color: AppColors.error,
      );
    case 'withdrawal_reversal':
      return MoneyLine(
        title: 'Withdrawal returned',
        detail: desc.isNotEmpty ? desc : "The payout didn't go through, so the money is back in your balance.",
        isIn: true,
        icon: Icons.undo,
        color: AppColors.success,
      );
    case 'opening_balance':
      return MoneyLine(
        title: 'Opening balance',
        detail: desc.isNotEmpty ? desc : 'Balance carried in when the account was set up',
        isIn: true,
        icon: Icons.account_balance_wallet_outlined,
        color: AppColors.success,
      );
    default:
      return MoneyLine(
        title: t.title,
        detail: desc,
        isIn: !t.isDebit,
        icon: t.icon,
        color: t.isDebit ? AppColors.error : AppColors.success,
      );
  }
}

/// Last-30-days totals for the money header (from the rows loaded)
class MoneyTotals {
  final double received;
  final double commission;
  final double withdrawn;
  final int payouts;
  const MoneyTotals({this.received = 0, this.commission = 0, this.withdrawn = 0, this.payouts = 0});
}

MoneyTotals summarizeMoney(List<WalletTransaction> txs, {DateTime? now, int days = 30}) {
  final since = (now ?? DateTime.now()).subtract(Duration(days: days));
  var received = 0.0, commission = 0.0, withdrawn = 0.0;
  var payouts = 0;
  for (final t in txs) {
    final at = t.createdAt;
    if (at == null || at.isBefore(since)) continue;
    switch (t.type) {
      case 'escrow_release':
        received += t.amount;
        payouts++;
        commission += parseReleaseBreakdown(t.description)?.commissionAmount ?? 0;
      case 'withdrawal':
        withdrawn += t.amount;
      case 'withdrawal_reversal':
        withdrawn -= t.amount;
    }
  }
  return MoneyTotals(received: received, commission: commission, withdrawn: withdrawn < 0 ? 0 : withdrawn, payouts: payouts);
}
