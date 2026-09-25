// ══════════════════════════════════════════════════════════════
// Vendra Rider App - Auth BLoC (FR05)
// Login / signup / auto-login / logout for rider accounts.
// Also starts notifications after sign-in and tears everything
// down (location tracking, socket, inbox) on logout.
// ══════════════════════════════════════════════════════════════

import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:vendra_rider/vendra_core.dart';

import '../../rider/services/rider_location_service.dart';
import 'auth_event.dart';
import 'auth_state.dart';

class AuthBloc extends Bloc<AuthEvent, AuthState> {
  final ApiService _api = ApiService();

  AuthBloc() : super(AuthInitial()) {
    on<CheckAuthRequested>(_onCheckAuth);
    on<LoginRequested>(_onLogin);
    on<SignupRequested>(_onSignup);
    on<LogoutRequested>(_onLogout);
    on<SessionExpired>(_onSessionExpired);
    on<AuthWalletBalanceUpdated>(_onWalletBalanceUpdated);
  }

  void _onWalletBalanceUpdated(AuthWalletBalanceUpdated event, Emitter<AuthState> emit) {
    final state = this.state;
    if (state is Authenticated) {
      emit(Authenticated(user: state.user.copyWith(walletBalance: event.walletBalance), token: state.token));
    }
  }

  /// Validate a stored token via /api/auth/me
  Future<void> _onCheckAuth(CheckAuthRequested event, Emitter<AuthState> emit) async {
    try {
      if (!await StorageService.hasToken()) {
        emit(const Unauthenticated());
        return;
      }
      final response = await _api.get(ApiConfig.me);
      if (response.data['success'] == true) {
        final user = UserModel.fromJson(response.data['data']);
        if (!user.isRider) {
          // Another role's account was signed in on this device — this app is for riders only.
          await StorageService.clearAll();
          emit(const Unauthenticated());
          return;
        }
        final token = (await StorageService.getToken())!;
        _onSignedIn();
        emit(Authenticated(user: user, token: token));
      } else {
        await StorageService.clearAll();
        emit(const Unauthenticated());
      }
    } catch (e) {
      await StorageService.clearAll();
      emit(const Unauthenticated());
    }
  }

  Future<void> _onLogin(LoginRequested event, Emitter<AuthState> emit) async {
    emit(AuthLoading());
    try {
      final response = await _api.post(
        ApiConfig.login,
        data: {'email': event.email, 'password': event.password, 'role': 'rider'},
      );
      await _handleAuthResponse(response.data, emit, 'Login failed');
    } catch (e) {
      // 403 WRONG_APP carries a message like "This is a vendor account…"
      emit(AuthError(message: ApiService.getErrorMessage(e)));
    }
  }

  Future<void> _onSignup(SignupRequested event, Emitter<AuthState> emit) async {
    emit(AuthLoading());
    try {
      final response = await _api.post(
        ApiConfig.signup,
        data: {
          'fullName': event.fullName,
          'email': event.email,
          'password': event.password,
          'phone': event.phone,
          'role': 'rider',
          'vehicleType': event.vehicleType,
        },
      );
      await _handleAuthResponse(response.data, emit, 'Sign-up failed');
    } catch (e) {
      emit(AuthError(message: ApiService.getErrorMessage(e)));
    }
  }

  Future<void> _handleAuthResponse(dynamic body, Emitter<AuthState> emit, String fallback) async {
    if (body['success'] == true) {
      final token = body['data']['token'] as String;
      final user = UserModel.fromJson(body['data']['user']);
      await StorageService.saveToken(token);
      await StorageService.saveUserRole(user.role);
      _onSignedIn();
      emit(Authenticated(user: user, token: token));
    } else {
      emit(AuthError(message: body['message'] ?? fallback));
    }
  }

  /// FR09: open the socket + inbox once a rider is signed in
  void _onSignedIn() {
    unawaited(NotificationCenter().start());
  }

  Future<void> _onLogout(LogoutRequested event, Emitter<AuthState> emit) async {
    emit(AuthLoading());
    RiderLocationService().stop();
    try {
      // Best effort: stop receiving tasks. The server refuses (409) mid-delivery.
      await _api.put(ApiConfig.riderStatus, data: {'isOnline': false});
    } catch (_) {}
    await _tearDown();
    emit(const Unauthenticated());
  }

  /// The token was rejected: sign out locally without calling the API
  /// (the status endpoint would just 401 again).
  Future<void> _onSessionExpired(SessionExpired event, Emitter<AuthState> emit) async {
    if (state is! Authenticated) return;
    RiderLocationService().stop();
    await _tearDown();
    emit(const Unauthenticated(message: 'Your session has expired. Please sign in again.'));
  }

  Future<void> _tearDown() async {
    NotificationCenter().stop();
    RealtimeService().disconnect();
    await StorageService.clearAll();
  }
}
