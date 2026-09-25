// ══════════════════════════════════════════════════════════════
// Vendra App - Dispute Model (FR08)
// ══════════════════════════════════════════════════════════════

import 'json_utils.dart';

class DisputeModel {
  final int id;
  final int orderId;
  final String issueType;
  final String description;
  final String status; // open | resolved
  final String? resolution; // refund | release
  final String? adminNote;
  final String? raisedByName;
  final String? raisedByRole;
  final String? orderStatus;
  final String? escrowStatus;
  final double heldAmount;
  final String? storeName;
  final List<String> evidenceUrls; // server paths — wrap with ApiConfig.fileUrl
  final DateTime? createdAt;
  final DateTime? resolvedAt;

  DisputeModel({
    required this.id,
    required this.orderId,
    required this.issueType,
    required this.description,
    required this.status,
    this.resolution,
    this.adminNote,
    this.raisedByName,
    this.raisedByRole,
    this.orderStatus,
    this.escrowStatus,
    this.heldAmount = 0,
    this.storeName,
    this.evidenceUrls = const [],
    this.createdAt,
    this.resolvedAt,
  });

  factory DisputeModel.fromJson(Map<String, dynamic> json) {
    final raisedBy = json['raisedBy'] as Map<String, dynamic>? ?? const {};
    final order = json['order'] as Map<String, dynamic>? ?? const {};
    return DisputeModel(
      id: toInt(json['id']),
      orderId: toInt(json['orderId']),
      issueType: json['issueType'] ?? 'other',
      description: json['description'] ?? '',
      status: json['status'] ?? 'open',
      resolution: json['resolution'],
      adminNote: json['adminNote'],
      raisedByName: raisedBy['name'],
      raisedByRole: raisedBy['role'],
      orderStatus: order['status'],
      escrowStatus: order['escrowStatus'],
      heldAmount: toDouble(order['heldAmount']),
      storeName: order['storeName'],
      evidenceUrls: (json['evidence'] as List<dynamic>? ?? const [])
          .map((e) => (e as Map)['url'].toString())
          .toList(),
      createdAt: toDate(json['createdAt']),
      resolvedAt: toDate(json['resolvedAt']),
    );
  }

  /// Issue types accepted by POST /api/disputes, with display labels
  static const Map<String, String> issueTypes = {
    'item_not_received': 'Item not received',
    'damaged_item': 'Item arrived damaged',
    'wrong_item': 'Wrong item delivered',
    'missing_items': 'Items missing from order',
    'quality_issue': 'Quality not as described',
    'rider_issue': 'Problem with the rider',
    'customer_issue': 'Problem with the customer',
    'other': 'Something else',
  };

  String get issueLabel => issueTypes[issueType] ?? issueType;

  String get outcomeText {
    if (status == 'open') return 'Under review — payment is on hold';
    if (resolution == 'refund') return 'Resolved — refunded to the customer';
    return 'Resolved — payment released to the store';
  }
}
