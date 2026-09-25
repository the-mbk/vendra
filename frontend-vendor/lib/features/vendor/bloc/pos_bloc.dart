// ══════════════════════════════════════════════════════════════
// Vendra Vendor App - Walk-in POS BLoC (FR01 / FR02)
// Holds the sale being rung up at the counter, looks up scanned
// barcodes, completes the sale and tracks today's walk-in totals.
//
// The server is the authority on stock: a cashier may sell the
// buffer but never units reserved for online orders
// (sellable = private − reserved). If the sale asks for more, the
// API answers 409 RESERVED_STOCK and the message is shown as-is.
// ══════════════════════════════════════════════════════════════

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:vendra_vendor/vendra_core.dart';

import '../models/pos_sale_model.dart';

// ── Events ──
abstract class PosEvent extends Equatable {
  const PosEvent();
  @override
  List<Object?> get props => [];
}

/// POS screen opened: clear any old sale and load today's totals
class PosStarted extends PosEvent {}

class PosLoadToday extends PosEvent {}

class PosAddProduct extends PosEvent {
  final ProductModel product;
  const PosAddProduct(this.product);
  @override
  List<Object?> get props => [product.id];
}

/// Sets a line's quantity; 0 removes the line
class PosSetQuantity extends PosEvent {
  final int productId;
  final int quantity;
  const PosSetQuantity(this.productId, this.quantity);
  @override
  List<Object?> get props => [productId, quantity];
}

class PosClearSale extends PosEvent {}

/// A barcode was scanned with the camera or typed/entered by a USB scanner
class PosBarcodeSubmitted extends PosEvent {
  final String code;
  const PosBarcodeSubmitted(this.code);
  @override
  List<Object?> get props => [code];
}

class PosCompleteSale extends PosEvent {}

class PosReceiptDismissed extends PosEvent {}

// ── State ──
class PosNotice {
  final int id; // increments so identical messages still reach the listener
  final String message;
  final bool isError;
  final String? code; // e.g. RESERVED_STOCK
  final int? productId;
  final int? sellable;
  final int? reserved;

  const PosNotice({
    required this.id,
    required this.message,
    this.isError = false,
    this.code,
    this.productId,
    this.sellable,
    this.reserved,
  });
}

class PosState extends Equatable {
  final List<PosLine> lines;
  final int todayCount;
  final double todayTotal;
  final List<PosSale> todaySales;
  final bool isLoadingToday;
  final bool isSubmitting;
  final bool isLookingUp;
  final PosSale? receipt; // last completed sale, shown until dismissed
  final PosNotice? notice;

  const PosState({
    this.lines = const [],
    this.todayCount = 0,
    this.todayTotal = 0,
    this.todaySales = const [],
    this.isLoadingToday = false,
    this.isSubmitting = false,
    this.isLookingUp = false,
    this.receipt,
    this.notice,
  });

  double get total => lines.fold(0.0, (sum, l) => sum + l.total);
  int get unitCount => lines.fold(0, (sum, l) => sum + l.quantity);
  bool get isEmpty => lines.isEmpty;

  int quantityOf(int productId) {
    for (final l in lines) {
      if (l.productId == productId) return l.quantity;
    }
    return 0;
  }

  PosState copyWith({
    List<PosLine>? lines,
    int? todayCount,
    double? todayTotal,
    List<PosSale>? todaySales,
    bool? isLoadingToday,
    bool? isSubmitting,
    bool? isLookingUp,
    PosSale? receipt,
    bool clearReceipt = false,
    PosNotice? notice,
  }) {
    return PosState(
      lines: lines ?? this.lines,
      todayCount: todayCount ?? this.todayCount,
      todayTotal: todayTotal ?? this.todayTotal,
      todaySales: todaySales ?? this.todaySales,
      isLoadingToday: isLoadingToday ?? this.isLoadingToday,
      isSubmitting: isSubmitting ?? this.isSubmitting,
      isLookingUp: isLookingUp ?? this.isLookingUp,
      receipt: clearReceipt ? null : (receipt ?? this.receipt),
      notice: notice ?? this.notice,
    );
  }

  @override
  List<Object?> get props => [
        lines.map((l) => '${l.productId}x${l.quantity}').join(','),
        todayCount,
        todayTotal,
        todaySales.length,
        isLoadingToday,
        isSubmitting,
        isLookingUp,
        receipt?.id,
        notice?.id,
      ];
}

// ── BLoC ──
class PosBloc extends Bloc<PosEvent, PosState> {
  final ApiService _api = ApiService();
  int _noticeId = 0;

