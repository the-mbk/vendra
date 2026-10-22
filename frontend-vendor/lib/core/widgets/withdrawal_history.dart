// ══════════════════════════════════════════════════════════════
// Vendra App - Withdrawal history (GET /api/withdrawals, paged)
// A non-scrolling list to embed in a wallet/earnings screen, with status
// chips (In transit / Paid / Returned). Reloads itself when a withdrawal
// notification arrives, polls gently while a payout is still in transit,
// and when [refreshKey] changes (e.g. right after a new withdrawal).
// ══════════════════════════════════════════════════════════════

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../config/api_config.dart';
import '../../config/app_theme.dart';
import '../models/notification_model.dart';
import '../models/page_meta.dart';
import '../models/payment_model.dart';
import '../services/api_service.dart';
import '../services/realtime_service.dart';
import 'amount_sheet.dart';

class WithdrawalStatusChip extends StatelessWidget {
  final WithdrawalModel withdrawal;
  const WithdrawalStatusChip({super.key, required this.withdrawal});

  @override
  Widget build(BuildContext context) {
    final color = withdrawal.isPaid
        ? AppColors.stockGreen
        : withdrawal.isFailed
            ? AppColors.stockRed
            : AppColors.reservedAmber;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            withdrawal.isPaid
                ? Icons.check_circle
                : withdrawal.isFailed
                    ? Icons.undo
                    : Icons.schedule,
            size: 12,
            color: color,
          ),
          const SizedBox(width: 4),
          Text(withdrawal.statusLabel,
              style: GoogleFonts.poppins(fontSize: 11, fontWeight: FontWeight.w600, color: color)),
        ],
      ),
    );
  }
}

class WithdrawalHistoryList extends StatefulWidget {
  /// Change it to force a reload (e.g. a counter bumped after a withdrawal)
  final Object? refreshKey;
  final int pageSize;
  final String emptyText;

  const WithdrawalHistoryList({
    super.key,
    this.refreshKey,
    this.pageSize = 10,
    this.emptyText = 'No withdrawals yet.',
  });

  @override
  State<WithdrawalHistoryList> createState() => _WithdrawalHistoryListState();
}

class _WithdrawalHistoryListState extends State<WithdrawalHistoryList> {
  final ApiService _api = ApiService();
  StreamSubscription<NotificationModel>? _notifSub;
  Timer? _poll;

  List<WithdrawalModel> _items = [];
  PageMeta _meta = const PageMeta();
  bool _loading = true;
  bool _loadingMore = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
    // withdrawal_paid / withdrawal_failed / withdrawal_reversal
    _notifSub = RealtimeService().notifications.listen((n) {
      if (n.type.startsWith('withdrawal')) _load(silent: true);
    });
  }

  @override
  void didUpdateWidget(covariant WithdrawalHistoryList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refreshKey != widget.refreshKey) _load(silent: true);
  }

  @override
  void dispose() {
    _notifSub?.cancel();
    _poll?.cancel();
    super.dispose();
  }

  /// Reloads the first page (keeps as many rows as are already shown)
  Future<void> _load({bool silent = false}) async {
    if (!silent) setState(() => _loading = true);
    final limit = _items.length > widget.pageSize ? _items.length : widget.pageSize;
    try {
      final res = await _api.get(ApiConfig.withdrawals, queryParams: {'limit': limit, 'offset': 0});
      if (!mounted) return;
      setState(() {
        _items = _parse(res.data);
        _meta = PageMeta.fromResponse(res.data);
        _error = null;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = ApiService.getErrorMessage(e);
        _loading = false;
      });
    }
    _schedulePoll();
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_meta.hasMore) return;
    setState(() => _loadingMore = true);
    try {
      final res = await _api.get(ApiConfig.withdrawals,
          queryParams: {'limit': widget.pageSize, 'offset': _meta.nextOffset ?? _items.length});
      if (!mounted) return;
      setState(() {
        _items = [..._items, ..._parse(res.data)];
        _meta = PageMeta.fromResponse(res.data);
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(ApiService.getErrorMessage(e))));
      }
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  /// While a payout is in transit, check again every few seconds (the socket
  /// notification usually gets there first)
  void _schedulePoll() {
    _poll?.cancel();
    if (!mounted || !_items.any((w) => w.isOnItsWay)) return;
    _poll = Timer(const Duration(seconds: 8), () => _load(silent: true));
  }

  static List<WithdrawalModel> _parse(dynamic body) => (body is Map && body['data'] is List)
      ? (body['data'] as List).whereType<Map>().map((w) => WithdrawalModel.fromJson(Map<String, dynamic>.from(w))).toList()
      : <WithdrawalModel>[];

  @override
  Widget build(BuildContext context) {
    if (_loading && _items.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))),
      );
    }
    if (_error != null && _items.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Column(
          children: [
            Text(_error!, textAlign: TextAlign.center, style: GoogleFonts.poppins(fontSize: 12, color: AppColors.textSecondary)),
            TextButton(onPressed: _load, child: const Text('Retry')),
          ],
        ),
      );
    }
    if (_items.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 20),
        child: Text(widget.emptyText,
            textAlign: TextAlign.center, style: GoogleFonts.poppins(fontSize: 13, color: AppColors.textSecondary)),
      );
    }
    return Container(
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
      child: Column(
        children: [
          for (var i = 0; i < _items.length; i++) ...[
            if (i > 0) const Divider(height: 1, indent: 64),
            _tile(_items[i]),
          ],
          if (_meta.hasMore)
            TextButton(
              onPressed: _loadingMore ? null : _loadMore,
              child: _loadingMore
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Show more'),
            ),
        ],
      ),
    );
  }

  Widget _tile(WithdrawalModel w) {
    final subtitle = [
      if (w.createdAt != null) DateFormat('d MMM yyyy, h:mm a').format(w.createdAt!),
      if (w.isFailed) '${w.failureMessage ?? 'The card refused the payout.'} The money is back in your wallet.',
      if (w.isOnItsWay) 'Usually arrives within a minute.',
    ].join('\n');
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: AppColors.secondary.withValues(alpha: 0.08),
        child: const Icon(Icons.north_east, color: AppColors.secondary, size: 20),
      ),
      title: Text('${formatRupees(w.amount)} to ${w.cardLabel}',
          style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w500)),
      subtitle: Text(subtitle, style: GoogleFonts.poppins(fontSize: 11, color: AppColors.textSecondary)),
      isThreeLine: subtitle.contains('\n'),
      trailing: WithdrawalStatusChip(withdrawal: w),
    );
  }
}
