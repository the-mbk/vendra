// ══════════════════════════════════════════════════════════════
// Vendra App - Dispute BLoCs (FR08)
//   ReportIssueBloc → POST /api/disputes (multipart: orderId, issueType,
//                     description, up to 4 images in "evidence")
//   MyDisputesBloc  → GET /api/disputes/mine
// Opening a dispute freezes the order's escrow until an admin rules.
// ══════════════════════════════════════════════════════════════

import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:vendra_customer/vendra_core.dart';

/// A photo picked for evidence (bytes so it works on mobile, web and desktop)
class EvidencePhoto {
  final String name;
  final Uint8List bytes;
  final String mimeType;

  const EvidencePhoto({required this.name, required this.bytes, required this.mimeType});

  static const int maxBytes = 5 * 1024 * 1024; // server limit per file
  static const int maxCount = 4;

  /// The server accepts JPEG, PNG, WebP and HEIC
  static String mimeFor(String name, [String? reported]) {
    if (reported != null && reported.startsWith('image/')) return reported;
    final lower = name.toLowerCase();
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.webp')) return 'image/webp';
    if (lower.endsWith('.heic') || lower.endsWith('.heif')) return 'image/heic';
    return 'image/jpeg';
  }
}

// ══════════════════════════════════════
// Report an issue
// ══════════════════════════════════════

abstract class ReportIssueEvent extends Equatable {
  const ReportIssueEvent();
  @override
  List<Object?> get props => [];
}

class SubmitDisputeRequested extends ReportIssueEvent {
  final int orderId;
  final String issueType;
  final String description;
  final List<EvidencePhoto> photos;

  const SubmitDisputeRequested({
    required this.orderId,
    required this.issueType,
    required this.description,
    this.photos = const [],
  });

  @override
  List<Object?> get props => [orderId, issueType, description, photos.length];
}

abstract class ReportIssueState extends Equatable {
  const ReportIssueState();
  @override
  List<Object?> get props => [];
}

class ReportIssueIdle extends ReportIssueState {}

class ReportIssueSubmitting extends ReportIssueState {}

class ReportIssueSuccess extends ReportIssueState {
  final DisputeModel dispute;
  final String message;
  const ReportIssueSuccess({required this.dispute, required this.message});
  @override
  List<Object?> get props => [dispute.id];
}

class ReportIssueFailure extends ReportIssueState {
  final String message;
  const ReportIssueFailure({required this.message});
  @override
  List<Object?> get props => [message, identityHashCode(this)];
}

class ReportIssueBloc extends Bloc<ReportIssueEvent, ReportIssueState> {
  final ApiService _api = ApiService();

  ReportIssueBloc() : super(ReportIssueIdle()) {
    on<SubmitDisputeRequested>(_onSubmit);
  }

  Future<void> _onSubmit(SubmitDisputeRequested event, Emitter<ReportIssueState> emit) async {
    emit(ReportIssueSubmitting());
    try {
      final form = FormData();
      form.fields
        ..add(MapEntry('orderId', event.orderId.toString()))
        ..add(MapEntry('issueType', event.issueType))
        ..add(MapEntry('description', event.description.trim()));
      for (final photo in event.photos) {
        form.files.add(MapEntry(
          'evidence',
          MultipartFile.fromBytes(
            photo.bytes,
            filename: photo.name,
            // The server filters by MIME type, so it must be set explicitly
            contentType: DioMediaType.parse(photo.mimeType),
          ),
        ));
      }

      final res = await _api.postMultipart(ApiConfig.disputes, form);
      final dispute = DisputeModel.fromJson(Map<String, dynamic>.from(res.data['data'] as Map));
      emit(ReportIssueSuccess(
        dispute: dispute,
        message: res.data['message']?.toString() ?? 'Dispute submitted.',
      ));
    } catch (e) {
      emit(ReportIssueFailure(message: ApiService.getErrorMessage(e)));
    }
  }
}

// ══════════════════════════════════════
// My disputes
// ══════════════════════════════════════

abstract class MyDisputesEvent extends Equatable {
  const MyDisputesEvent();
  @override
  List<Object?> get props => [];
}

class FetchMyDisputes extends MyDisputesEvent {
  final bool silent;
  const FetchMyDisputes({this.silent = false});
  @override
  List<Object?> get props => [silent];
}

class MyDisputesState extends Equatable {
  final List<DisputeModel> disputes;
  final bool loading;
  final String? error;

  const MyDisputesState({this.disputes = const [], this.loading = false, this.error});

  @override
  List<Object?> get props => [
        disputes.map((d) => '${d.id}:${d.status}:${d.resolution}').join(','),
        loading,
        error,
      ];
}

class MyDisputesBloc extends Bloc<MyDisputesEvent, MyDisputesState> {
  final ApiService _api = ApiService();
  StreamSubscription<OrderUpdateEvent>? _updatesSub;

  MyDisputesBloc() : super(const MyDisputesState(loading: true)) {
    on<FetchMyDisputes>(_onFetch);
    // An admin ruling changes the order's escrow and pushes an order:update
    _updatesSub = RealtimeService().orderUpdates.listen((_) => add(const FetchMyDisputes(silent: true)));
  }

  Future<void> _onFetch(FetchMyDisputes event, Emitter<MyDisputesState> emit) async {
    if (!event.silent) emit(MyDisputesState(disputes: state.disputes, loading: true));
    try {
      final res = await _api.get(ApiConfig.myDisputes);
      final list = (res.data['data'] as List)
          .map((d) => DisputeModel.fromJson(Map<String, dynamic>.from(d)))
          .toList();
      emit(MyDisputesState(disputes: list));
    } catch (e) {
      emit(MyDisputesState(disputes: state.disputes, error: ApiService.getErrorMessage(e)));
    }
  }

  @override
  Future<void> close() {
    _updatesSub?.cancel();
    return super.close();
  }
}
