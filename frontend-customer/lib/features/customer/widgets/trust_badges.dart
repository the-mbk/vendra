// ══════════════════════════════════════════════════════════════
// Vendra Customer App - Trust badges
// LiveStockIndicator  dual inventory reassurance (FR01): the stock count
//                     follows the store's shelf in real time, a buffer is
//                     kept for walk-ins and ordered units are reserved
// EscrowTrustBadge    "Funds held safely by Vendra Escrow" (FR03)
// Each one opens a short explainer bottom sheet.
// ══════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:vendra_customer/vendra_core.dart';

const _liveGreen = AppColors.stockGreen;
Color get _escrowGreen => AppColors.successInk;

/// "Only 3 left" / "24 in stock" / "Sold out" — the low-stock signal (FR01)
String stockLabel(ProductModel p) {
  if (p.isOutOfStock) return 'Sold out';
  if (p.publicStock <= 10) return 'Only ${p.publicStock} left';
  return '${p.publicStock} in stock';
}

Color stockColor(ProductModel p) => p.publicStock <= 10 ? AppColors.stockRed : AppColors.stockGreen;

/// "30-minute", "2-hour", "1-day" for a window given in minutes
String formatWindow(int minutes) {
  if (minutes >= 1440 && minutes % 1440 == 0) return '${minutes ~/ 1440}-day';
  if (minutes >= 60 && minutes % 60 == 0) return '${minutes ~/ 60}-hour';
  return '$minutes-minute';
}

// ══════════════════════════════════════
// Live stock (dual inventory)
// ══════════════════════════════════════

/// Green "live" dot that gently pulses
class LiveDot extends StatefulWidget {
  final double size;
  final Color color;
  const LiveDot({super.key, this.size = 8, this.color = _liveGreen});

  @override
  State<LiveDot> createState() => _LiveDotState();
}

class _LiveDotState extends State<LiveDot> with SingleTickerProviderStateMixin {
  late final AnimationController _pulse =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1400))..repeat(reverse: true);

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.size * 2,
      height: widget.size * 2,
      child: Stack(
        alignment: Alignment.center,
        children: [
          FadeTransition(
            opacity: Tween(begin: 0.35, end: 0.0).animate(_pulse),
            child: ScaleTransition(
              scale: Tween(begin: 1.0, end: 2.0).animate(_pulse),
              child: Container(
                width: widget.size,
                height: widget.size,
                decoration: BoxDecoration(color: widget.color, shape: BoxShape.circle),
              ),
            ),
          ),
          Container(
            width: widget.size,
            height: widget.size,
            decoration: BoxDecoration(color: widget.color, shape: BoxShape.circle),
          ),
        ],
      ),
    );
  }
}

/// "Live stock · synced with the store shelf" with the stock count.
/// [compact] is a single short line for cards and sheets.
class LiveStockIndicator extends StatelessWidget {
  final ProductModel product;
  final bool compact;

  const LiveStockIndicator({super.key, required this.product, this.compact = false});

  @override
  Widget build(BuildContext context) {
    if (compact) {
      return InkWell(
        onTap: () => showDualInventoryExplainer(context),
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const LiveDot(size: 6),
              const SizedBox(width: 2),
              Flexible(
                child: Text.rich(
                  TextSpan(children: [
                    const TextSpan(text: 'Live stock'),
                    TextSpan(
                      text: ' · ${stockLabel(product)}',
                      style: TextStyle(color: stockColor(product), fontWeight: FontWeight.w600),
                    ),
                  ]),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
                ),
              ),
              const SizedBox(width: 3),
              Icon(Icons.info_outline, size: 13, color: AppColors.textLight),
            ],
          ),
        ),
      );
    }

    return Material(
      color: _liveGreen.withValues(alpha: 0.06),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: () => showDualInventoryExplainer(context),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.fromLTRB(10, 12, 8, 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: _liveGreen.withValues(alpha: 0.25)),
          ),
          child: Row(
            children: [
              const LiveDot(),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      stockLabel(product),
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: stockColor(product)),
                    ),
                    Text(
                      'Live stock · synced with the store shelf',
                      style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(left: 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('How?', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.secondary)),
                    const SizedBox(width: 2),
                    Icon(Icons.info_outline, size: 18, color: AppColors.secondary),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One-line live stock note above a product grid (store screen)
class LiveStockNote extends StatelessWidget {
  const LiveStockNote({super.key});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => showDualInventoryExplainer(context),
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            const LiveDot(size: 6),
            const SizedBox(width: 4),
            Expanded(
              child: Text(
                'Live stock · synced with the store shelf',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
              ),
            ),
            Icon(Icons.info_outline, size: 16, color: AppColors.secondary),
          ],
        ),
      ),
    );
  }
}

