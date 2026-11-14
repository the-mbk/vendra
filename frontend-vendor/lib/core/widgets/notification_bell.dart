// ══════════════════════════════════════════════════════════════
// Vendra App - Notification bell + inbox screen (FR09)
// Drop NotificationBell() into any AppBar's actions.
// The inbox keeps every alert: scroll to the end to load older ones,
// filter to unread, tap one to mark it read and open its order.
// ══════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../config/app_theme.dart';
import '../models/notification_model.dart';
import '../services/notification_center.dart';

class NotificationBell extends StatelessWidget {
  /// Called when a notification that belongs to an order is tapped
  final void Function(BuildContext context, int orderId)? onOpenOrder;
  final Color? color;

  const NotificationBell({super.key, this.onOpenOrder, this.color});

  @override
  Widget build(BuildContext context) {
    final center = NotificationCenter();
    return AnimatedBuilder(
      animation: center,
      builder: (context, _) => IconButton(
        tooltip: 'Notifications',
        onPressed: () => Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => NotificationsScreen(onOpenOrder: onOpenOrder),
        )),
        icon: Badge(
          isLabelVisible: center.unreadCount > 0,
          label: Text(center.unreadCount > 99 ? '99+' : '${center.unreadCount}'),
          backgroundColor: AppColors.primary,
          child: Icon(Icons.notifications_outlined, color: color),
        ),
      ),
    );
  }
}

class NotificationsScreen extends StatefulWidget {
  final void Function(BuildContext context, int orderId)? onOpenOrder;
  const NotificationsScreen({super.key, this.onOpenOrder});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  final _center = NotificationCenter();
  bool _unreadOnly = false;

  @override
  void initState() {
    super.initState();
    _center.refresh();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications'),
        actions: [
          AnimatedBuilder(
            animation: _center,
            builder: (context, _) => TextButton(
              onPressed: _center.unreadCount > 0 ? _center.markAllRead : null,
              child: const Text('Mark all read'),
            ),
          ),
        ],
      ),
      body: AnimatedBuilder(
        animation: _center,
        builder: (context, _) {
          final all = _center.items;
          final items = _unreadOnly ? all.where((n) => !n.isRead).toList() : all;
          final filters = Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Wrap(spacing: 8, children: [
              ChoiceChip(label: const Text('All'), selected: !_unreadOnly, onSelected: (_) => setState(() => _unreadOnly = false)),
              ChoiceChip(
                label: Text('Unread (${_center.unreadCount})'),
                selected: _unreadOnly,
                onSelected: (_) => setState(() => _unreadOnly = true),
              ),
            ]),
          );
          if (_center.isLoading && items.isEmpty) {
            return const Center(child: CircularProgressIndicator());
          }
          if (items.isEmpty && !_center.hasMore) {
            return Column(children: [
              filters,
              Expanded(
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Text(
                      _unreadOnly ? "You're all caught up." : 'No notifications yet. Order updates will show up here.',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: AppColors.textSecondary),
                    ),
                  ),
                ),
              ),
            ]);
          }
          return RefreshIndicator(
            onRefresh: _center.refresh,
            child: ListView.separated(
              itemCount: items.length + 2,
              separatorBuilder: (_, i) => i == 0 ? const SizedBox.shrink() : const Divider(height: 1),
              itemBuilder: (context, i) {
                if (i == 0) return filters;
                if (i == items.length + 1) return _OlderButton(center: _center);
                final n = items[i - 1];
                return _NotificationTile(
                  n: n,
                  onTap: () {
                    _center.markRead(n);
                    if (n.orderId != null && widget.onOpenOrder != null) widget.onOpenOrder!(context, n.orderId!);
                  },
                );
              },
            ),
          );
        },
      ),
    );
  }
}

/// "Load older" at the end of the list (or a spinner while it loads)
class _OlderButton extends StatelessWidget {
  final NotificationCenter center;
  const _OlderButton({required this.center});

  @override
  Widget build(BuildContext context) {
    if (center.isLoadingMore) {
      return const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator(strokeWidth: 2)));
    }
    if (!center.hasMore) {
      return center.items.isEmpty
          ? const SizedBox.shrink()
          : const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: Text("That's everything.", style: TextStyle(color: AppColors.textLight, fontSize: 12))),
            );
    }
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Center(
        child: OutlinedButton.icon(
          onPressed: center.loadMore,
          icon: const Icon(Icons.history, size: 18),
          label: const Text('Load older notifications'),
        ),
      ),
    );
  }
}

class _NotificationTile extends StatelessWidget {
  final NotificationModel n;
  final VoidCallback? onTap;
  const _NotificationTile({required this.n, this.onTap});

  IconData get _icon {
    if (n.type.startsWith('dispute')) return Icons.gavel_outlined;
    if (n.type.startsWith('escrow')) return Icons.account_balance_wallet_outlined;
    if (n.type.startsWith('task') || n.type.startsWith('rider')) return Icons.delivery_dining_outlined;
    if (n.type.startsWith('product') || n.type.startsWith('vendor')) return Icons.storefront_outlined;
    if (n.type.startsWith('review')) return Icons.star_outline_rounded;
    if (n.type.startsWith('otp')) return Icons.lock_outline;
    return Icons.receipt_long_outlined;
  }

  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: onTap,
      tileColor: n.isRead ? null : AppColors.primary.withValues(alpha: 0.05),
      leading: CircleAvatar(
        backgroundColor: AppColors.secondary.withValues(alpha: 0.1),
        child: Icon(_icon, color: AppColors.secondary, size: 20),
      ),
      title: Text(n.title, style: TextStyle(fontWeight: n.isRead ? FontWeight.w500 : FontWeight.w700)),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (n.body != null) Text(n.body!),
          if (n.createdAt != null)
            Text(DateFormat('d MMM, h:mm a').format(n.createdAt!),
                style: const TextStyle(fontSize: 11, color: AppColors.textLight)),
        ],
      ),
      isThreeLine: n.body != null,
    );
  }
}
