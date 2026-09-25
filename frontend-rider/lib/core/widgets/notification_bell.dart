// ══════════════════════════════════════════════════════════════
// Vendra App - Notification bell + inbox screen (FR09)
// Drop NotificationBell() into any AppBar's actions.
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

  @override
  void initState() {
    super.initState();
    _center.refresh().then((_) => _center.markAllRead());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Notifications')),
      body: AnimatedBuilder(
        animation: _center,
        builder: (context, _) {
          final items = _center.items;
          if (_center.isLoading && items.isEmpty) {
            return const Center(child: CircularProgressIndicator());
          }
          if (items.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text(
                  'No notifications yet. Order updates will show up here.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.textSecondary),
                ),
              ),
            );
          }
          return RefreshIndicator(
            onRefresh: _center.refresh,
            child: ListView.separated(
              itemCount: items.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, i) => _NotificationTile(
                n: items[i],
                onTap: items[i].orderId != null && widget.onOpenOrder != null
                    ? () => widget.onOpenOrder!(context, items[i].orderId!)
                    : null,
              ),
            ),
          );
        },
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
