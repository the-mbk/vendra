// ══════════════════════════════════════════════════════════════
// Vendra App - Card payment & withdrawal models
// Payments (money in):  POST /api/payments/topup | /api/payments/checkout
// Withdrawals (money out): POST /api/withdrawals
// Gateway objects: card tokens and the sandbox test-card list.
// ══════════════════════════════════════════════════════════════

import '../utils/card_utils.dart';
import 'json_utils.dart';
import 'order_model.dart';

/// The non-sensitive card summary the API and gateway return
class CardInfo {
  final String brand;
  final String last4;
  final String? funding; // credit | debit (gateway responses only)
  final int? expMonth;
  final int? expYear;

  const CardInfo({required this.brand, required this.last4, this.funding, this.expMonth, this.expYear});

  factory CardInfo.fromJson(Map<String, dynamic> json) => CardInfo(
        brand: (json['brand'] ?? 'unknown').toString(),
        last4: (json['last4'] ?? '').toString(),
        funding: json['funding']?.toString(),
        expMonth: toIntOrNull(pick(json, 'expMonth', 'exp_month')),
        expYear: toIntOrNull(pick(json, 'expYear', 'exp_year')),
      );

  static CardInfo? maybe(dynamic json) =>
      json is Map ? CardInfo.fromJson(Map<String, dynamic>.from(json)) : null;

  String get brandLabel => CardUtils.brandLabel(brand);

  /// "Visa •••• 4242"
  String get label => CardUtils.maskedLabel(brand, last4);
}

/// A single-use card token from POST {gatewayUrl}/v1/tokens
class CardToken {
  final String id; // tok_…
  final CardInfo card;

  const CardToken({required this.id, required this.card});

  factory CardToken.fromJson(Map<String, dynamic> json) => CardToken(
        id: (json['id'] ?? '').toString(),
        card: CardInfo.maybe(json['card']) ?? const CardInfo(brand: 'unknown', last4: ''),
      );
}

/// What the app must do before a payment can finish (3-D Secure one-time password)
class PaymentNextAction {
  final String type; // otp
  final int? attemptsLeft;

  /// The sandbox code — only sent by a development backend
  final String? hint;

  const PaymentNextAction({required this.type, this.attemptsLeft, this.hint});

  factory PaymentNextAction.fromJson(Map<String, dynamic> json) => PaymentNextAction(
        type: (json['type'] ?? 'otp').toString(),
        attemptsLeft: toIntOrNull(json['attemptsLeft']),
        hint: json['hint']?.toString(),
      );
}

/// A card payment (top-up or card checkout)
class PaymentModel {
  final int id;
  final String purpose; // topup | checkout
  final double amount;
  final String status; // processing | requires_action | succeeded | failed | canceled
  final CardInfo? card;
  final String? gatewayIntentId; // pi_…
  final PaymentNextAction? nextAction;
  final String? failureMessage;
  final int? orderId;

  /// Card checkout only: why the order couldn't be placed after the card was
  /// charged (e.g. sold out during the OTP step). The money is then in the wallet.
  final String? orderError;
  final DateTime? createdAt;

  const PaymentModel({
    required this.id,
    required this.purpose,
    required this.amount,
    required this.status,
    this.card,
    this.gatewayIntentId,
    this.nextAction,
    this.failureMessage,
    this.orderId,
    this.orderError,
    this.createdAt,
  });

  factory PaymentModel.fromJson(Map<String, dynamic> json) => PaymentModel(
        id: toInt(json['id']),
        purpose: (json['purpose'] ?? 'topup').toString(),
        amount: toDouble(json['amount']),
        status: (json['status'] ?? 'processing').toString(),
        card: CardInfo.maybe(json['card']),
        gatewayIntentId: json['gatewayIntentId']?.toString(),
        nextAction: json['nextAction'] is Map
            ? PaymentNextAction.fromJson(Map<String, dynamic>.from(json['nextAction'] as Map))
            : null,
        failureMessage: json['failureMessage']?.toString(),
        orderId: toIntOrNull(json['orderId']),
        orderError: json['orderError']?.toString(),
        createdAt: toDate(json['createdAt']),
      );

  bool get isSucceeded => status == 'succeeded';
  bool get requiresAction => status == 'requires_action';
  bool get isFailed => status == 'failed' || status == 'canceled';
  bool get isProcessing => status == 'processing';

  bool get needsOtp => requiresAction && (nextAction?.type ?? 'otp') == 'otp';

  /// "Visa •••• 4242", or "card" if the gateway never saw one
  String get cardLabel => card?.label ?? 'card';

