// ══════════════════════════════════════════════════════════════
// Vendra App - Customer Product BLoC
// Fetches and searches products from marketplace
// ══════════════════════════════════════════════════════════════

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';
import '../../../core/models/product_model.dart';
import '../../../core/services/api_service.dart';
import '../../../config/api_config.dart';

// ── Events ──
abstract class CustomerProductEvent extends Equatable {
  const CustomerProductEvent();
  @override
  List<Object?> get props => [];
}

class FetchProducts extends CustomerProductEvent {
  final String? search;
  final int? vendorId;
  const FetchProducts({this.search, this.vendorId});
  @override
  List<Object?> get props => [search, vendorId];
}

// ── States ──
abstract class CustomerProductState extends Equatable {
  const CustomerProductState();
  @override
  List<Object?> get props => [];
}

class CustomerProductInitial extends CustomerProductState {}
class CustomerProductLoading extends CustomerProductState {}

class CustomerProductLoaded extends CustomerProductState {
  final List<ProductModel> products;
  const CustomerProductLoaded({required this.products});
  @override
  List<Object?> get props => [products.length];
}

class CustomerProductError extends CustomerProductState {
  final String message;
  const CustomerProductError({required this.message});
  @override
  List<Object?> get props => [message];
}

// ── BLoC ──
class CustomerProductBloc extends Bloc<CustomerProductEvent, CustomerProductState> {
  final ApiService _api = ApiService();

  CustomerProductBloc() : super(CustomerProductInitial()) {
    on<FetchProducts>(_onFetch);
  }

  Future<void> _onFetch(FetchProducts event, Emitter<CustomerProductState> emit) async {
    emit(CustomerProductLoading());
    try {
      final queryParams = <String, dynamic>{};
      if (event.search != null && event.search!.isNotEmpty) {
        queryParams['search'] = event.search;
      }
      if (event.vendorId != null) {
        queryParams['vendor_id'] = event.vendorId;
      }

      final response = await _api.get(ApiConfig.products, queryParams: queryParams);

      if (response.data['success'] == true) {
        final products = (response.data['data'] as List)
            .map((json) => ProductModel.fromJson(json))
            .toList();
        emit(CustomerProductLoaded(products: products));
      } else {
        emit(CustomerProductError(message: response.data['message'] ?? 'Failed to load products'));
      }
    } catch (e) {
      emit(CustomerProductError(message: ApiService.getErrorMessage(e)));
    }
  }
}
