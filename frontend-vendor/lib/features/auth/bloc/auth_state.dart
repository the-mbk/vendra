// ══════════════════════════════════════════════════════════════
// Vendra App - Auth States
// ══════════════════════════════════════════════════════════════

import 'package:equatable/equatable.dart';
import 'package:vendra_vendor/vendra_core.dart';

abstract class AuthState extends Equatable {
  const AuthState();
  @override
  List<Object?> get props => [];
}

/// Initial state - checking auth
class AuthInitial extends AuthState {}

/// Loading state during login/signup
class AuthLoading extends AuthState {}

/// User is authenticated
class Authenticated extends AuthState {
  final UserModel user;
  final String token;
  const Authenticated({required this.user, required this.token});
  @override
  List<Object?> get props => [
        user.id,
        user.walletBalance,
        user.platformEscrowBalance,
        user.mustChangePassword,
        // A new logo / cover photo must rebuild every screen that shows it
        user.storeName,
        user.storeLogoUrl,
        user.storeCoverUrl,
        token,
      ];
}

/// User is not authenticated
class Unauthenticated extends AuthState {}

/// Auth error occurred
class AuthError extends AuthState {
  final String message;
  const AuthError({required this.message});
  @override
  List<Object?> get props => [message];
}
