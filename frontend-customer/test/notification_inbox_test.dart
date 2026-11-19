// Notification inbox: kind / icon / colour per type, relative times and
// the Today / Yesterday / Earlier grouping (shared core, same in all apps).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vendra_customer/vendra_core.dart';

NotificationModel _n(int id, DateTime at, {String type = 'order_confirmed'}) =>
    NotificationModel(id: id, type: type, title: 'T$id', createdAt: at);

void main() {
  final now = DateTime(2026, 11, 18, 22, 30);

  test('each type gets a kind label and icon', () {
    expect(notificationStyleFor('order_confirmed').label, 'Order');
    expect(notificationStyleFor('order_delivered').icon, Icons.check_circle_outline);
    expect(notificationStyleFor('order_on_the_way').label, 'Delivery');
    expect(notificationStyleFor('rider_arrived').label, 'Delivery');
    expect(notificationStyleFor('escrow_refund').label, 'Refund');
    expect(notificationStyleFor('escrow_released').label, 'Payment');
    expect(notificationStyleFor('withdrawal_paid').label, 'Payment');
    expect(notificationStyleFor('dispute_opened').label, 'Dispute');
    expect(notificationStyleFor('low_stock').label, 'Stock');
    expect(notificationStyleFor('review_received').label, 'Review');
    expect(notificationStyleFor('rider_approved').label, 'Account');
    expect(notificationStyleFor('product_approved').label, 'Store');
    expect(notificationStyleFor('something_new').label, 'Update');
  });

  test('problems are shown in the error colour', () {
    expect(notificationStyleFor('order_cancelled').color, AppColors.error);
    expect(notificationStyleFor('withdrawal_failed').color, AppColors.error);
    expect(notificationStyleFor('product_hidden').color, AppColors.error);
    expect(notificationStyleFor('withdrawal_paid').color, AppColors.success);
  });

  test('relative times', () {
    expect(notificationTimeLabel(now.subtract(const Duration(seconds: 20)), now: now), 'Just now');
    expect(notificationTimeLabel(now.subtract(const Duration(minutes: 5)), now: now), '5 min ago');
    expect(notificationTimeLabel(now.subtract(const Duration(hours: 3)), now: now), '3 h ago');
    expect(notificationTimeLabel(DateTime(2026, 11, 17, 15, 10), now: now), 'Yesterday, 3:10 PM');
    expect(notificationTimeLabel(DateTime(2026, 11, 16, 9, 5), now: now), 'Mon, 9:05 AM');
    expect(notificationTimeLabel(DateTime(2026, 11, 2, 9, 5), now: now), '2 Nov, 9:05 AM');
    expect(notificationTimeLabel(DateTime(2025, 11, 2, 9, 5), now: now), '2 Nov 2025');
  });

  test('grouped Today / Yesterday / Earlier, newest first', () {
    final groups = groupNotificationsByDay([
      _n(1, DateTime(2026, 11, 18, 21)),
      _n(2, DateTime(2026, 11, 18, 8)),
      _n(3, DateTime(2026, 11, 17, 20)),
      _n(4, DateTime(2026, 11, 10, 20)),
      _n(5, DateTime(2026, 10, 10, 20)),
    ], now: now);
    expect(groups.map((g) => g.$1).toList(), ['Today', 'Yesterday', 'Earlier']);
    expect(groups.map((g) => g.$2.length).toList(), [2, 1, 2]);
    expect(notificationDayGroup(null, now: now), 'Earlier');
  });
}
