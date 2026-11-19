// ══════════════════════════════════════════════════════════════
// Vendra Customer App - Stock reservation timer (FR02)
// A pending order's units are reserved until reservationExpiresAt. If the
// store hasn't accepted by then the reservation is released and the order
// is cancelled and refunded. This shows a live countdown and asks the
// caller to refresh the order once time is up (then every 15 s for a
// little while, in case the server's sweep runs a few seconds late).
// Hidden for any order that isn't pending.
// ══════════════════════════════════════════════════════════════

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:vendra_customer/vendra_core.dart';

/// When a pending order's reserved stock is released, or null when not
/// pending. The API sends reservationExpiresAt; the checkout response does
/// not, so fall back to createdAt + the store-accept timeout (public config).
DateTime? reservationDeadline(OrderModel order, {int? acceptTimeoutMinutes}) {
  if (order.status != 'pending') return null;
  if (order.reservationExpiresAt != null) return order.reservationExpiresAt;
  final timeout = acceptTimeoutMinutes ?? AppConfig.current.vendorAcceptTimeoutMinutes;
  final placed = order.createdAt == null ? null : DateTime.tryParse(order.createdAt!)?.toLocal();
  if (placed == null || timeout <= 0) return null;
  return placed.add(Duration(minutes: timeout));
}

/// "04:59", or "1:04:59" past an hour. Negative durations show "00:00".
String formatCountdown(Duration d) {
  final left = d.isNegative ? Duration.zero : d;
  String two(int n) => n.toString().padLeft(2, '0');
  final h = left.inHours;
  final m = left.inMinutes % 60;
  final s = left.inSeconds % 60;
  return h > 0 ? '$h:${two(m)}:${two(s)}' : '${two(m)}:${two(s)}';
}

class ReservationCountdown extends StatefulWidget {
  final OrderModel order;

  /// Called when the reservation runs out — refresh the order
  final VoidCallback? onExpired;

  /// Single line for order cards; otherwise a full banner
  final bool compact;

  /// Override the clock (tests)
  final DateTime Function()? clock;

  const ReservationCountdown({
    super.key,
    required this.order,
    this.onExpired,
    this.compact = false,
    this.clock,
  });

  @override
  State<ReservationCountdown> createState() => _ReservationCountdownState();
}

class _ReservationCountdownState extends State<ReservationCountdown> {
  /// After expiry, ask for a refresh every [_retryEvery] seconds, up to [_retryFor]
  static const _retryEvery = 15;
  static const _retryFor = 90;

  Timer? _ticker;
  DateTime? _deadline;
  int _secondsExpired = 0;

  DateTime _now() => (widget.clock ?? DateTime.now)();

  @override
  void initState() {
    super.initState();
    _deadline = reservationDeadline(widget.order);
    _start();
  }

  @override
  void didUpdateWidget(covariant ReservationCountdown oldWidget) {
    super.didUpdateWidget(oldWidget);
    final next = reservationDeadline(widget.order);
    if (next != _deadline) {
      _deadline = next;
      _secondsExpired = 0;
      _start();
    }
  }

  void _start() {
    _ticker?.cancel();
    _ticker = null;
    if (_deadline == null) return;
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  void _tick() {
    if (!mounted || _deadline == null) return;
    if (_deadline!.isAfter(_now())) {
      setState(() {});
      return;
    }
    if (_secondsExpired % _retryEvery == 0) widget.onExpired?.call();
    _secondsExpired++;
    if (_secondsExpired > _retryFor) {
      _ticker?.cancel();
      _ticker = null;
    }
    setState(() {});
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final deadline = _deadline;
    if (deadline == null) return const SizedBox.shrink();
    final left = deadline.difference(_now());
    final expired = left <= Duration.zero;
    const color = AppColors.reservedAmber;
    final ink = AppColors.warningInk;

    final message = expired
        ? const TextSpan(text: 'Reservation time is up — checking with the store…')
        : TextSpan(children: [
            const TextSpan(text: 'The store has '),
            TextSpan(
              text: formatCountdown(left),
              style: const TextStyle(fontWeight: FontWeight.w700, fontFeatures: [FontFeature.tabularFigures()]),
            ),
            const TextSpan(text: ' to accept and pack this order'),
          ]);

    if (widget.compact) {
      return Row(
        children: [
          Icon(expired ? Icons.hourglass_bottom_rounded : Icons.timer_outlined, size: 15, color: color),
          const SizedBox(width: 6),
          Expanded(
            child: Text.rich(message, style: TextStyle(fontSize: 12, color: ink)),
          ),
        ],
      );
    }

    final total = AppConfig.current.vendorAcceptTimeoutMinutes * 60;
    final fraction = total > 0 ? (left.inSeconds / total).clamp(0.0, 1.0) : null;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.warningSurface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(expired ? Icons.hourglass_bottom_rounded : Icons.timer_outlined, size: 22, color: color),
              const SizedBox(width: 10),
              Expanded(
                child: Text.rich(
                  message,
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: ink),
                ),
              ),
            ],
          ),
          if (fraction != null && !expired) ...[
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: fraction,
                minHeight: 5,
                color: color,
                backgroundColor: color.withValues(alpha: 0.2),
              ),
            ),
          ],
          const SizedBox(height: 8),
          Text(
            "Your units are reserved and can't be sold to walk-in customers. If the store doesn't "
            'accept in time, the reservation expires and your payment is automatically refunded '
            '100% to your Vendra Wallet.',
            style: TextStyle(fontSize: 11, height: 1.4, color: ink),
          ),
        ],
      ),
    );
  }
}
