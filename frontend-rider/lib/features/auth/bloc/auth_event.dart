// ══════════════════════════════════════════════════════════════
// Vendra Rider App - Auth Events
// ══════════════════════════════════════════════════════════════

import 'package:equatable/equatable.dart';

abstract class AuthEvent extends Equatable {
  const AuthEvent();
  @override
  List<Object?> get props => [];
}

/// Check if the rider is already logged in (splash screen)
class CheckAuthRequested extends AuthEvent {}

/// Login with email and password (always sent with role: rider)
class LoginRequested extends AuthEvent {
  final String email;
  final String password;
  const LoginRequested({required this.email, required this.password});
  @override
  List<Object?> get props => [email, password];
}

/// Rider sign-up with the documents an admin checks before the first delivery
class SignupRequested extends AuthEvent {
  final String fullName;
  final String email;
  final String password;
  final String phone;
  final String vehicleType; // motorcycle | scooter | bicycle | car
  final String cnic; // 12345-1234567-1
  final String? licenseNumber; // null for a bicycle
  final String? vehicleNumber; // null for a bicycle
  const SignupRequested({
    required this.fullName,
    required this.email,
    required this.password,
    required this.phone,
    required this.vehicleType,
    required this.cnic,
    this.licenseNumber,
    this.vehicleNumber,
  });
  @override
  List<Object?> get props => [fullName, email, phone, vehicleType, cnic, licenseNumber, vehicleNumber];
}

/// Refresh wallet balance (e.g. after a delivery payout) without re-fetching /me
class AuthWalletBalanceUpdated extends AuthEvent {
  final double walletBalance;
  const AuthWalletBalanceUpdated({required this.walletBalance});
  @override
  List<Object?> get props => [walletBalance];
}

/// Logout: stop tracking, go offline (best effort), clear token
class LogoutRequested extends AuthEvent {}

/// The server rejected the stored token (401 TOKEN_EXPIRED / INVALID_TOKEN).
/// Same teardown as logout, but no API calls — the token is already invalid.
class SessionExpired extends AuthEvent {}
