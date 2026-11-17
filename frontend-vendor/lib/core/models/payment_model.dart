// ══════════════════════════════════════════════════════════════
// Vendra App - Card payment & withdrawal models
// Payments (money in):  POST /api/payments/topup | /api/payments/checkout
// Withdrawals (money out): POST /api/withdrawals
// Payout accounts (Payoneer / Stripe): GET /api/payouts/account
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

/// A single-use card token from POST {gatewayUrl}/v1/tokens, or a Stripe
/// PaymentMethod made by Stripe's card field
class CardToken {
  final String id; // tok_… (Vendra Pay) | pm_… (Stripe)
  final CardInfo card;

  const CardToken({required this.id, required this.card});

  factory CardToken.fromJson(Map<String, dynamic> json) => CardToken(
        id: (json['id'] ?? '').toString(),
        card: CardInfo.maybe(json['card']) ?? const CardInfo(brand: 'unknown', last4: ''),
      );
}

/// What the app must do before a payment can finish (3-D Secure):
///   otp         Vendra Pay — send the one-time password to the gateway
///   stripe_sdk  Stripe — run the bank's check with Stripe's SDK using [clientSecret]
class PaymentNextAction {
  final String type; // otp | stripe_sdk
  final int? attemptsLeft;

  /// The sandbox code — only sent by a development backend
  final String? hint;

  /// Stripe only: the PaymentIntent's client secret for handleNextAction
  final String? clientSecret;

  const PaymentNextAction({required this.type, this.attemptsLeft, this.hint, this.clientSecret});

  factory PaymentNextAction.fromJson(Map<String, dynamic> json) => PaymentNextAction(
        type: (json['type'] ?? 'otp').toString(),
        attemptsLeft: toIntOrNull(json['attemptsLeft']),
        hint: json['hint']?.toString(),
        clientSecret: pick(json, 'clientSecret', 'client_secret')?.toString(),
      );

  bool get isStripeSdk => type == 'stripe_sdk';
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

  /// Stripe's 3-D Secure, run with its SDK and the intent's client secret
  bool get needsStripeAction => requiresAction && nextAction?.isStripeSdk == true;

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

/// A payout of wallet money to a card (Vendra Pay), to the user's linked
/// Payoneer account (a Payoneer payout in USD) or to their Stripe payout
/// account (a transfer in the platform's currency)
class WithdrawalModel {
  final int id;
  final double amount;
  final String status; // pending | in_transit | paid | failed
  final String provider; // vendrapay | payoneer | stripe
  final CardInfo? card;

  /// Payoneer: the payee id (vendra-12); Stripe: the connected account (acct_…)
  final String? destinationAccount;

  /// Payoneer / Stripe: what the account received, in [gatewayCurrency] (e.g. 17.86 usd)
  final double? gatewayAmount;
  final String? gatewayCurrency;
  final String? gatewayPayoutId; // po_… | tr_…
  final String? failureMessage;
  final DateTime? createdAt;
  final DateTime? settledAt;

  const WithdrawalModel({
    required this.id,
    required this.amount,
    required this.status,
    this.provider = 'vendrapay',
    this.card,
    this.destinationAccount,
    this.gatewayAmount,
    this.gatewayCurrency,
    this.gatewayPayoutId,
    this.failureMessage,
    this.createdAt,
    this.settledAt,
  });

  factory WithdrawalModel.fromJson(Map<String, dynamic> json) => WithdrawalModel(
        id: toInt(json['id']),
        amount: toDouble(json['amount']),
        status: (json['status'] ?? 'pending').toString(),
        provider: (json['provider'] ?? 'vendrapay').toString(),
        card: CardInfo.maybe(json['card']),
        destinationAccount: json['destinationAccount']?.toString(),
        gatewayAmount: toDoubleOrNull(json['gatewayAmount']),
        gatewayCurrency: json['gatewayCurrency']?.toString(),
        gatewayPayoutId: json['gatewayPayoutId']?.toString(),
        failureMessage: json['failureMessage']?.toString(),
        createdAt: toDate(json['createdAt']),
        settledAt: toDate(json['settledAt']),
      );

