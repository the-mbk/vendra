// ══════════════════════════════════════════════════════════════
// Vendra Vendor App - Dual-inventory matrix (FR01)
// The four numbers behind phantom-stock prevention, side by side:
//   Physical shelf (private)  units in the shop right now
//   Walk-in buffer            kept back for counter customers
//   Active reservations       locked by open online orders
//   Online available (public) = private − buffer − reserved (never below 0)
// Each has its own semantic tint: navy, slate, amber, green.
// ══════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';

import '../../config/app_theme.dart';

class DualStockMatrix extends StatelessWidget {
  final int privateStock;
  final int buffer;
  final int reserved;

  /// Small labels and numbers (dialogs); otherwise the full card with the formula line
  final bool compact;

  const DualStockMatrix({
    super.key,
    required this.privateStock,
    required this.buffer,
    required this.reserved,
    this.compact = false,
  });

  /// What the marketplace may sell: the same rule the server applies
  int get onlineAvailable {
    final available = privateStock - buffer - reserved;
    return available < 0 ? 0 : available;
  }

  static const _slate = Color(0xFF64748B);

  @override
  Widget build(BuildContext context) {
    final cells = [
      _Cell('Physical shelf', 'Private', privateStock, AppColors.secondary, Icons.inventory_2_outlined),
      _Cell('Walk-in buffer', 'Counter only', buffer, _slate, Icons.storefront_outlined),
      _Cell('Reserved', 'Open online orders', reserved, AppColors.reservedAmber, Icons.lock_outline),
      _Cell('Online available', 'Public', onlineAvailable, AppColors.stockGreen, Icons.public),
    ];

    final grid = LayoutBuilder(
      builder: (context, constraints) {
        // Four across when there is room, otherwise two by two
        final perRow = constraints.maxWidth >= 360 ? 4 : 2;
        const gap = 8.0;
        final width = (constraints.maxWidth - gap * (perRow - 1)) / perRow;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [for (final c in cells) SizedBox(width: width, child: _cell(c))],
        );
      },
    );

    if (compact) return grid;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          grid,
          const SizedBox(height: 10),
          Text(
            'Online = $privateStock − $buffer − $reserved = $onlineAvailable',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              color: AppColors.textSecondary,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }

  Widget _cell(_Cell c) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 8, vertical: compact ? 8 : 10),
      decoration: BoxDecoration(
        color: c.color.withValues(alpha: AppColors.isDark ? 0.16 : 0.07),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: c.color.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(c.icon, size: 14, color: c.color),
              const Spacer(),
              Text(
                '${c.value}',
                style: TextStyle(
                  fontSize: compact ? 16 : 20,
                  fontWeight: FontWeight.w700,
                  color: c.color,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(c.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
          if (!compact)
            Text(c.hint,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 10, color: AppColors.textSecondary)),
        ],
      ),
    );
  }
}

class _Cell {
  final String label;
  final String hint;
  final int value;
  final Color color;
  final IconData icon;
  const _Cell(this.label, this.hint, this.value, this.color, this.icon);
}
