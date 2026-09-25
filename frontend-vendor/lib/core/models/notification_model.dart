// ══════════════════════════════════════════════════════════════
// Vendra App - Notification Model (FR09)
// ══════════════════════════════════════════════════════════════

import 'json_utils.dart';

class NotificationModel {
  final int id;
  final String type;
  final String title;
  final String? body;
  final int? orderId;
  final bool isRead;
  final DateTime? createdAt;

  NotificationModel({
    required this.id,
    required this.type,
    required this.title,
    this.body,
    this.orderId,
    this.isRead = false,
    this.createdAt,
  });

  factory NotificationModel.fromJson(Map<String, dynamic> json) => NotificationModel(
        id: toInt(json['id']),
        type: json['type'] ?? 'info',
        title: json['title'] ?? '',
        body: json['body'],
        orderId: toIntOrNull(json['orderId']),
        isRead: json['isRead'] ?? false,
        createdAt: toDate(json['createdAt']),
      );

  NotificationModel markRead() => NotificationModel(
        id: id, type: type, title: title, body: body, orderId: orderId, isRead: true, createdAt: createdAt,
      );
}