  String get statusLabel {
    switch (status) {
      case 'succeeded':
        return 'Paid';
      case 'requires_action':
        return 'Waiting for code';
      case 'processing':
        return 'Processing';
      case 'failed':
        return 'Failed';
      case 'canceled':
        return 'Cancelled';
      default:
        return status;
    }
  }
}

/// `{ payment, order, walletBalance }` from the payment endpoints (also the
/// body of a 402 decline)
class PaymentResult {
  final PaymentModel payment;
  final OrderModel? order;
  final double? walletBalance;

  const PaymentResult({required this.payment, this.order, this.walletBalance});

  factory PaymentResult.fromJson(Map<String, dynamic> json) => PaymentResult(
        payment: PaymentModel.fromJson(Map<String, dynamic>.from(json['payment'] as Map)),
        order: json['order'] is Map ? OrderModel.fromJson(Map<String, dynamic>.from(json['order'] as Map)) : null,
        walletBalance: toDoubleOrNull(json['walletBalance']),
      );

  /// Reads the result from a full response body, or null if it has none
  static PaymentResult? fromBody(dynamic body) {
    if (body is Map && body['data'] is Map && (body['data'] as Map)['payment'] is Map) {
      return PaymentResult.fromJson(Map<String, dynamic>.from(body['data'] as Map));
    }
    return null;
  }
}

/// A payout of wallet money to a card
class WithdrawalModel {
  final int id;
  final double amount;
  final String status; // pending | in_transit | paid | failed
  final CardInfo? card;
  final String? gatewayPayoutId; // po_…
  final String? failureMessage;
  final DateTime? createdAt;
  final DateTime? settledAt;

  const WithdrawalModel({
    required this.id,
    required this.amount,
    required this.status,
    this.card,
    this.gatewayPayoutId,
    this.failureMessage,
    this.createdAt,
    this.settledAt,
  });

  factory WithdrawalModel.fromJson(Map<String, dynamic> json) => WithdrawalModel(
        id: toInt(json['id']),
        amount: toDouble(json['amount']),
        status: (json['status'] ?? 'pending').toString(),
        card: CardInfo.maybe(json['card']),
        gatewayPayoutId: json['gatewayPayoutId']?.toString(),
        failureMessage: json['failureMessage']?.toString(),
        createdAt: toDate(json['createdAt']),
        settledAt: toDate(json['settledAt']),
      );

  bool get isPaid => status == 'paid';
  bool get isFailed => status == 'failed';
  bool get isOnItsWay => status == 'pending' || status == 'in_transit';

  String get cardLabel => card?.label ?? 'your card';

  String get statusLabel {
    switch (status) {
      case 'pending':
      case 'in_transit':
        return 'In transit';
      case 'paid':
        return 'Paid';
      case 'failed':
        return 'Returned';
      default:
        return status;
    }
  }
}

/// `{ withdrawal, walletBalance }` from POST /api/withdrawals
class WithdrawalResult {
  final WithdrawalModel withdrawal;
  final double? walletBalance;

  const WithdrawalResult({required this.withdrawal, this.walletBalance});

  factory WithdrawalResult.fromJson(Map<String, dynamic> json) => WithdrawalResult(
        withdrawal: WithdrawalModel.fromJson(Map<String, dynamic>.from(json['withdrawal'] as Map)),
        walletBalance: toDoubleOrNull(json['walletBalance']),
      );
}

/// One sandbox card from GET {gatewayUrl}/v1/test-cards
class TestCard {
  final String number;
  final String brand;
  final String funding;

  /// What happens with this card, e.g. "Asks for a one-time password"
  final String label;

  const TestCard({required this.number, required this.brand, required this.funding, required this.label});

  factory TestCard.fromJson(Map<String, dynamic> json) => TestCard(
        number: CardUtils.digitsOnly((json['number'] ?? '').toString()),
        brand: (json['brand'] ?? 'unknown').toString(),
        funding: (json['funding'] ?? 'credit').toString(),
        label: (json['label'] ?? '').toString(),
      );

  String get last4 => number.length >= 4 ? number.substring(number.length - 4) : number;
  String get formattedNumber => CardUtils.formatNumber(number);
  bool get isDebit => funding == 'debit';

  /// Payouts only make sense to these (declining cards bounce on purpose)
  bool get mentionsPayouts => label.toLowerCase().contains('payout');
}

/// The test-card list plus the sandbox one-time password
class TestCardList {
  final String? otp;
  final List<TestCard> cards;

  const TestCardList({this.otp, this.cards = const []});

  factory TestCardList.fromJson(Map<String, dynamic> json) => TestCardList(
        otp: json['otp']?.toString(),
        cards: (json['data'] as List<dynamic>? ?? const [])
            .whereType<Map>()
            .map((c) => TestCard.fromJson(Map<String, dynamic>.from(c)))
            .toList(),
      );
}
