// ══════════════════════════════════════════════════════════════
// Vendra App - One message in an order's customer ↔ rider chat
// (GET/POST /api/orders/:id/messages, live as 'chat:message')
// ══════════════════════════════════════════════════════════════

import 'json_utils.dart';

class ChatMessage {
  final int id;
  final int orderId;

  /// 'customer' or 'rider'
  final String senderRole;
  final String body;
  final DateTime? createdAt;

  const ChatMessage({required this.id, required this.orderId, required this.senderRole, required this.body, this.createdAt});

  factory ChatMessage.fromJson(Map<String, dynamic> json) => ChatMessage(
        id: toInt(json['id']),
        orderId: toInt(json['orderId']),
        senderRole: json['senderRole']?.toString() ?? 'customer',
        body: json['body']?.toString() ?? '',
        createdAt: toDate(json['createdAt']),
      );
}

/// Who you are talking to (GET /api/orders/:id/messages → with): short name,
/// photo, and their number only while the delivery is open
class ChatCounterpart {
  /// 'rider' or 'customer'
  final String role;
  final String name;
  final String? photoUrl;
  final String? phone;
  final String? vehicleType;

  const ChatCounterpart({required this.role, required this.name, this.photoUrl, this.phone, this.vehicleType});

  static ChatCounterpart? tryParse(dynamic json) {
    if (json is! Map) return null;
    final role = json['role']?.toString() ?? 'customer';
    return ChatCounterpart(
      role: role,
      name: json['name']?.toString() ?? (role == 'rider' ? 'Your rider' : 'Customer'),
      photoUrl: json['photoUrl']?.toString(),
      phone: json['phone']?.toString(),
      vehicleType: json['vehicleType']?.toString(),
    );
  }

  bool get isRider => role == 'rider';

  /// "Your rider · Motorcycle" / "Customer"
  String get subtitle {
    if (!isRider) return 'Customer';
    final v = vehicleType;
    if (v == null || v.isEmpty) return 'Your rider';
    return 'Your rider · ${v[0].toUpperCase()}${v.substring(1).replaceAll('_', ' ')}';
  }
}