  PosBloc() : super(const PosState()) {
    on<PosStarted>(_onStarted);
    on<PosLoadToday>(_onLoadToday);
    on<PosAddProduct>(_onAdd);
    on<PosSetQuantity>(_onSetQuantity);
    on<PosClearSale>((_, emit) => emit(state.copyWith(lines: const [])));
    on<PosBarcodeSubmitted>(_onBarcode);
    on<PosCompleteSale>(_onComplete);
    on<PosReceiptDismissed>((_, emit) => emit(state.copyWith(clearReceipt: true)));
  }

  PosNotice _notice(String message, {bool isError = false, Map<String, dynamic>? data}) => PosNotice(
        id: ++_noticeId,
        message: message,
        isError: isError,
        code: data?['code'] as String?,
        productId: toIntOrNull(data?['productId']),
        sellable: toIntOrNull(data?['sellable']),
        reserved: toIntOrNull(data?['reserved']),
      );

  Future<void> _onStarted(PosStarted event, Emitter<PosState> emit) async {
    emit(const PosState());
    add(PosLoadToday());
  }

  Future<void> _onLoadToday(PosLoadToday event, Emitter<PosState> emit) async {
    emit(state.copyWith(isLoadingToday: true));
    try {
      final res = await _api.get(ApiConfig.posSales);
      final data = Map<String, dynamic>.from(res.data['data'] as Map);
      emit(state.copyWith(
        isLoadingToday: false,
        todayCount: toInt(data['today_count']),
        todayTotal: toDouble(data['today_total']),
        todaySales: (data['sales'] as List<dynamic>? ?? const [])
            .map((s) => PosSale.fromJson(Map<String, dynamic>.from(s)))
            .toList(),
      ));
    } catch (e) {
      emit(state.copyWith(isLoadingToday: false));
    }
  }

  void _addLine(ProductModel p, Emitter<PosState> emit, {PosNotice? notice}) {
    final lines = List<PosLine>.from(state.lines);
    final i = lines.indexWhere((l) => l.productId == p.id);
    if (i >= 0) {
      lines[i] = lines[i].withQuantity(lines[i].quantity + 1);
    } else {
      lines.add(PosLine(productId: p.id, name: p.name, unitPrice: p.price, quantity: 1));
    }
    // A new sale replaces the previous receipt
    emit(state.copyWith(lines: lines, clearReceipt: true, notice: notice));
  }

  void _onAdd(PosAddProduct event, Emitter<PosState> emit) => _addLine(event.product, emit);

  void _onSetQuantity(PosSetQuantity event, Emitter<PosState> emit) {
    final lines = List<PosLine>.from(state.lines);
    final i = lines.indexWhere((l) => l.productId == event.productId);
    if (i < 0) return;
    if (event.quantity <= 0) {
      lines.removeAt(i);
    } else {
      lines[i] = lines[i].withQuantity(event.quantity);
    }
    emit(state.copyWith(lines: lines));
  }

  Future<void> _onBarcode(PosBarcodeSubmitted event, Emitter<PosState> emit) async {
    final code = event.code.trim();
    if (code.isEmpty) return;
    emit(state.copyWith(isLookingUp: true));
    try {
      final res = await _api.get(ApiConfig.vendorProductByBarcode(code));
      final product = ProductModel.fromJson(Map<String, dynamic>.from(res.data['data'] as Map));
      emit(state.copyWith(isLookingUp: false));
      _addLine(product, emit, notice: _notice('Added ${product.name}'));
    } catch (e) {
      // 404: "No product with barcode … in your store."
      emit(state.copyWith(isLookingUp: false, notice: _notice(ApiService.getErrorMessage(e), isError: true)));
    }
  }

  Future<void> _onComplete(PosCompleteSale event, Emitter<PosState> emit) async {
    if (state.lines.isEmpty || state.isSubmitting) return;
    emit(state.copyWith(isSubmitting: true));
    try {
      final res = await _api.post(ApiConfig.posSales, data: {
        'items': state.lines.map((l) => {'productId': l.productId, 'quantity': l.quantity}).toList(),
      });
      final sale = PosSale.fromJson(Map<String, dynamic>.from(res.data['data'] as Map));
      emit(state.copyWith(
        isSubmitting: false,
        lines: const [],
        receipt: sale,
        todayCount: state.todayCount + 1,
        todayTotal: state.todayTotal + sale.totalAmount,
        notice: _notice(res.data['message'] ?? 'Sale #${sale.id} completed.'),
      ));
      add(PosLoadToday()); // authoritative totals from the server
    } catch (e) {
      // 409 RESERVED_STOCK: 'Only 3 "X" can be sold — 2 are reserved for online orders.'
      emit(state.copyWith(
        isSubmitting: false,
        notice: _notice(ApiService.getErrorMessage(e), isError: true, data: ApiService.getErrorData(e)),
      ));
    }
  }
}
