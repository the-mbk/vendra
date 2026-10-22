// ══════════════════════════════════════════════════════════════
// Vendra App - Checkout BLoC (FR02 atomic reservation + FR03 escrow hold)
// Wallet: POST /api/customer/checkout.
// Card:   the screen runs the shared CardPaymentFlow against
//         POST /api/payments/checkout (needs sheets/dialogs), then hands the
//         outcome here as CardCheckoutCompleted.
// Kept apart from OrderBloc so a failed checkout never replaces the
// customer's order list. Error codes surfaced to the UI:
//   409 INSUFFICIENT_STOCK   { productId, available } (before any card charge)
//   400 INSUFFICIENT_BALANCE (wallet too low for subtotal + delivery fee)
//   payment.orderError       card charged but the order couldn't be placed
//                            (sold out during the OTP step) → money in wallet
// ══════════════════════════════════════════════════════════════

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:vendra_customer/vendra_core.dart';
import '../../../core/models/cart_item_model.dart';

// ── Events ──
abstract class CheckoutEvent extends Equatable {
  const CheckoutEvent();
  @override
  List<Object?> get props => [];
}

class CheckoutRequested extends CheckoutEvent {
  final List<CartItemModel> items;
  final String deliveryType; // delivery | self_pickup
  final String? deliveryAddress;

  /// Required for delivery: the rider's delivery geofence is checked against this pin
  final double? customerLat;
  final double? customerLng;

  const CheckoutRequested({
    required this.items,
    this.deliveryType = 'delivery',
    this.deliveryAddress,
    this.customerLat,
    this.customerLng,
  });

  /// The /api/customer/checkout body (the card endpoint takes it plus `token`)
  Map<String, dynamic> toBody() => {
        'items': items.map((item) => {'productId': item.product.id, 'quantity': item.quantity}).toList(),
        'deliveryType': deliveryType,
        if (deliveryAddress != null) 'deliveryAddress': deliveryAddress,
        if (customerLat != null && customerLng != null) ...{
          'customerLat': customerLat,
          'customerLng': customerLng,
        },
      };

  @override
  List<Object?> get props => [items.length, deliveryType, customerLat, customerLng];
}

/// The card flow finished (paid, declined, cancelled or refused before charging)
class CardCheckoutCompleted extends CheckoutEvent {
  final CardPaymentOutcome outcome;
  const CardCheckoutCompleted(this.outcome);
  @override
  List<Object?> get props => [identityHashCode(outcome)];
}

// ── States ──
abstract class CheckoutState extends Equatable {
  const CheckoutState();
  @override
  List<Object?> get props => [];
}

class CheckoutIdle extends CheckoutState {}

class CheckoutSubmitting extends CheckoutState {}

class CheckoutSuccess extends CheckoutState {
  final OrderModel order;
  final double? walletBalance;

  /// "Visa •••• 4242" for a card checkout, null for wallet
  final String? paidWith;
  const CheckoutSuccess({required this.order, this.walletBalance, this.paidWith});
  @override
  List<Object?> get props => [order.id, walletBalance, paidWith];
}

/// The card was charged but the order couldn't be placed afterwards
/// (e.g. an item sold out during the OTP step). The money is in the wallet.
class CheckoutPaidNotPlaced extends CheckoutState {
  final String reason;
  final double amount;
  final String cardLabel;
  final double? walletBalance;
  const CheckoutPaidNotPlaced({
    required this.reason,
    required this.amount,
    required this.cardLabel,
    this.walletBalance,
  });
  @override
  List<Object?> get props => [reason, amount, cardLabel, walletBalance];
}

class CheckoutFailure extends CheckoutState {
  final String message;
  final String? code;

  /// For INSUFFICIENT_STOCK: the product that ran short and how many are left
  final int? productId;
  final int? available;

  const CheckoutFailure({required this.message, this.code, this.productId, this.available});

