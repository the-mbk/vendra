// ══════════════════════════════════════════════════════════════
// Vendra App - Notification bell + inbox screen (FR09)
// Drop NotificationBell() into any AppBar's actions.
// The inbox keeps every alert, grouped Today / Yesterday / Earlier.
// Each row says what kind of update it is (order, delivery, payment,
// dispute, stock...) with its own icon and colour, when it happened
// ("5 min ago"), and whether it is unread (orange dot + tint). Tap one
// to mark it read and open its order; scroll to the end for older ones.
// ══════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../config/app_theme.dart';
import '../models/notification_model.dart';
import '../services/notification_center.dart';

/// How one notification type is presented: icon, accent colour and a short kind label
class NotificationStyle {
  final IconData icon;
  final Color color;

  /// "Order", "Delivery", "Payment", "Dispute", "Stock"...
  final String label;
  const NotificationStyle(this.icon, this.color, this.label);
}

const _problemTypes = {
  'order_cancelled',
  'payment_order_failed',
  'withdrawal_failed',
  'withdrawal_reversal',
  'otp_locked',
  'vendor_suspended',
  'rider_rejected',
  'product_hidden',
  'location_rejected',
};

/// Icon, colour and kind label for a notification type (unknown types fall back to a plain update)
NotificationStyle notificationStyleFor(String type) {
  final problem = _problemTypes.contains(type);
  Color tone(Color normal) => problem ? AppColors.error : normal;

  if (type == 'order_delivered') return const NotificationStyle(Icons.check_circle_outline, AppColors.success, 'Order');
  if (type == 'order_cancelled') return const NotificationStyle(Icons.cancel_outlined, AppColors.error, 'Order');
  if (const {'order_picked', 'order_on_the_way', 'rider_assigned', 'rider_arrived', 'rider_released', 'task_available'}
      .contains(type)) {
    return const NotificationStyle(Icons.delivery_dining_outlined, AppColors.primary, 'Delivery');
  }
  if (type == 'task_released') return NotificationStyle(Icons.delivery_dining_outlined, AppColors.warningInk, 'Delivery');
  if (type.startsWith('order_')) return NotificationStyle(Icons.receipt_long_outlined, AppColors.secondary, 'Order');
  if (type == 'escrow_refund') return const NotificationStyle(Icons.replay, AppColors.success, 'Refund');
  if (type.startsWith('escrow') ||
      type.startsWith('withdrawal') ||
      type.startsWith('payment') ||
      type.startsWith('wallet') ||
      type == 'rider_payout') {
    return NotificationStyle(Icons.account_balance_wallet_outlined, tone(AppColors.success), 'Payment');
  }
  if (type.startsWith('dispute')) return NotificationStyle(Icons.gavel_outlined, AppColors.warningInk, 'Dispute');
  if (type == 'low_stock') return NotificationStyle(Icons.inventory_2_outlined, AppColors.warningInk, 'Stock');
  if (type == 'stock_in') return const NotificationStyle(Icons.inventory_2_outlined, AppColors.success, 'Stock');
  if (type.startsWith('review') || type == 'rider_rated') {
    return const NotificationStyle(Icons.star_outline_rounded, AppColors.reservedAmber, 'Review');
  }
  if (type.startsWith('chat')) return NotificationStyle(Icons.chat_bubble_outline, AppColors.secondary, 'Message');
  if (type.startsWith('otp')) return NotificationStyle(Icons.lock_outline, tone(AppColors.secondary), 'Security');
  if (type.startsWith('rider_')) return NotificationStyle(Icons.badge_outlined, tone(AppColors.info), 'Account');
  if (type.startsWith('product') || type.startsWith('vendor') || type.startsWith('location')) {
    return NotificationStyle(Icons.storefront_outlined, tone(AppColors.info), 'Store');
  }
  return NotificationStyle(Icons.notifications_none_rounded, AppColors.secondary, 'Update');
}

DateTime _day(DateTime t) => DateTime(t.year, t.month, t.day);

/// "Just now", "5 min ago", "3 h ago", "Yesterday, 3:10 PM", "Mon, 3:10 PM", "12 Nov, 3:10 PM", "12 Nov 2025"
String notificationTimeLabel(DateTime at, {DateTime? now}) {
  final t = at.toLocal();
  final n = (now ?? DateTime.now()).toLocal();
  final diff = n.difference(t);
  if (diff.inSeconds < 60) return 'Just now';
  final days = _day(n).difference(_day(t)).inDays;
  if (days == 0) return diff.inMinutes < 60 ? '${diff.inMinutes} min ago' : '${diff.inHours} h ago';
  final clock = DateFormat('h:mm a').format(t);
  if (days == 1) return 'Yesterday, $clock';
  if (days > 1 && days < 7) return '${DateFormat('EEE').format(t)}, $clock';
  if (t.year == n.year) return '${DateFormat('d MMM').format(t)}, $clock';
  return DateFormat('d MMM yyyy').format(t);
}

/// The inbox section a notification belongs to: "Today", "Yesterday" or "Earlier"
String notificationDayGroup(DateTime? at, {DateTime? now}) {
  if (at == null) return 'Earlier';
  final days = _day((now ?? DateTime.now()).toLocal()).difference(_day(at.toLocal())).inDays;
  if (days <= 0) return 'Today';
  if (days == 1) return 'Yesterday';
  return 'Earlier';
}

