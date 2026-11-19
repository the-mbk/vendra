// ══════════════════════════════════════════════════════════════
// Vendra Vendor App - The rider for a delivery order
// Before the rider checks in: who is coming (tap to call). Once they check
// in at the store (geofenced "Arrived"): a live "waiting 03:12" clock and
// how long they have left to collect. Past the limit the delivery goes
// back to other riders automatically, so a rider can't sit at the counter
// holding the order (and earning waiting pay). The store stops the clock
// with "Handed over" (vendor_orders_screen).
// ══════════════════════════════════════════════════════════════

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:vendra_vendor/vendra_core.dart';

/// Where the rider is, from the store's side
enum RiderAtStore { onTheWay, waiting, overLimit }

RiderAtStore riderAtStoreState(OrderModel order, int limitMinutes, DateTime now) {
  final arrived = order.riderArrivedAt;
  if (arrived == null) return RiderAtStore.onTheWay;
  if (limitMinutes > 0 && now.difference(arrived) >= Duration(minutes: limitMinutes)) return RiderAtStore.overLimit;
  return RiderAtStore.waiting;
}

String _mmss(Duration d) {
  final m = d.inMinutes;
  final s = d.inSeconds % 60;
  return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
}

class RiderAtStoreCard extends StatefulWidget {
  final OrderModel order;
  const RiderAtStoreCard({super.key, required this.order});

  @override
  State<RiderAtStoreCard> createState() => _RiderAtStoreCardState();
}

class _RiderAtStoreCardState extends State<RiderAtStoreCard> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _syncTicker();
  }

  @override
  void didUpdateWidget(RiderAtStoreCard old) {
    super.didUpdateWidget(old);
    _syncTicker();
  }

  /// Ticks only while the rider is waiting at the counter
  void _syncTicker() {
    final waiting = widget.order.status == 'ready_for_pickup' && widget.order.riderArrivedAt != null;
    if (waiting && _ticker == null) {
      _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });
    } else if (!waiting) {
      _ticker?.cancel();
      _ticker = null;
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final order = widget.order;
    final rider = order.rider!;
    final name = rider.name ?? 'Your rider';
    final limit = AppConfig.current.riderStoreWaitMaxMinutes;
    final now = DateTime.now();
    final atStore = order.status == 'ready_for_pickup';
    final state = atStore ? riderAtStoreState(order, limit, now) : null;

    final (Color accent, String headline, String? detail) = switch (state) {
      RiderAtStore.waiting => () {
          final waited = now.difference(order.riderArrivedAt!);
          final left = limit > 0 ? Duration(minutes: limit) - waited : null;
          return (
            AppColors.primary,
            '$name is at your counter · waiting ${_mmss(waited.isNegative ? Duration.zero : waited)}',
            left == null
                ? 'Hand the parcel over, then tap Handed over.'
                : 'Hand the parcel over, then tap Handed over. If it isn\'t collected in ${_mmss(left)}, '
                    'the delivery goes to another rider.',
          );
        }(),
      RiderAtStore.overLimit => (
          AppColors.error,
          '$name has waited over $limit min',
          'The delivery is being offered to another rider. Keep the parcel ready.',
        ),
      RiderAtStore.onTheWay => (
          AppColors.secondary,
          '$name is coming to collect',
          'You will see a timer here when they check in at your store.',
        ),
      null => (AppColors.secondary, 'Rider: $name', null),
    };

    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.fromLTRB(10, 8, 4, 8),
      decoration: BoxDecoration(
        color: AppColors.tint(accent),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: accent.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: UserAvatar(name: name, photoUrl: rider.photoUrl, size: 34, badge: AppIcons.rider),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  headline,
                  style: GoogleFonts.poppins(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.ink(accent),
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                if (detail != null)
                  Text(detail, style: GoogleFonts.poppins(fontSize: 12, color: AppColors.textSecondary)),
              ],
            ),
          ),
          PhoneAction(phone: rider.phone, label: 'Call'),
        ],
      ),
    );
  }
}
