// ══════════════════════════════════════════════════════════════
// Vendra App - Auth Events
// ══════════════════════════════════════════════════════════════

import 'package:equatable/equatable.dart';

abstract class AuthEvent extends Equatable {
  const AuthEvent();
  @override
  List<Object?> get props => [];
}

/// Check if user is already logged in (splash screen)
class CheckAuthRequested extends AuthEvent {}

/// Login with email and password
class LoginRequested extends AuthEvent {
  final String email;
  final String password;
  const LoginRequested({required this.email, required this.password});
  @override
  List<Object?> get props => [email, password];
}

/// Signup with full details
class SignupRequested extends AuthEvent {
  final String fullName;
  final String email;
  final String password;
  final String role;
  final String? storeName;
  final String? cnic;
  final String? phone;
  const SignupRequested({
    required this.fullName,
    required this.email,
    required this.password,
    required this.role,
    this.storeName,
    this.cnic,
    this.phone,
  });
  @override
  List<Object?> get props => [fullName, email, password, role, cnic];
}

/// Refresh wallet from top-up / checkout response without re-fetching /me
class AuthWalletBalanceUpdated extends AuthEvent {
  final double walletBalance;
  const AuthWalletBalanceUpdated({required this.walletBalance});
  @override
  List<Object?> get props => [walletBalance];
}

/// Logout and clear token
class LogoutRequested extends AuthEvent {}

/// The server rejected the stored session (expired/invalid token). main.dart
/// has already cleared storage and stopped realtime; this just signs the
/// bloc out.
class SessionExpired extends AuthEvent {}