/// Consecutive runs of [items] (newest first) under their day headings
List<(String, List<NotificationModel>)> groupNotificationsByDay(List<NotificationModel> items, {DateTime? now}) {
  final groups = <(String, List<NotificationModel>)>[];
  for (final n in items) {
    final label = notificationDayGroup(n.createdAt, now: now);
    if (groups.isEmpty || groups.last.$1 != label) {
      groups.add((label, [n]));
    } else {
      groups.last.$2.add(n);
    }
  }
  return groups;
}

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
          textColor: Colors.white,
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

  void _open(NotificationModel n) {
    _center.markRead(n);
    if (n.orderId != null && widget.onOpenOrder != null) widget.onOpenOrder!(context, n.orderId!);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Notifications'),
        actions: [
          AnimatedBuilder(
            animation: _center,
            builder: (context, _) => TextButton.icon(
              onPressed: _center.unreadCount > 0 ? _center.markAllRead : null,
              icon: const Icon(Icons.done_all, size: 18),
              label: const Text('Mark all read'),
            ),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: AnimatedBuilder(
        animation: _center,
        builder: (context, _) {
          final all = _center.items;
          final items = _unreadOnly ? all.where((n) => !n.isRead).toList() : all;
          final filters = _Filters(
            unreadOnly: _unreadOnly,
            unreadCount: _center.unreadCount,
            onChanged: (v) => setState(() => _unreadOnly = v),
          );
          if (_center.isLoading && items.isEmpty) {
            return const Center(child: CircularProgressIndicator());
          }
          if (items.isEmpty && !_center.hasMore) {
            return Column(children: [
              filters,
              Expanded(child: _EmptyInbox(unreadOnly: _unreadOnly)),
            ]);
          }

          final rows = <Widget>[filters];
          for (final (label, group) in groupNotificationsByDay(items)) {
            rows.add(_DayHeading(label: label));
            rows.add(_GroupCard(
              children: [
                for (final n in group)
                  _NotificationTile(
                    n: n,
                    canOpenOrder: n.orderId != null && widget.onOpenOrder != null,
                    onTap: () => _open(n),
                  ),
              ],
            ));
          }
          rows.add(_OlderButton(center: _center));

          return RefreshIndicator(
            onRefresh: _center.refresh,
            child: ListView(padding: const EdgeInsets.only(bottom: 24), children: rows),
          );
        },
      ),
    );
  }
}

class _Filters extends StatelessWidget {
  final bool unreadOnly;
  final int unreadCount;
  final ValueChanged<bool> onChanged;
  const _Filters({required this.unreadOnly, required this.unreadCount, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Row(children: [
        ChoiceChip(label: const Text('All'), selected: !unreadOnly, onSelected: (_) => onChanged(false)),
        const SizedBox(width: 8),
        ChoiceChip(label: Text('Unread ($unreadCount)'), selected: unreadOnly, onSelected: (_) => onChanged(true)),
      ]),
    );
  }
}

class _DayHeading extends StatelessWidget {
  final String label;
  const _DayHeading({required this.label});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
      child: Text(
        label.toUpperCase(),
        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 0.8, color: AppColors.textSecondary),
      ),
    );
  }
}

/// One rounded card per day, rows separated by hairlines
class _GroupCard extends StatelessWidget {
  final List<Widget> children;
  const _GroupCard({required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.hairline),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) Divider(height: 1, thickness: 1, indent: 68, color: AppColors.hairline),
            children[i],
          ],
        ],
      ),
    );
  }
}

class _EmptyInbox extends StatelessWidget {
  final bool unreadOnly;
  const _EmptyInbox({required this.unreadOnly});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(color: AppColors.secondary.withValues(alpha: 0.10), shape: BoxShape.circle),
              child: Icon(unreadOnly ? Icons.done_all : Icons.notifications_none_rounded,
                  size: 34, color: AppColors.secondary),
            ),
            const SizedBox(height: 16),
            Text(unreadOnly ? "You're all caught up" : 'No notifications yet',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
            const SizedBox(height: 6),
            Text(
              unreadOnly
                  ? 'Nothing new since you last looked.'
                  : 'Order updates, payments and messages will show up here.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, height: 1.4, color: AppColors.textSecondary),
            ),
          ],
        ),
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
          : Padding(
              padding: const EdgeInsets.all(20),
              child: Center(
                child: Text("That's everything.", style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
              ),
            );
    }
    return Padding(
      padding: const EdgeInsets.all(16),
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
  final bool canOpenOrder;
  final VoidCallback onTap;
  const _NotificationTile({required this.n, required this.canOpenOrder, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final style = notificationStyleFor(n.type);
    final unread = !n.isRead;
    final kind = n.orderId != null ? '${style.label} · Order #${n.orderId}' : style.label;
    final body = n.body?.trim();

    return Material(
      color: unread ? AppColors.primary.withValues(alpha: AppColors.isDark ? 0.10 : 0.05) : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: style.color.withValues(alpha: AppColors.isDark ? 0.20 : 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(style.icon, color: style.color, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            kind,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontSize: 12, fontWeight: FontWeight.w600, letterSpacing: 0.2, color: style.color),
                          ),
                        ),
                        if (n.createdAt != null)
                          Text(notificationTimeLabel(n.createdAt!),
                              style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                        if (unread) ...[
                          const SizedBox(width: 6),
                          Semantics(
                            label: 'Unread',
                            child: Container(
                              width: 9,
                              height: 9,
                              decoration: const BoxDecoration(color: AppColors.primary, shape: BoxShape.circle),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      n.title,
                      style: TextStyle(
                        fontSize: 15,
                        height: 1.3,
                        fontWeight: unread ? FontWeight.w700 : FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    if (body != null && body.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        body,
                        style: TextStyle(
                          fontSize: 14,
                          height: 1.4,
                          color: AppColors.textPrimary.withValues(alpha: 0.78),
                        ),
                      ),
                    ],
                    if (canOpenOrder) ...[
                      const SizedBox(height: 6),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text('View order',
                              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.secondary)),
                          Icon(Icons.chevron_right, size: 18, color: AppColors.secondary),
                        ],
                      ),
                    ],
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