  bool get isPaid => status == 'paid';
  bool get isFailed => status == 'failed';
  bool get isOnItsWay => status == 'pending' || status == 'in_transit';

  /// Where it went: card | payoneer | stripe
  PayoutProvider get payoutProvider => PayoutProvider.fromApi(provider);

  /// Paid to a payout account (Payoneer / Stripe) rather than to a card
  bool get toPayoutAccount => payoutProvider.needsAccount;
  bool get toPayoneer => payoutProvider == PayoutProvider.payoneer;
  bool get toStripeAccount => payoutProvider == PayoutProvider.stripe;

  /// "Visa •••• 4242", "your Payoneer account" or "your Stripe account"
  String get cardLabel => toPayoutAccount ? payoutProvider.destination : card?.label ?? 'your card';

  /// What the payout account received, e.g. "$17.86"; null for card payouts
  String? get convertedLabel =>
      gatewayAmount != null && gatewayCurrency != null ? formatForeignAmount(gatewayAmount!, gatewayCurrency!) : null;

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

/// Where withdrawals go, and the wording every payout screen shares
enum PayoutProvider {
  /// Vendra Pay: straight to a debit card, nothing to set up
  card('card'),

  /// The user's own Payoneer account, linked once on Payoneer's page; payouts
  /// are in USD and the user withdraws from Payoneer to their bank
  payoneer('Payoneer'),

  /// The user's Stripe Express account, set up once on Stripe's pages;
  /// transfers are in the platform's currency and Stripe pays their bank
  stripe('Stripe');

  /// "card" | "Payoneer" | "Stripe"
  final String label;

  const PayoutProvider(this.label);

  /// From public-config payments.payoutsTo: card | payoneer | stripe_account
  static PayoutProvider fromPayoutsTo(Object? payoutsTo) {
    switch (payoutsTo) {
      case 'payoneer':
        return PayoutProvider.payoneer;
      case 'stripe_account':
        return PayoutProvider.stripe;
      default:
        return PayoutProvider.card;
    }
  }

  /// From an API provider: GET /api/payouts/account (card | payoneer |
  /// stripe_connect) or a withdrawal (vendrapay | payoneer | stripe)
  static PayoutProvider fromApi(Object? provider) {
    switch (provider) {
      case 'payoneer':
        return PayoutProvider.payoneer;
      case 'stripe':
      case 'stripe_connect':
        return PayoutProvider.stripe;
      default:
        return PayoutProvider.card;
    }
  }

  /// The user needs an account with the provider before withdrawing
  bool get needsAccount => this != PayoutProvider.card;

  /// For wording: "a debit card" | "your Payoneer account" | "your Stripe account"
  String get destination => needsAccount ? 'your $label account' : 'a debit card';

  /// Withdraw button text: "Withdraw to card" | "Withdraw to Payoneer" | "Withdraw to Stripe"
  String get withdrawLabel => 'Withdraw to $label';
}

/// The user's payout account (null until set up): a Payoneer payee or a
/// Stripe Connect Express account
class PayoutAccount {
  final String id; // vendra-12 (Payoneer payee id) | acct_… (Stripe)

  /// Payoneer only: not_registered | pending | active | inactive
  final String? status;
  final bool detailsSubmitted;
  final bool payoutsEnabled;

  const PayoutAccount({required this.id, this.status, this.detailsSubmitted = false, this.payoutsEnabled = false});

  factory PayoutAccount.fromJson(Map<String, dynamic> json) => PayoutAccount(
        id: (json['id'] ?? '').toString(),
        status: json['status']?.toString(),
        detailsSubmitted: json['detailsSubmitted'] == true,
        payoutsEnabled: json['payoutsEnabled'] == true,
      );

