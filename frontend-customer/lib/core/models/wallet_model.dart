// ══════════════════════════════════════════════════════════════
// Vendra App - Wallet Models (GET /api/wallet)
// ══════════════════════════════════════════════════════════════

import 'json_utils.dart';

class WalletTransaction {
  final int id;
  final int? orderId;
  final String type; // deposit | escrow_hold | escrow_refund | escrow_release | rider_payout
  final double amount;
  final double balanceAfter;
  final String? description;
  final DateTime? createdAt;

  WalletTransaction({
    required this.id,
    this.orderId,
    required this.type,
    required this.amount,
    required this.balanceAfter,
    this.description,
    this.createdAt,
  });

  factory WalletTransaction.fromJson(Map<String, dynamic> json) => WalletTransaction(
        id: toInt(json['id']),
        orderId: toIntOrNull(json['orderId']),
        type: json['type'] ?? '',
        amount: toDouble(json['amount']),
        balanceAfter: toDouble(json['balanceAfter']),
        description: json['description'],
        createdAt: toDate(json['createdAt']),
      );

  /// Money leaving the wallet (shown as negative)
  bool get isDebit => type == 'escrow_hold' || type == 'withdrawal';

  String get label {
    switch (type) {
      case 'deposit': return 'Top-up';
      case 'escrow_hold': return 'Held in escrow';
      case 'escrow_refund': return 'Refund';
      case 'escrow_release': return 'Payment received';
      case 'rider_payout': return 'Delivery earnings';
      default: return type;
    }
  }
}

class WalletSummary {
  final double balance;
  final List<WalletTransaction> transactions;

  WalletSummary({required this.balance, required this.transactions});

  factory WalletSummary.fromJson(Map<String, dynamic> json) => WalletSummary(
        balance: toDouble(json['balance']),
        transactions: (json['transactions'] as List<dynamic>? ?? const [])
            .map((t) => WalletTransaction.fromJson(Map<String, dynamic>.from(t)))
            .toList(),
      );
}
