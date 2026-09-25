// ══════════════════════════════════════════════════════════════
// Vendra App - Auth BLoC
// Manages authentication state: login, signup, auto-login, logout
// ══════════════════════════════════════════════════════════════

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:vendra_vendor/vendra_core.dart';
import 'auth_event.dart';
import 'auth_state.dart';

class AuthBloc extends Bloc<AuthEvent, AuthState> {
  final ApiService _api = ApiService();

  AuthBloc() : super(AuthInitial()) {
    on<CheckAuthRequested>(_onCheckAuth);
    on<LoginRequested>(_onLogin);
    on<SignupRequested>(_onSignup);
    on<LogoutRequested>(_onLogout);
    on<AuthWalletBalanceUpdated>(_onWalletBalanceUpdated);
    on<RefreshUserRequested>(_onRefreshUser);
  }

  /// Opens the realtime socket + notification inbox for a signed-in vendor (FR09)
  void _startLiveServices(UserModel user) {
    if (!user.isVendor) return;
    NotificationCenter().start();
  }

  /// Re-reads /api/auth/me (e.g. wallet balance after an escrow release).
  /// Unlike CheckAuthRequested, a network failure here never signs the vendor out.
  Future<void> _onRefreshUser(RefreshUserRequested event, Emitter<AuthState> emit) async {
    final current = state;
    if (current is! Authenticated) return;
    try {
      final response = await _api.get(ApiConfig.me);
      if (response.data['success'] == true) {
        emit(Authenticated(user: UserModel.fromJson(response.data['data']), token: current.token));
      }
    } catch (_) {
      // Keep the current user; the next refresh will catch up.
    }
  }

  void _onWalletBalanceUpdated(AuthWalletBalanceUpdated event, Emitter<AuthState> emit) {
    final state = this.state;
    if (state is Authenticated) {
      emit(Authenticated(
        user: state.user.copyWith(walletBalance: event.walletBalance),
        token: state.token,
      ));
    }
  }

  /// Check if user has a stored token and validate it
  Future<void> _onCheckAuth(CheckAuthRequested event, Emitter<AuthState> emit) async {
    try {
      final hasToken = await StorageService.hasToken();
      if (!hasToken) {
        emit(Unauthenticated());
        return;
      }

      // Validate token by calling /me endpoint
      final response = await _api.get(ApiConfig.me);
      if (response.data['success'] == true) {
        final user = UserModel.fromJson(response.data['data']);
        final token = (await StorageService.getToken())!;
        _startLiveServices(user);
        emit(Authenticated(user: user, token: token));
      } else {
        await StorageService.clearAll();
        emit(Unauthenticated());
      }
    } catch (e) {
      await StorageService.clearAll();
      emit(Unauthenticated());
    }
  }

  /// Login with email and password
  Future<void> _onLogin(LoginRequested event, Emitter<AuthState> emit) async {
    emit(AuthLoading());
    try {
      final response = await _api.post(
        ApiConfig.login,
        data: {
          'email': event.email,
          'password': event.password,
          // FR05: the server refuses non-vendor accounts with 403 WRONG_APP
          'role': 'vendor',
        },
      );

      if (response.data['success'] == true) {
        final token = response.data['data']['token'];
        final user = UserModel.fromJson(response.data['data']['user']);

        // Persist token and role
        await StorageService.saveToken(token);
        await StorageService.saveUserRole(user.role);

        _startLiveServices(user);
        emit(Authenticated(user: user, token: token));
      } else {
        emit(AuthError(message: response.data['message'] ?? 'Login failed'));
      }
    } catch (e) {
      if (ApiService.getErrorCode(e) == 'WRONG_APP') {
        // e.g. "This is a customer account. Please sign in with the Vendra app."
        emit(AuthError(message: ApiService.getErrorData(e)?['message'] ?? 'This account belongs to another Vendra app.'));
      } else {
        emit(AuthError(message: ApiService.getErrorMessage(e)));
      }
    }
  }

  /// Signup with full details
  Future<void> _onSignup(SignupRequested event, Emitter<AuthState> emit) async {
    emit(AuthLoading());
    try {
      final response = await _api.post(
        ApiConfig.signup,
        data: {
          'fullName': event.fullName,
          'email': event.email,
          'password': event.password,
          'role': event.role,
          if (event.storeName != null) 'storeName': event.storeName,
          if (event.cnic != null) 'cnic': event.cnic,
          if (event.phone != null) 'phone': event.phone,
        },
      );

      if (response.data['success'] == true) {
        final token = response.data['data']['token'];
        final user = UserModel.fromJson(response.data['data']['user']);

        await StorageService.saveToken(token);
        await StorageService.saveUserRole(user.role);

        _startLiveServices(user);
        emit(Authenticated(user: user, token: token));
      } else {
        emit(AuthError(message: response.data['message'] ?? 'Signup failed'));
      }
    } catch (e) {
      emit(AuthError(message: ApiService.getErrorMessage(e)));
    }
  }

  /// Logout and clear stored data
  Future<void> _onLogout(LogoutRequested event, Emitter<AuthState> emit) async {
    NotificationCenter().stop();
    RealtimeService().disconnect();
    await StorageService.clearAll();
    emit(Unauthenticated());
  }
}
