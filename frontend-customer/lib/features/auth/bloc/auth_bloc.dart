// ══════════════════════════════════════════════════════════════
// Vendra App - Auth BLoC
// Manages authentication state: login, signup, auto-login, logout
// ══════════════════════════════════════════════════════════════

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:vendra_customer/vendra_core.dart';
import 'auth_event.dart';
import 'auth_state.dart';

class AuthBloc extends Bloc<AuthEvent, AuthState> {
  final ApiService _api = ApiService();

  AuthBloc() : super(AuthInitial()) {
    on<CheckAuthRequested>(_onCheckAuth);
    on<LoginRequested>(_onLogin);
    on<SignupRequested>(_onSignup);
    on<LogoutRequested>(_onLogout);
    on<SessionExpired>((_, emit) => emit(Unauthenticated()));
    on<AuthWalletBalanceUpdated>(_onWalletBalanceUpdated);
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
          // FR05: the server rejects vendor/rider/admin accounts in this app (403 WRONG_APP)
          'role': 'customer',
        },
      );

      if (response.data['success'] == true) {
        final token = response.data['data']['token'];
        final user = UserModel.fromJson(response.data['data']['user']);

        // Persist token and role
        await StorageService.saveToken(token);
        await StorageService.saveUserRole(user.role);

        emit(Authenticated(user: user, token: token));
      } else {
        emit(AuthError(message: response.data['message'] ?? 'Login failed'));
      }
    } catch (e) {
      if (ApiService.getErrorCode(e) == 'WRONG_APP') {
        // 403: e.g. "This is a vendor account. Please sign in with the Vendra Vendor app."
        final serverMessage = ApiService.getErrorData(e)?['message']?.toString();
        emit(AuthError(
          message: serverMessage ?? 'This account is not a customer account. Please use the matching Vendra app.',
        ));
        return;
      }
      emit(AuthError(message: ApiService.getErrorMessage(e)));
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
    // FR09: stop the inbox and close the socket so the next user starts clean
    NotificationCenter().stop();
    RealtimeService().disconnect();
    await StorageService.clearAll();
    emit(Unauthenticated());
  }
}
