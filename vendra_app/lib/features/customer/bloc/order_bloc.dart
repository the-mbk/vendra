// ══════════════════════════════════════════════════════════════
// Vendra App - Order BLoC
// ══════════════════════════════════════════════════════════════

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';
import '../../../core/models/order_model.dart';
import '../../../core/models/cart_item_model.dart';
import '../../../core/services/api_service.dart';
import '../../../config/api_config.dart';

abstract class OrderEvent extends Equatable {
  const OrderEvent();
  @override
  List<Object?> get props => [];
}

class CheckoutRequested extends OrderEvent {
  final List<CartItemModel> items;
  final String deliveryType;
  final String? deliveryAddress;
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
  List<Object?> get props => [items.length, deliveryType];
}

class FetchCustomerOrders extends OrderEvent {
  final bool silent;
  const FetchCustomerOrders({this.silent = false});
  @override
  List<Object?> get props => [silent];
}

class CustomerMarkPickedUp extends OrderEvent {
  final int orderId;
  const CustomerMarkPickedUp({required this.orderId});
  @override
  List<Object?> get props => [orderId];
}

class CustomerConfirmDelivered extends OrderEvent {
  final int orderId;
  const CustomerConfirmDelivered({required this.orderId});
  @override
  List<Object?> get props => [orderId];
}

class ClearOrderFeedback extends OrderEvent {}

abstract class OrderState extends Equatable {
  const OrderState();
  @override
  List<Object?> get props => [];
}

class OrderInitial extends OrderState {}

class OrderLoading extends OrderState {}

class OrderPlaced extends OrderState {
  final OrderModel order;
  final double? newWalletBalance;

  const OrderPlaced({required this.order, this.newWalletBalance});

  @override
  List<Object?> get props => [order.id, newWalletBalance];
}

class OrdersLoaded extends OrderState {
  final List<OrderModel> orders;
  final String? feedback;
  final bool feedbackIsError;

  const OrdersLoaded({
    required this.orders,
    this.feedback,
    this.feedbackIsError = false,
  });

  OrdersLoaded copyWithoutFeedback() =>
      OrdersLoaded(orders: orders, feedback: null, feedbackIsError: false);

  @override
  List<Object?> get props => [
        orders.map((o) => '${o.id}:${o.status}:${o.deliveryType}').join('|'),
        feedback,
        feedbackIsError,
      ];
}

class OrderError extends OrderState {
  final String message;
  const OrderError({required this.message});
  @override
  List<Object?> get props => [message];
}

class OrderBloc extends Bloc<OrderEvent, OrderState> {
  final ApiService _api = ApiService();

  OrderBloc() : super(OrderInitial()) {
    on<CheckoutRequested>(_onCheckout);
    on<FetchCustomerOrders>(_onFetchOrders);
    on<CustomerMarkPickedUp>(_onCustomerMarkPickedUp);
    on<CustomerConfirmDelivered>(_onCustomerConfirmDelivered);
    on<ClearOrderFeedback>(_onClearFeedback);
  }

  Future<List<OrderModel>> _loadOrdersList() async {
    final response = await _api.get(ApiConfig.customerOrders);
    if (response.data['success'] != true) {
      throw Exception(response.data['message'] ?? 'Failed to load orders');
    }
    return (response.data['data'] as List).map((json) => OrderModel.fromJson(json)).toList();
  }

  Future<void> _onCheckout(CheckoutRequested event, Emitter<OrderState> emit) async {
    emit(OrderLoading());
    try {
      final response = await _api.post(
        ApiConfig.checkout,
        data: {
          'items': event.items
              .map((item) => {
                    'productId': item.product.id,
                    'quantity': item.quantity,
                  })
              .toList(),
          'deliveryType': event.deliveryType,
          'deliveryAddress': event.deliveryAddress,
          'customerLat': event.customerLat ?? 33.6844,
          'customerLng': event.customerLng ?? 73.0479,
        },
      );

      if (response.data['success'] == true) {
        final data = response.data['data'] as Map<String, dynamic>;
        final order = OrderModel.fromJson(data);
        double? nw;
        final wb = data['walletBalance'];
        if (wb != null) nw = (wb as num).toDouble();
        emit(OrderPlaced(order: order, newWalletBalance: nw));
      } else {
        emit(OrderError(message: response.data['message'] ?? 'Checkout failed'));
      }
    } catch (e) {
      emit(OrderError(message: ApiService.getErrorMessage(e)));
    }
  }

  Future<void> _onFetchOrders(FetchCustomerOrders event, Emitter<OrderState> emit) async {
    if (!event.silent) emit(OrderLoading());
    try {
      final orders = await _loadOrdersList();
      emit(OrdersLoaded(orders: orders));
    } catch (e) {
      emit(OrderError(message: ApiService.getErrorMessage(e)));
    }
  }

  void _onClearFeedback(ClearOrderFeedback event, Emitter<OrderState> emit) {
    final s = state;
    if (s is OrdersLoaded) emit(s.copyWithoutFeedback());
  }

  Future<void> _onCustomerMarkPickedUp(CustomerMarkPickedUp event, Emitter<OrderState> emit) async {
    List<OrderModel>? previous;
    if (state is OrdersLoaded) previous = (state as OrdersLoaded).orders;

    try {
      final response = await _api.post(ApiConfig.customerMarkPickedUp(event.orderId));
      if (response.data['success'] != true) {
        final msg = response.data['message']?.toString() ?? 'Could not update order';
        if (previous != null) {
          emit(OrdersLoaded(orders: previous, feedback: msg, feedbackIsError: true));
        } else {
          emit(OrderError(message: msg));
        }
        return;
      }
      final orders = await _loadOrdersList();
      emit(OrdersLoaded(orders: orders, feedback: 'Marked as picked up.'));
    } catch (e) {
      final msg = ApiService.getErrorMessage(e);
      if (previous != null) {
        emit(OrdersLoaded(orders: previous, feedback: msg, feedbackIsError: true));
      } else {
        emit(OrderError(message: msg));
      }
    }
  }

  Future<void> _onCustomerConfirmDelivered(CustomerConfirmDelivered event, Emitter<OrderState> emit) async {
    List<OrderModel>? previous;
    if (state is OrdersLoaded) previous = (state as OrdersLoaded).orders;

    try {
      final response = await _api.post(ApiConfig.customerConfirmReceived(event.orderId));
      if (response.data['success'] != true) {
        final msg = response.data['message']?.toString() ?? 'Could not complete order';
        if (previous != null) {
          emit(OrdersLoaded(orders: previous, feedback: msg, feedbackIsError: true));
        } else {
          emit(OrderError(message: msg));
        }
        return;
      }
      final orders = await _loadOrdersList();
      emit(OrdersLoaded(orders: orders, feedback: 'Order completed. Vendor has been paid.'));
    } catch (e) {
      final msg = ApiService.getErrorMessage(e);
      if (previous != null) {
        emit(OrdersLoaded(orders: previous, feedback: msg, feedbackIsError: true));
      } else {
        emit(OrderError(message: msg));
      }
    }
  }
}
