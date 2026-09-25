// ══════════════════════════════════════════════════════════════
// Vendra App - Vendor Product BLoC
// Manages vendor's product CRUD operations and keeps the stock
// numbers live: every `stock:vendor` socket event (online order
// reserved/released units, walk-in sale, stock edit) is patched into
// the loaded list in place, so the dashboard, catalog and POS never
// show phantom stock (FR02 / PR01).
// A photo picked on the add/edit screen is uploaded right after the
// product is saved; if only the upload fails the product stays saved and
// the success state carries a `photoError` for the screen to show.
// ══════════════════════════════════════════════════════════════

import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:vendra_vendor/vendra_core.dart';
import '../models/product_photo.dart';

// ── Events ──
abstract class VendorProductEvent extends Equatable {
  const VendorProductEvent();
  @override
  List<Object?> get props => [];
}

class FetchVendorProducts extends VendorProductEvent {
  /// Silent refetches keep the current list on screen (no loading shimmer)
  final bool silent;
  const FetchVendorProducts({this.silent = false});
  @override
  List<Object?> get props => [silent];
}

class AddVendorProduct extends VendorProductEvent {
  final String name;
  final String? description;
  final double price;
  final int privateStock;
  /// null = let the server apply the platform default buffer
  final int? buffer;
  final String? barcode;
  final int? categoryId;
  /// Uploaded after the product is created
  final ProductPhoto? photo;
  const AddVendorProduct({
    required this.name,
    this.description,
    required this.price,
    required this.privateStock,
    this.buffer,
    this.barcode,
    this.categoryId,
    this.photo,
  });
}

class UpdateVendorProduct extends VendorProductEvent {
  final int id;
  final String? name;
  final String? description;
  final double? price;
  final int? privateStock;
  final int? buffer;
  final String? barcode;
  final int? categoryId;
  /// New photo to upload after saving (replaces the current one)
  final ProductPhoto? photo;
  /// Delete the current photo after saving (ignored when [photo] is set)
  final bool removePhoto;
  const UpdateVendorProduct({
    required this.id,
    this.name,
    this.description,
    this.price,
    this.privateStock,
    this.buffer,
    this.barcode,
    this.categoryId,
    this.photo,
    this.removePhoto = false,
  });
}

class DeleteVendorProduct extends VendorProductEvent {
  final int id;
  const DeleteVendorProduct({required this.id});
}

/// Internal: a realtime `stock:vendor` event arrived
class _VendorStockChanged extends VendorProductEvent {
  final VendorStockEvent update;
  const _VendorStockChanged(this.update);
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

  /// Includes the stock numbers so an in-place realtime patch triggers a rebuild
  @override
  List<Object?> get props => products
      .map((p) => '${p.id}:${p.privateStock}:${p.reservedQuantity}:${p.buffer}:${p.publicStock}:'
          '${p.isApproved}:${p.name}:${p.price}:${p.categoryId}:${p.barcode}:${p.imageUrl}')
      .toList();
}

class VendorProductActionSuccess extends VendorProductState {
  final String message;
  /// The product was saved but its photo couldn't be uploaded / removed
  final String? photoError;
  const VendorProductActionSuccess({required this.message, this.photoError});
  @override
  List<Object?> get props => [message, photoError, identityHashCode(this)];
}

class VendorProductError extends VendorProductState {
  final String message;
  /// API error code, e.g. BELOW_RESERVED
  final String? code;
  /// Reserved units reported with BELOW_RESERVED
  final int? reserved;
  const VendorProductError({required this.message, this.code, this.reserved});
  @override
  List<Object?> get props => [message, code, identityHashCode(this)];
}

// ── BLoC ──
class VendorProductBloc extends Bloc<VendorProductEvent, VendorProductState> {
  final ApiService _api = ApiService();
  StreamSubscription<VendorStockEvent>? _stockSub;
  StreamSubscription<void>? _catalogSub;

  List<ProductModel> _products = const [];
  bool _hasLoaded = false;

  /// Last known product list (kept while action/error states are showing)
  List<ProductModel> get products => _products;
  bool get hasLoaded => _hasLoaded;

  ProductModel? productById(int id) {
    for (final p in _products) {
      if (p.id == id) return p;
    }
    return null;
  }

  VendorProductBloc() : super(VendorProductInitial()) {
    on<FetchVendorProducts>(_onFetch);
    on<AddVendorProduct>(_onAdd);
    on<UpdateVendorProduct>(_onUpdate);
    on<DeleteVendorProduct>(_onDelete);
    on<_VendorStockChanged>(_onStockChanged);

    _stockSub = RealtimeService().vendorStock.listen((u) => add(_VendorStockChanged(u)));
    // Admin approved/hid a product → refresh the approval badges
    _catalogSub = RealtimeService().catalogUpdates.listen((_) {
      if (_hasLoaded) add(const FetchVendorProducts(silent: true));
    });
  }

  @override
  Future<void> close() {
    _stockSub?.cancel();
    _catalogSub?.cancel();
    return super.close();
  }

  void _emitLoaded(Emitter<VendorProductState> emit) {
    emit(VendorProductLoaded(products: List.unmodifiable(_products)));
  }

  VendorProductError _errorFrom(Object e) {
    final data = ApiService.getErrorData(e);
    return VendorProductError(
      message: ApiService.getErrorMessage(e),
      code: data?['code'] as String?,
      reserved: toIntOrNull(data?['reserved']),
    );
  }