  bool get isStockProblem => code == 'INSUFFICIENT_STOCK';
  bool get isBalanceProblem => code == 'INSUFFICIENT_BALANCE';

  /// The card was charged and the order exists, but it couldn't be loaded
  /// here — the customer should look in My Orders
  bool get isOrderPlacedElsewhere => code == orderPlacedCode;

  static const orderPlacedCode = 'ORDER_PLACED';

  @override
  List<Object?> get props => [message, code, productId, available, identityHashCode(this)];
}

// ── BLoC ──
class CheckoutBloc extends Bloc<CheckoutEvent, CheckoutState> {
  final ApiService _api = ApiService();

  CheckoutBloc() : super(CheckoutIdle()) {
    on<CheckoutRequested>(_onCheckout);
    on<CardCheckoutCompleted>(_onCardCompleted);
  }

  Future<void> _onCheckout(CheckoutRequested event, Emitter<CheckoutState> emit) async {
    emit(CheckoutSubmitting());
    try {
      final response = await _api.post(ApiConfig.checkout, data: event.toBody());

      if (response.data['success'] == true) {
        final data = Map<String, dynamic>.from(response.data['data'] as Map);
        emit(CheckoutSuccess(
          order: OrderModel.fromJson(data),
          walletBalance: toDoubleOrNull(data['walletBalance']),
        ));
      } else {
        emit(CheckoutFailure(message: response.data['message'] ?? 'Checkout failed'));
      }
    } catch (e) {
      final data = ApiService.getErrorData(e);
      emit(CheckoutFailure(
        message: ApiService.getErrorMessage(e),
        code: data?['code'] as String?,
        productId: toIntOrNull(data?['productId']),
        available: toIntOrNull(data?['available']),
      ));
    }
  }

  Future<void> _onCardCompleted(CardCheckoutCompleted event, Emitter<CheckoutState> emit) async {
    final outcome = event.outcome;
    final payment = outcome.payment;

    // Refused before the card was charged (stock, validation, network…)
    if (payment == null) {
      if (outcome.cancelled) {
        emit(CheckoutIdle());
        return;
      }
      final data = outcome.errorData;
      emit(CheckoutFailure(
        message: outcome.message,
        code: outcome.errorCode,
        productId: toIntOrNull(data?['productId']),
        available: toIntOrNull(data?['available']),
      ));
      return;
    }

    // Declined, OTP failed or left unconfirmed: nothing was charged
    if (!payment.isSucceeded) {
      emit(CheckoutFailure(message: outcome.message, code: outcome.cancelled ? 'PAYMENT_NOT_CONFIRMED' : 'CARD_DECLINED'));
      return;
    }

    // Charged, but the order couldn't be placed afterwards → money is in the wallet
    if (payment.orderError != null) {
      emit(CheckoutPaidNotPlaced(
        reason: payment.orderError!,
        amount: payment.amount,
        cardLabel: payment.cardLabel,
        walletBalance: outcome.walletBalance,
      ));
      return;
    }

    emit(CheckoutSubmitting());
    var order = outcome.result?.order;
    // The order may have been placed by the gateway webhook first: load it by id
    if (order == null && payment.orderId != null) {
      try {
        final res = await _api.get(ApiConfig.customerOrder(payment.orderId!));
        order = OrderModel.fromJson(Map<String, dynamic>.from(res.data['data'] as Map));
      } catch (_) {}
    }
    if (order != null) {
      emit(CheckoutSuccess(order: order, walletBalance: outcome.walletBalance, paidWith: payment.cardLabel));
      return;
    }
    emit(CheckoutFailure(
      message: payment.orderId != null
          ? 'Paid with ${payment.cardLabel}. Order #${payment.orderId} was placed — find it in My Orders.'
          : 'Paid with ${payment.cardLabel}. Your order is being placed — check My Orders in a moment.',
      code: CheckoutFailure.orderPlacedCode,
    ));
  }
}
