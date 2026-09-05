// ══════════════════════════════════════════════════════════════
// Vendra App - Vendor Order BLoC
// Fetches orders, approve/reject pending orders
// ══════════════════════════════════════════════════════════════

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';
import '../../../core/models/order_model.dart';
import '../../../core/services/api_service.dart';
import '../../../config/api_config.dart';

// Events
abstract class VendorOrderEvent extends Equatable {
  const VendorOrderEvent();
  @override
  List<Object?> get props => [];
}

class FetchVendorOrders extends VendorOrderEvent {}

class ApproveVendorOrder extends VendorOrderEvent {
  final int orderId;
  const ApproveVendorOrder({required this.orderId});
  @override
  List<Object?> get props => [orderId];
}

class RejectVendorOrder extends VendorOrderEvent {
  final int orderId;
  const RejectVendorOrder({required this.orderId});
  @override
  List<Object?> get props => [orderId];
}

class MarkOrderPreparing extends VendorOrderEvent {
  final int orderId;
  const MarkOrderPreparing({required this.orderId});
  @override
  List<Object?> get props => [orderId];
}

class MarkOrderReadyForPickup extends VendorOrderEvent {
  final int orderId;
  const MarkOrderReadyForPickup({required this.orderId});
  @override
  List<Object?> get props => [orderId];
}

class DeliverVendorOrder extends VendorOrderEvent {
  final int orderId;
  const DeliverVendorOrder({required this.orderId});
  @override
  List<Object?> get props => [orderId];
}

// States
abstract class VendorOrderState extends Equatable {
  const VendorOrderState();
  @override
  List<Object?> get props => [];
}

class VendorOrderInitial extends VendorOrderState {}
class VendorOrderLoading extends VendorOrderState {}

class VendorOrderLoaded extends VendorOrderState {
  final List<OrderModel> orders;
  const VendorOrderLoaded({required this.orders});
  @override
  List<Object?> get props => orders.map((o) => '${o.id}:${o.status}:${o.deliveryType}').toList();
}

class VendorOrderError extends VendorOrderState {
  final String message;
  const VendorOrderError({required this.message});
}

class VendorOrderActionSuccess extends VendorOrderState {
  final String message;
  const VendorOrderActionSuccess({required this.message});
}

class VendorOrderActionError extends VendorOrderState {
  final String message;
  const VendorOrderActionError({required this.message});
}

// BLoC
class VendorOrderBloc extends Bloc<VendorOrderEvent, VendorOrderState> {
  final ApiService _api = ApiService();

  VendorOrderBloc() : super(VendorOrderInitial()) {
    on<FetchVendorOrders>(_onFetch);
    on<ApproveVendorOrder>(_onApprove);
    on<RejectVendorOrder>(_onReject);
    on<MarkOrderPreparing>(_onPrepare);
    on<MarkOrderReadyForPickup>(_onReadyPickup);
    on<DeliverVendorOrder>(_onDeliver);
  }

  Future<void> _onFetch(FetchVendorOrders event, Emitter<VendorOrderState> emit) async {
    emit(VendorOrderLoading());
    try {
      final response = await _api.get(ApiConfig.vendorOrders);
      if (response.data['success'] == true) {
        final orders = (response.data['data'] as List).map((j) => OrderModel.fromJson(j)).toList();
        emit(VendorOrderLoaded(orders: orders));
      } else {
        emit(VendorOrderError(message: response.data['message'] ?? 'Failed'));
      }
    } catch (e) {
      emit(VendorOrderError(message: ApiService.getErrorMessage(e)));
    }
  }

  Future<void> _onApprove(ApproveVendorOrder event, Emitter<VendorOrderState> emit) async {
    try {
      final response = await _api.put(ApiConfig.approveOrder(event.orderId));
      if (response.data['success'] == true) {
        emit(const VendorOrderActionSuccess(message: 'Order approved! ✅'));
      } else {
        emit(VendorOrderActionError(message: response.data['message'] ?? 'Failed to approve'));
      }
    } catch (e) {
      emit(VendorOrderActionError(message: ApiService.getErrorMessage(e)));
    }
  }

  Future<void> _onReject(RejectVendorOrder event, Emitter<VendorOrderState> emit) async {
    try {
      final response = await _api.put(ApiConfig.rejectOrder(event.orderId));
      if (response.data['success'] == true) {
        emit(const VendorOrderActionSuccess(message: 'Order rejected. Stock released.'));
      } else {
        emit(VendorOrderActionError(message: response.data['message'] ?? 'Failed to reject'));
      }
    } catch (e) {
      emit(VendorOrderActionError(message: ApiService.getErrorMessage(e)));
    }
  }

  Future<void> _onPrepare(MarkOrderPreparing event, Emitter<VendorOrderState> emit) async {
    try {
      final response = await _api.put(ApiConfig.prepareOrder(event.orderId));
      if (response.data['success'] == true) {
        emit(const VendorOrderActionSuccess(message: 'Marked as preparing.'));
      } else {
        emit(VendorOrderActionError(message: response.data['message'] ?? 'Failed to update order'));
      }
    } catch (e) {
      emit(VendorOrderActionError(message: ApiService.getErrorMessage(e)));
    }
  }

  Future<void> _onReadyPickup(MarkOrderReadyForPickup event, Emitter<VendorOrderState> emit) async {
    try {
      final response = await _api.put(ApiConfig.readyForPickupOrder(event.orderId));
      if (response.data['success'] == true) {
        emit(const VendorOrderActionSuccess(message: 'Marked ready for pickup. Customer will confirm collection.'));
      } else {
        emit(VendorOrderActionError(message: response.data['message'] ?? 'Failed to update order'));
      }
    } catch (e) {
      emit(VendorOrderActionError(message: ApiService.getErrorMessage(e)));
    }
  }

  Future<void> _onDeliver(DeliverVendorOrder event, Emitter<VendorOrderState> emit) async {
    try {
      final response = await _api.put(ApiConfig.deliverOrder(event.orderId));
      if (response.data['success'] == true) {
        emit(const VendorOrderActionSuccess(message: 'Marked delivered. Funds released to your wallet.'));
      } else {
        emit(VendorOrderActionError(message: response.data['message'] ?? 'Failed to update order'));
      }
    } catch (e) {
      emit(VendorOrderActionError(message: ApiService.getErrorMessage(e)));
    }
  }
}
