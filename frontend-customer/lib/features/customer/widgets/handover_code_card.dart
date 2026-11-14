// ══════════════════════════════════════════════════════════════
// Vendra Customer App - Delivery handover code
// Open orders carry a 4-digit deliveryOtp. The rider (or, for self pickup,
// the store) must type it in to complete the handover, so a delivery can't
// be marked done from a spoofed GPS position. Five wrong codes lock the
// handover for a while (otpLockedUntil) and the customer is warned here.
// ══════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:vendra_customer/vendra_core.dart';

/// Whether the order has a code to show (open orders only)
bool showsHandoverCode(OrderModel o) =>
    (o.deliveryOtp ?? '').isNotEmpty && o.status != 'delivered' && o.status != 'cancelled';

/// What the customer should do with the code
String handoverInstruction(OrderModel o) => o.isDelivery
    ? 'Give this code to the rider only when you have your items'
    : 'Show this code at the counter when you collect your order';

/// Whether wrong codes have locked the handover right now
bool handoverLocked(OrderModel o, [DateTime? now]) =>
    o.otpLockedUntil != null && o.otpLockedUntil!.isAfter(now ?? DateTime.now());

class HandoverCodeCard extends StatelessWidget {
  final OrderModel order;

  /// Slim version for order cards
  final bool compact;

  const HandoverCodeCard({super.key, required this.order, this.compact = false});

  static final _time = DateFormat('h:mm a');

  @override
  Widget build(BuildContext context) {
    if (!showsHandoverCode(order)) return const SizedBox.shrink();
    final code = order.deliveryOtp!;
    final locked = handoverLocked(order);
    return compact ? _compact(code, locked) : _full(code, locked);
  }

  Widget _lockWarning({required bool small}) {
    return Container(
      width: double.infinity,
      margin: EdgeInsets.only(top: small ? 6 : 12),
      padding: EdgeInsets.all(small ? 8 : 10),
      decoration: BoxDecoration(
        color: AppColors.error.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.error.withValues(alpha: 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.lock_clock_outlined, size: small ? 16 : 18, color: AppColors.error),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Wrong codes were entered. Handover is locked until ${_time.format(order.otpLockedUntil!)}. '
              'Only share the code with the ${order.isDelivery ? 'rider' : 'store'} in person.',
              style: TextStyle(fontSize: small ? 11 : 12, height: 1.35, color: AppColors.error),
            ),
          ),
        ],
      ),
    );
  }

  Widget _compact(String code, bool locked) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.secondary.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.secondary.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.key_rounded, size: 16, color: AppColors.secondary),
              const SizedBox(width: 6),
              const Expanded(
                child: Text('Handover code',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
              ),
              Text(
                code.split('').join(' '),
                semanticsLabel: 'Handover code ${code.split('').join(' ')}',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 2,
                  color: AppColors.secondary,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
          Text(handoverInstruction(order), style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
          if (locked) _lockWarning(small: true),
        ],
      ),
    );
  }

  Widget _full(String code, bool locked) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.secondary.withValues(alpha: 0.25)),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.key_rounded, size: 20, color: AppColors.secondary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  order.isDelivery ? 'Delivery handover code' : 'Pickup code',
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Semantics(
            label: 'Handover code ${code.split('').join(' ')}',
            excludeSemantics: true,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (final digit in code.split(''))
                  Flexible(
                    child: Container(
                      constraints: const BoxConstraints(maxWidth: 56),
                      margin: const EdgeInsets.symmetric(horizontal: 5),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: AppColors.secondary.withValues(alpha: 0.06),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: AppColors.secondary.withValues(alpha: 0.3)),
                      ),
                      child: Text(
                        digit,
                        style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w700, color: AppColors.secondary),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Text(
            handoverInstruction(order),
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: AppColors.textPrimary),
          ),
          const SizedBox(height: 4),
          Text(
            order.isDelivery
                ? 'The delivery is completed only when the rider enters this code — never share it by phone or message.'
                : 'The store enters this code to hand your order over. Keep it to yourself until then.',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 11, height: 1.35, color: AppColors.textSecondary),
          ),
          if (locked) _lockWarning(small: false),
        ],
      ),
    );
  }
}
