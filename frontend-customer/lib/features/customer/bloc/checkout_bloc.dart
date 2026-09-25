// ══════════════════════════════════════════════════════════════
// Vendra App - Checkout BLoC (FR02 atomic reservation + FR03 escrow hold)
// POST /api/customer/checkout. Kept apart from OrderBloc so a failed
// checkout never replaces the customer's order list.
// Error codes surfaced to the UI:
//   409 INSUFFICIENT_STOCK   { productId, available }
//   400 INSUFFICIENT_BALANCE (wallet too low for subtotal + delivery fee)
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

  @override
  List<Object?> get props => [items.length, deliveryType, customerLat, customerLng];
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
  const CheckoutSuccess({required this.order, this.walletBalance});
  @override
  List<Object?> get props => [order.id, walletBalance];
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

  @override
  List<Object?> get props => [message, code, productId, available, identityHashCode(this)];
}

// ── BLoC ──
class CheckoutBloc extends Bloc<CheckoutEvent, CheckoutState> {
  final ApiService _api = ApiService();

  CheckoutBloc() : super(CheckoutIdle()) {
    on<CheckoutRequested>(_onCheckout);
  }

  Future<void> _onCheckout(CheckoutRequested event, Emitter<CheckoutState> emit) async {
    emit(CheckoutSubmitting());
    try {
      final response = await _api.post(
        ApiConfig.checkout,
        data: {
          'items': event.items
              .map((item) => {'productId': item.product.id, 'quantity': item.quantity})
              .toList(),
          'deliveryType': event.deliveryType,
          if (event.deliveryAddress != null) 'deliveryAddress': event.deliveryAddress,
          if (event.customerLat != null && event.customerLng != null) ...{
            'customerLat': event.customerLat,
            'customerLng': event.customerLng,
          },
        },
      );

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
}
