// ══════════════════════════════════════════════════════════════
// Vendra Rider App - Payout slip (FR04)
// The itemised payout the server stores on an order at delivery
// (`payoutBreakdown`) and estimates on a task card
// (`estimatedPayoutBreakdown`): base fee + distance + paid waiting.
// Lines are rounded for display; `total` is the exact amount paid.
// ══════════════════════════════════════════════════════════════

import 'package:intl/intl.dart';
import 'package:vendra_rider/vendra_core.dart';

/// One line of the slip, e.g. "Distance" · "5.12 km × Rs. 25/km" · 128
class PayoutSlipLine {
  final String label;
  final String? detail;
  final double amount;

  const PayoutSlipLine(this.label, this.amount, {this.detail});
}

class PayoutBreakdown {
  final double baseFee;
  final double perKm;
  final double distanceKm;
  final double distancePay;
  final double perWaitMin;
  final double freeWaitMin;
  final double waitMinutes;
  final double paidWaitMinutes;
  final double waitPay;
  final double total;

  /// gps | straight_line — null on an estimate (always straight line, no waiting)
  final String? distanceSource;

  const PayoutBreakdown({
    required this.baseFee,
    required this.perKm,
    required this.distanceKm,
    required this.distancePay,
    required this.perWaitMin,
    required this.freeWaitMin,
    required this.waitMinutes,
    required this.paidWaitMinutes,
    required this.waitPay,
    required this.total,
    this.distanceSource,
  });

  factory PayoutBreakdown.fromJson(Map<String, dynamic> json) => PayoutBreakdown(
        baseFee: toDouble(json['baseFee']),
        perKm: toDouble(json['perKm']),
        distanceKm: toDouble(json['distanceKm']),
        distancePay: toDouble(json['distancePay']),
        perWaitMin: toDouble(json['perWaitMin']),
        freeWaitMin: toDouble(json['freeWaitMin']),
        waitMinutes: toDouble(json['waitMinutes']),
        paidWaitMinutes: toDouble(json['paidWaitMinutes']),
        waitPay: toDouble(json['waitPay']),
        total: toDouble(json['total']),
        distanceSource: json['distanceSource'],
      );

  /// Orders delivered before slips existed send null (show the total only)
  static PayoutBreakdown? tryParse(dynamic json) =>
      json is Map ? PayoutBreakdown.fromJson(Map<String, dynamic>.from(json)) : null;

  bool get isStraightLine => distanceSource == 'straight_line';

  /// Base fee, distance and waiting — plus a rounding line when the rounded
  /// lines don't add up to the exact total, so the slip always sums.
  List<PayoutSlipLine> get lines {
    final result = [
      PayoutSlipLine('Base fee', baseFee),
      PayoutSlipLine('Distance', distancePay, detail: '${slipKm(distanceKm)} × ${slipRate(perKm)}/km'),
      PayoutSlipLine(
        'Waiting',
        waitPay,
        detail: '${slipMinutes(waitMinutes)} min (${slipMinutes(freeWaitMin)} free) × ${slipRate(perWaitMin)}/min',
      ),
    ];
    final rounding = roundingDifference;
    if (rounding != 0) result.add(PayoutSlipLine('Rounding', rounding));
    return result;
  }

  /// total − (base + distance + waiting), to the paisa
  double get roundingDifference {
    final paisa = (total * 100).round() - ((baseFee + distancePay + waitPay) * 100).round();
    return paisa / 100;
  }
}

final _rate = NumberFormat('#,##0.##', 'en_US');

/// "5.12 km" (the slip always shows two decimals)
String slipKm(double v) => '${v.toStringAsFixed(2)} km';

/// "7" or "7.5" (minutes)
String slipMinutes(double v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);

/// "Rs. 25" or "Rs. 2.5" (a per-unit rate)
String slipRate(double v) => 'Rs. ${_rate.format(v)}';
