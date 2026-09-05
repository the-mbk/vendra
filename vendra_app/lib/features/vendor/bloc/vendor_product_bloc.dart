// ══════════════════════════════════════════════════════════════
// Vendra App - Vendor Product BLoC
// Manages vendor's product CRUD operations
// ══════════════════════════════════════════════════════════════

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';
import '../../../core/models/product_model.dart';
import '../../../core/services/api_service.dart';
import '../../../config/api_config.dart';

// ── Events ──
abstract class VendorProductEvent extends Equatable {
  const VendorProductEvent();
  @override
  List<Object?> get props => [];
}

class FetchVendorProducts extends VendorProductEvent {}

class AddVendorProduct extends VendorProductEvent {
  final String name;
  final String? description;
  final double price;
  final int privateStock;
  final int buffer;
  final String? barcode;
  const AddVendorProduct({required this.name, this.description, required this.price, required this.privateStock, this.buffer = 5, this.barcode});
}

class UpdateVendorProduct extends VendorProductEvent {
  final int id;
  final String? name;
  final String? description;
  final double? price;
  final int? privateStock;
  final int? buffer;
  final String? barcode;
  const UpdateVendorProduct({required this.id, this.name, this.description, this.price, this.privateStock, this.buffer, this.barcode});
}

class DeleteVendorProduct extends VendorProductEvent {
  final int id;
  const DeleteVendorProduct({required this.id});
}

// ── States ──
abstract class VendorProductState extends Equatable {
  const VendorProductState();
  @override
  List<Object?> get props => [];
}

class VendorProductInitial extends VendorProductState {}
class VendorProductLoading extends VendorProductState {}

class VendorProductLoaded extends VendorProductState {
  final List<ProductModel> products;
  const VendorProductLoaded({required this.products});
  @override
  List<Object?> get props => [products.length];
}

class VendorProductActionSuccess extends VendorProductState {
  final String message;
  const VendorProductActionSuccess({required this.message});
}

class VendorProductError extends VendorProductState {
  final String message;
  const VendorProductError({required this.message});
}

// ── BLoC ──
class VendorProductBloc extends Bloc<VendorProductEvent, VendorProductState> {
  final ApiService _api = ApiService();

  VendorProductBloc() : super(VendorProductInitial()) {
    on<FetchVendorProducts>(_onFetch);
    on<AddVendorProduct>(_onAdd);
    on<UpdateVendorProduct>(_onUpdate);
    on<DeleteVendorProduct>(_onDelete);
  }

  Future<void> _onFetch(FetchVendorProducts event, Emitter<VendorProductState> emit) async {
    emit(VendorProductLoading());
    try {
      final response = await _api.get(ApiConfig.vendorProducts);
      if (response.data['success'] == true) {
        final products = (response.data['data'] as List).map((j) => ProductModel.fromJson(j)).toList();
        emit(VendorProductLoaded(products: products));
      } else {
        emit(VendorProductError(message: response.data['message'] ?? 'Failed'));
      }
    } catch (e) {
      emit(VendorProductError(message: ApiService.getErrorMessage(e)));
    }
  }

  Future<void> _onAdd(AddVendorProduct event, Emitter<VendorProductState> emit) async {
    emit(VendorProductLoading());
    try {
      final response = await _api.post(ApiConfig.vendorProducts, data: {
        'name': event.name,
        'description': event.description,
        'price': event.price,
        'private_stock': event.privateStock,
        'buffer': event.buffer,
        'barcode': event.barcode,
      });
      if (response.data['success'] == true) {
        emit(const VendorProductActionSuccess(message: 'Product added successfully!'));
        add(FetchVendorProducts());
      } else {
        emit(VendorProductError(message: response.data['message'] ?? 'Failed'));
      }
    } catch (e) {
      emit(VendorProductError(message: ApiService.getErrorMessage(e)));
    }
  }

  Future<void> _onUpdate(UpdateVendorProduct event, Emitter<VendorProductState> emit) async {
    emit(VendorProductLoading());
    try {
      final data = <String, dynamic>{};
      if (event.name != null) data['name'] = event.name;
      if (event.description != null) data['description'] = event.description;
      if (event.price != null) data['price'] = event.price;
      if (event.privateStock != null) data['private_stock'] = event.privateStock;
      if (event.buffer != null) data['buffer'] = event.buffer;
      if (event.barcode != null) data['barcode'] = event.barcode;

      final response = await _api.put(ApiConfig.vendorProduct(event.id), data: data);
      if (response.data['success'] == true) {
        emit(const VendorProductActionSuccess(message: 'Product updated!'));
        add(FetchVendorProducts());
      } else {
        emit(VendorProductError(message: response.data['message'] ?? 'Failed'));
      }
    } catch (e) {
      emit(VendorProductError(message: ApiService.getErrorMessage(e)));
    }
  }

  Future<void> _onDelete(DeleteVendorProduct event, Emitter<VendorProductState> emit) async {
    try {
      await _api.delete(ApiConfig.vendorProduct(event.id));
      emit(const VendorProductActionSuccess(message: 'Product deleted'));
      add(FetchVendorProducts());
    } catch (e) {
      emit(VendorProductError(message: ApiService.getErrorMessage(e)));
    }
  }
}