Future<void> showDualInventoryExplainer(BuildContext context) {
  final timeout = AppConfig.current.vendorAcceptTimeoutMinutes;
  return _showExplainer(
    context,
    icon: Icons.inventory_2_outlined,
    color: _liveGreen,
    title: 'How live stock works',
    points: [
      const _Point(
        Icons.storefront_outlined,
        'One shelf, two ways to buy',
        'This store sells the same stock to walk-in customers and on Vendra. The count you see '
            'updates the moment anything sells — at the counter or online.',
      ),
      const _Point(
        Icons.shield_outlined,
        'A safety buffer for walk-ins',
        'The store keeps a few units aside for customers in the shop, so the app never offers '
            'the very last item on the shelf.',
      ),
      const _Point(
        Icons.lock_outline,
        'Your units are reserved instantly',
        'When you place an order, your units are reserved in the same step as payment. '
            'A walk-in sale can\'t take them while the store prepares your order.',
      ),
      _Point(
        Icons.timer_outlined,
        'Released if the store doesn\'t confirm',
        'If the store doesn\'t accept your order${timeout > 0 ? ' within $timeout minutes' : ' in time'}, '
            'the reservation is released and you\'re refunded in full.',
      ),
    ],
  );
}

// ══════════════════════════════════════
// Escrow
// ══════════════════════════════════════

/// Headline for where the money is, by escrow status (FR03): held / frozen / released
String escrowTrustHeadline(OrderModel order) {
  switch (order.escrowStatus) {
    case 'disputed':
      return 'Under admin review — escrow frozen';
    case 'released':
      return 'Order completed — payment released to the store';
    case 'refunded':
      return 'Escrow refunded to your Vendra wallet';
    default:
      return 'Payment held safely in Vendra Escrow';
  }
}

/// Dual-tone escrow emblem: a tinted shield carrying a solid lock
class EscrowEmblem extends StatelessWidget {
  final Color color;
  final double size;
  final IconData lock;

  const EscrowEmblem({super.key, required this.color, this.size = 40, this.lock = Icons.lock_rounded});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color.withValues(alpha: AppColors.isDark ? 0.2 : 0.1),
        borderRadius: BorderRadius.circular(size * 0.3),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Icon(Icons.shield, size: size * 0.78, color: color.withValues(alpha: 0.28)),
          Icon(lock, size: size * 0.38, color: color),
        ],
      ),
    );
  }
}

/// "Payment held safely in Vendra Escrow" with a "How it works" link.
/// [compact] is a slim single row (e.g. above the pay button).
class EscrowTrustBadge extends StatelessWidget {
  final bool compact;
  final String? subtitle;

  const EscrowTrustBadge({super.key, this.compact = false, this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.successSurface,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: () => showEscrowExplainer(context),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: compact ? const EdgeInsets.symmetric(horizontal: 10, vertical: 8) : const EdgeInsets.all(12),
          child: Row(
            children: [
              EscrowEmblem(color: _escrowGreen, size: compact ? 28 : 40),
              SizedBox(width: compact ? 8 : 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Payment held safely in Vendra Escrow',
                      style: TextStyle(
                        fontSize: compact ? 12 : 13,
                        fontWeight: FontWeight.w600,
                        color: _escrowGreen,
                      ),
                    ),
                    if (!compact)
                      Text(
                        subtitle ?? 'The store is paid only after verified doorstep delivery. Cancelled? Refunded in full.',
                        style: TextStyle(fontSize: 11, height: 1.35, color: AppColors.textSecondary),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 4),
              Icon(Icons.info_outline, size: compact ? 16 : 18, color: _escrowGreen),
            ],
          ),
        ),
      ),
    );
  }
}

Future<void> showEscrowExplainer(BuildContext context) {
  final window = AppConfig.current.disputeWindowMinutes;
  return _showExplainer(
    context,
    icon: Icons.lock_rounded,
    color: _escrowGreen,
    title: 'How Vendra Escrow protects you',
    points: [
      const _Point(
        Icons.account_balance_outlined,
        'Paid to Vendra, not the store',
        'Your payment is held by Vendra Escrow the moment you order. The store can\'t touch it yet.',
      ),
      _Point(
        Icons.local_shipping_outlined,
        'Released only after delivery',
        'The store is paid after your order is delivered (or you confirm pickup) and the '
            '${window > 0 ? '${formatWindow(window)} ' : ''}dispute window closes without an issue.',
      ),
      const _Point(
        Icons.replay_rounded,
        'Refunded if something goes wrong',
        'If the order is cancelled, or a dispute you raise is upheld, the full amount goes back to your Vendra wallet.',
      ),
    ],
  );
}

// ══════════════════════════════════════
// Explainer sheet
// ══════════════════════════════════════

class _Point {
  final IconData icon;
  final String title;
  final String body;
  const _Point(this.icon, this.title, this.body);
}

Future<void> _showExplainer(
  BuildContext context, {
  required IconData icon,
  required Color color,
  required String title,
  required List<_Point> points,
}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (ctx) => SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.85),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(color: AppColors.hairline, borderRadius: BorderRadius.circular(2)),
                ),
              ),
              Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(color: color.withValues(alpha: 0.12), shape: BoxShape.circle),
                    child: Icon(icon, color: color, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(title,
                        style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              for (final p in points)
                Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(p.icon, size: 20, color: color),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(p.title,
                                style: TextStyle(
                                    fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                            const SizedBox(height: 2),
                            Text(p.body,
                                style: TextStyle(fontSize: 13, height: 1.4, color: AppColors.textSecondary)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 4),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(ctx),
                  style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 12)),
                  child: const Text('Got it'),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