  /// "…a1B2" — enough to recognise it without showing the whole id
  String get shortId => id.length > 4 ? '…${id.substring(id.length - 4)}' : id;
}

/// Where the user is in setting up their payout account
enum PayoutAccountState {
  /// Withdrawals go to a card (Vendra Pay): nothing to set up
  notRequired,

  /// No payout account yet
  none,

  /// Setup started on the provider's page but not finished
  /// (Payoneer: not_registered)
  incomplete,

  /// Details sent; the provider is still checking them (Payoneer: pending)
  checking,

  /// Withdrawals can be sent
  ready,
}

/// GET /api/payouts/account → `{ provider, required, account, currency, pkrPerUnit }`
class PayoutAccountStatus {
  final String provider; // payoneer | stripe_connect | card
  final bool required;
  final PayoutAccount? account;

  /// The platform's currency transfers are made in (e.g. usd); null if unknown
  final String? currency;

  /// Rupees per one unit of [currency] (e.g. 280)
  final double pkrPerUnit;

  const PayoutAccountStatus({
    this.provider = 'stripe',
    this.required = true,
    this.account,
    this.currency,
    this.pkrPerUnit = 280,
  });

  factory PayoutAccountStatus.fromJson(Map<String, dynamic> json) => PayoutAccountStatus(
        provider: (json['provider'] ?? 'stripe').toString(),
        required: json['required'] != false,
        account: json['account'] is Map ? PayoutAccount.fromJson(Map<String, dynamic>.from(json['account'] as Map)) : null,
        currency: json['currency']?.toString(),
        pkrPerUnit: toDouble(json['pkrPerUnit'], 280),
      );

  /// Who the account is with (an unknown provider that needs an account reads as Stripe)
  PayoutProvider get payoutProvider {
    final p = PayoutProvider.fromApi(provider);
    return p == PayoutProvider.card && required ? PayoutProvider.stripe : p;
  }

  bool get isPayoneer => payoutProvider == PayoutProvider.payoneer;

  /// "Payoneer" | "Stripe" (| "card" when nothing is needed)
  String get providerName => payoutProvider.label;

  PayoutAccountState get state {
    if (!required) return PayoutAccountState.notRequired;
    final a = account;
    if (a == null) return PayoutAccountState.none;
    if (a.payoutsEnabled) return PayoutAccountState.ready;
    return a.detailsSubmitted ? PayoutAccountState.checking : PayoutAccountState.incomplete;
  }

  bool get isReady => state == PayoutAccountState.ready || state == PayoutAccountState.notRequired;

  /// [rupees] in the platform's currency, rounded like the backend does it
  /// (to the minor unit, at least 1). Null when the currency is unknown.
  double? convert(double rupees) {
    if (currency == null || pkrPerUnit <= 0) return null;
    final minor = (rupees * 100 / pkrPerUnit).round();
    return (minor < 1 ? 1 : minor) / 100;
  }

  /// "≈ $17.86 at Rs 280/USD", or null when the currency is unknown
  String? conversionText(double rupees) {
    final converted = convert(rupees);
    if (converted == null) return null;
    final rate = pkrPerUnit % 1 == 0 ? pkrPerUnit.toStringAsFixed(0) : pkrPerUnit.toStringAsFixed(2);
    return '≈ ${formatForeignAmount(converted, currency!)} at Rs $rate/${currency!.toUpperCase()}';
  }
}

/// "$17.86", "€5.00", "£1.20", or "17.86 AED" for currencies without a symbol here
String formatForeignAmount(double amount, String currency) {
  const symbols = {'usd': r'$', 'eur': '€', 'gbp': '£', 'cad': r'CA$', 'aud': r'A$', 'sgd': r'S$'};
  final value = amount.toStringAsFixed(2);
  final symbol = symbols[currency.toLowerCase()];
  return symbol != null ? '$symbol$value' : '$value ${currency.toUpperCase()}';
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
