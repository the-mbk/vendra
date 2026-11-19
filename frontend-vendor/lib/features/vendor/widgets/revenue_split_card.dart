// ══════════════════════════════════════════════════════════════
// Vendra Vendor App - Revenue by channel (SRDS §2.1)
// The owner's two channels side by side: walk-in POS sales (cash / card
// at the counter) and Vendra online orders whose escrow has cleared to the
// store wallet (after commission). Today or the last 30 days, plus what
// is still held in escrow. GET /api/vendor/revenue
// ══════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:vendra_vendor/vendra_core.dart';

final NumberFormat _money = NumberFormat('#,##0');

class _Channel {
  final double walkIn;
  final int walkInCount;
  final double online;
  final int onlineCount;
  const _Channel(this.walkIn, this.walkInCount, this.online, this.onlineCount);

  factory _Channel.fromJson(Map<String, dynamic>? j) => _Channel(
        toDouble(j?['walkIn']),
        toInt(j?['walkInCount']),
        toDouble(j?['online']),
        toInt(j?['onlineCount']),
      );

  double get total => walkIn + online;
}

class RevenueSplitCard extends StatefulWidget {
  /// Changes whenever a walk-in sale completes, so the card reloads
  final Object refreshKey;
  final VoidCallback? onOpenPos;

  const RevenueSplitCard({super.key, required this.refreshKey, this.onOpenPos});

  @override
  State<RevenueSplitCard> createState() => _RevenueSplitCardState();
}

class _RevenueSplitCardState extends State<RevenueSplitCard> {
  _Channel? _today;
  _Channel? _month;
  double _inEscrow = 0;
  int _escrowOrders = 0;
  bool _showMonth = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant RevenueSplitCard old) {
    super.didUpdateWidget(old);
    if (old.refreshKey != widget.refreshKey) _load();
  }

  Future<void> _load() async {
    try {
      final res = await ApiService().get(ApiConfig.vendorRevenue);
      final data = Map<String, dynamic>.from(res.data['data'] as Map);
      final escrow = Map<String, dynamic>.from(data['inEscrow'] as Map? ?? const {});
      if (!mounted) return;
      setState(() {
        _today = _Channel.fromJson(Map<String, dynamic>.from(data['today'] as Map));
        _month = _Channel.fromJson(Map<String, dynamic>.from(data['last30Days'] as Map));
        _inEscrow = toDouble(escrow['amount']);
        _escrowOrders = toInt(escrow['orders']);
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = ApiService.getErrorMessage(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final channel = _showMonth ? _month : _today;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('Revenue by channel',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
              ),
              SegmentedButton<bool>(
                showSelectedIcon: false,
                style: SegmentedButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  textStyle: const TextStyle(fontSize: 12),
                ),
                segments: const [
                  ButtonSegment(value: false, label: Text('Today')),
                  ButtonSegment(value: true, label: Text('30 days')),
                ],
                selected: {_showMonth},
                onSelectionChanged: (v) => setState(() => _showMonth = v.first),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (channel == null)
            _error != null
                ? Row(
                    children: [
                      Expanded(child: Text(_error!, style: const TextStyle(fontSize: 12, color: AppColors.error))),
                      TextButton(onPressed: _load, child: const Text('Retry')),
                    ],
                  )
                : const Center(child: Padding(padding: EdgeInsets.all(12), child: CircularProgressIndicator(strokeWidth: 2)))
          else ...[
            _splitBar(channel),
            const SizedBox(height: 14),
            _row(
              icon: Icons.point_of_sale,
              color: AppColors.secondary,
              title: 'Walk-in POS revenue',
              hint: '${channel.walkInCount} sale${channel.walkInCount == 1 ? '' : 's'} · direct cash / card',
              amount: channel.walkIn,
              onTap: widget.onOpenPos,
            ),
            const SizedBox(height: 10),
            _row(
              icon: Icons.language,
              color: AppColors.primary,
              title: 'Vendra online orders',
              hint: '${channel.onlineCount} order${channel.onlineCount == 1 ? '' : 's'} · escrow cleared, after commission',
              amount: channel.online,
            ),
            if (_escrowOrders > 0) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  Icon(Icons.lock_outline, size: 14, color: AppColors.textSecondary),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Rs. ${_money.format(_inEscrow)} in escrow on $_escrowOrders online order${_escrowOrders == 1 ? '' : 's'} '
                      '— paid out after delivery and the dispute window.',
                      style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ],
      ),
    );
  }

  Widget _splitBar(_Channel c) {
    final total = c.total;
    final walkInShare = total > 0 ? c.walkIn / total : 0.5;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Rs. ${_money.format(total)}',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: SizedBox(
            height: 8,
            child: total <= 0
                ? ColoredBox(color: AppColors.surfaceMuted)
                : Row(
                    children: [
                      if (c.walkIn > 0)
                        Expanded(flex: (walkInShare * 1000).round(), child: ColoredBox(color: AppColors.secondary)),
                      if (c.online > 0)
                        Expanded(flex: ((1 - walkInShare) * 1000).round(), child: const ColoredBox(color: AppColors.primary)),
                    ],
                  ),
          ),
        ),
      ],
    );
  }

  Widget _row({
    required IconData icon,
    required Color color,
    required String title,
    required String hint,
    required double amount,
    VoidCallback? onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: color.withValues(alpha: AppColors.isDark ? 0.2 : 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 18, color: color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                Text(hint, style: TextStyle(fontSize: 11, color: AppColors.textSecondary)),
              ],
            ),
          ),
          Text('Rs. ${_money.format(amount)}',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: color)),
        ],
      ),
    );
  }
}
