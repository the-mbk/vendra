// ══════════════════════════════════════════════════════════════
// Vendra App - Category BLoC (FR06)
// Loads the admin-managed categories from GET /api/categories
// ══════════════════════════════════════════════════════════════

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:vendra_customer/vendra_core.dart';

// ── Events ──
abstract class CategoryEvent extends Equatable {
  const CategoryEvent();
  @override
  List<Object?> get props => [];
}

class FetchCategories extends CategoryEvent {
  const FetchCategories();
}

// ── State ──
class CategoryState extends Equatable {
  final List<CategoryModel> categories;
  final bool loading;
  final String? error;

  const CategoryState({this.categories = const [], this.loading = false, this.error});

  @override
  List<Object?> get props => [categories.map((c) => '${c.id}:${c.name}').join(','), loading, error];
}

// ── BLoC ──
class CategoryBloc extends Bloc<CategoryEvent, CategoryState> {
  final ApiService _api = ApiService();

  CategoryBloc() : super(const CategoryState()) {
    on<FetchCategories>(_onFetch);
  }

  Future<void> _onFetch(FetchCategories event, Emitter<CategoryState> emit) async {
    emit(CategoryState(categories: state.categories, loading: true));
    try {
      final res = await _api.get(ApiConfig.categories);
      final list = (res.data['data'] as List)
          .map((c) => CategoryModel.fromJson(Map<String, dynamic>.from(c)))
          .toList();
      emit(CategoryState(categories: list));
    } catch (e) {
      emit(CategoryState(categories: state.categories, error: ApiService.getErrorMessage(e)));
    }
  }
}
