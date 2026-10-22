// ══════════════════════════════════════════════════════════════
// Vendra App - Wallet Models (GET /api/wallet)
// Every money movement is a ledger row with a type; amounts are always
// positive and the type decides the sign shown to the user.
// ══════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';

import 'json_utils.dart';

class WalletTransaction {
  final int id;
  final int? orderId;

  /// deposit (card, ref pi_…) | opening_balance | escrow_hold | escrow_refund |
  /// escrow_release | rider_payout | withdrawal (ref po_…) | withdrawal_reversal
  final String type;
  final double amount;
  final double balanceAfter;
  final String? description;

  /// Gateway id of the card payment (pi_…) or payout (po_…), when there is one
  final String? reference;
  final DateTime? createdAt;

  WalletTransaction({
    required this.id,
    this.orderId,
    required this.type,
    required this.amount,
    required this.balanceAfter,
    this.description,
    this.reference,
    this.createdAt,
  });

  factory WalletTransaction.fromJson(Map<String, dynamic> json) => WalletTransaction(
        id: toInt(json['id']),
        orderId: toIntOrNull(pick(json, 'orderId', 'order_id')),
        type: (json['type'] ?? '').toString(),
        amount: toDouble(json['amount']),
        balanceAfter: toDouble(pick(json, 'balanceAfter', 'balance_after')),
        description: json['description']?.toString(),
        reference: _blankToNull(json['reference']),
        createdAt: toDate(pick(json, 'createdAt', 'created_at')),
      );

  static String? _blankToNull(dynamic v) {
    final s = v?.toString().trim();
    return s == null || s.isEmpty ? null : s;
  }

  static const _debitTypes = {'escrow_hold', 'withdrawal'};

  /// Money leaving the wallet (shown as negative)
  bool get isDebit => _debitTypes.contains(type);

  /// Signed amount: negative for money leaving the wallet
  double get signedAmount => isDebit ? -amount : amount;

  /// "+ Rs. 500" / "− Rs. 500"
  String get amountText => '${isDebit ? '−' : '+'} ${formatRupees(amount)}';

  String get label {
    switch (type) {
      case 'deposit':
        return 'Card top-up';
      case 'opening_balance':
        return 'Opening balance';
      case 'escrow_hold':
        return 'Paid into escrow';
      case 'escrow_refund':
        return 'Refund';
      case 'escrow_release':
        return 'Payment received';
      case 'rider_payout':
        return 'Delivery earnings';
      case 'withdrawal':
        return 'Withdrawal';
      case 'withdrawal_reversal':
        return 'Withdrawal returned';
      default:
        // Unknown future type: "some_type" → "Some type"
        final words = type.replaceAll('_', ' ').trim();
        return words.isEmpty ? 'Transaction' : words[0].toUpperCase() + words.substring(1);
    }
  }

  /// Label with the order number where it helps ("Refund · Order #12")
  String get title => orderId != null && const {'escrow_hold', 'escrow_refund', 'escrow_release', 'rider_payout'}.contains(type)
      ? '$label · Order #$orderId'
      : label;

  IconData get icon {
    switch (type) {
      case 'deposit':
        return Icons.add_card;
      case 'opening_balance':
        return Icons.account_balance_wallet_outlined;
      case 'escrow_hold':
        return Icons.lock_outline;
      case 'escrow_refund':
        return Icons.replay;
      case 'escrow_release':
        return Icons.storefront_outlined;
      case 'rider_payout':
        return Icons.delivery_dining;
      case 'withdrawal':
        return Icons.north_east;
      case 'withdrawal_reversal':
        return Icons.undo;
      default:
        return Icons.swap_vert;
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