  /// Shows the error, then puts the last good list back on screen
  void _emitError(Object e, Emitter<VendorProductState> emit) {
    emit(_errorFrom(e));
    if (_hasLoaded) _emitLoaded(emit);
  }

  Future<void> _onFetch(FetchVendorProducts event, Emitter<VendorProductState> emit) async {
    if (!event.silent) {
      // A full (non-silent) load starts clean, e.g. after signing in as another vendor
      _products = const [];
      _hasLoaded = false;
    }
    if (!_hasLoaded) emit(VendorProductLoading());
    try {
      final response = await _api.get(ApiConfig.vendorProducts);
      if (response.data['success'] == true) {
        _products = (response.data['data'] as List)
            .map((j) => ProductModel.fromJson(Map<String, dynamic>.from(j)))
            .toList();
        _hasLoaded = true;
        _emitLoaded(emit);
      } else {
        emit(VendorProductError(message: response.data['message'] ?? 'Failed'));
      }
    } catch (e) {
      if (event.silent && _hasLoaded) return; // keep showing the last good list
      emit(_errorFrom(e));
    }
  }

  void _onStockChanged(_VendorStockChanged event, Emitter<VendorProductState> emit) {
    final u = event.update;
    final index = _products.indexWhere((p) => p.id == u.productId);
    if (index < 0) {
      // A product we don't have yet (e.g. just created on another device)
      if (_hasLoaded) add(const FetchVendorProducts(silent: true));
      return;
    }
    final updated = List<ProductModel>.from(_products);
    updated[index] = updated[index].withStock(
      privateStock: u.privateStock,
      reservedQuantity: u.reservedQuantity,
      buffer: u.buffer,
      publicStock: u.publicStock,
    );
    _products = updated;
    if (state is VendorProductLoaded) _emitLoaded(emit);
  }

  Future<void> _onAdd(AddVendorProduct event, Emitter<VendorProductState> emit) async {
    emit(VendorProductLoading());
    try {
      final response = await _api.post(ApiConfig.vendorProducts, data: {
        'name': event.name,
        'description': event.description,
        'price': event.price,
        'private_stock': event.privateStock,
        if (event.buffer != null) 'buffer': event.buffer,
        'barcode': event.barcode,
        'category_id': event.categoryId,
      });
      if (response.data['success'] == true) {
        final productId = toInt((response.data['data'] as Map)['id']);
        final photoError = event.photo == null ? null : await _uploadPhoto(productId, event.photo!);
        // Server says whether the product still needs admin approval
        emit(VendorProductActionSuccess(
          message: response.data['message'] ?? 'Product added successfully!',
          photoError: photoError,
        ));
        add(const FetchVendorProducts(silent: true));
      } else {
        emit(VendorProductError(message: response.data['message'] ?? 'Failed'));
        if (_hasLoaded) _emitLoaded(emit);
      }
    } catch (e) {
      _emitError(e, emit);
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
      // Always sent so the vendor can also clear the category
      data['category_id'] = event.categoryId;

      final response = await _api.put(ApiConfig.vendorProduct(event.id), data: data);
      if (response.data['success'] == true) {
        String? photoError;
        if (event.photo != null) {
          photoError = await _uploadPhoto(event.id, event.photo!);
        } else if (event.removePhoto) {
          photoError = await _removePhoto(event.id);
        }
        emit(VendorProductActionSuccess(message: 'Product updated!', photoError: photoError));
        add(const FetchVendorProducts(silent: true));
      } else {
        emit(VendorProductError(message: response.data['message'] ?? 'Failed'));
        if (_hasLoaded) _emitLoaded(emit);
      }
    } catch (e) {
      // 409 BELOW_RESERVED: "Stock can't go below N — those units are reserved for online orders."
      _emitError(e, emit);
    }
  }

  /// POST /api/vendor/products/:id/image — returns an error message, or null on success
  Future<String?> _uploadPhoto(int productId, ProductPhoto photo) async {
    try {
      final response = await _api.postMultipart(ApiConfig.vendorProductImage(productId), photo.toFormData());
      if (response.data['success'] == true) {
        _patchProduct(Map<String, dynamic>.from(response.data['data'] as Map));
        return null;
      }
      return response.data['message'] ?? 'Upload failed';
    } catch (e) {
      // e.g. 400 "Each photo must be 5 MB or smaller." / wrong file type
      return ApiService.getErrorMessage(e);
    }
  }

  /// DELETE /api/vendor/products/:id/image — returns an error message, or null on success
  Future<String?> _removePhoto(int productId) async {
    try {
      await _api.delete(ApiConfig.vendorProductImage(productId));
      return null;
    } catch (e) {
      return ApiService.getErrorMessage(e);
    }
  }

  /// Replaces one product with a fresh row from the server (e.g. after a photo upload)
  void _patchProduct(Map<String, dynamic> row) {
    final product = ProductModel.fromJson(row);
    final index = _products.indexWhere((p) => p.id == product.id);
    if (index < 0) return;
    _products = List<ProductModel>.from(_products)..[index] = product;
  }

  Future<void> _onDelete(DeleteVendorProduct event, Emitter<VendorProductState> emit) async {
    try {
      await _api.delete(ApiConfig.vendorProduct(event.id));
      emit(const VendorProductActionSuccess(message: 'Product deleted'));
      add(const FetchVendorProducts(silent: true));
    } catch (e) {
      // 409 while units are reserved for open orders
      _emitError(e, emit);
    }
  }
}
