// ══════════════════════════════════════════════════════════════
// Vendra Rider App - Auth States
// ══════════════════════════════════════════════════════════════

import 'package:equatable/equatable.dart';
import 'package:vendra_rider/vendra_core.dart';

abstract class AuthState extends Equatable {
  const AuthState();
  @override
  List<Object?> get props => [];
}

/// Initial state - checking auth
class AuthInitial extends AuthState {}

/// Loading state during login/signup
class AuthLoading extends AuthState {}

/// Rider is authenticated
class Authenticated extends AuthState {
  final UserModel user;
  final String token;
  const Authenticated({required this.user, required this.token});
  @override
  List<Object?> get props => [user.id, user.walletBalance, token];
}

/// Not authenticated. [message] explains a sign-out the rider didn't ask for
/// (e.g. an expired session) and is shown on the way back to the login screen.
class Unauthenticated extends AuthState {
  final String? message;
  const Unauthenticated({this.message});
  @override
  List<Object?> get props => [message];
}

/// Auth error occurred (message comes from the server, e.g. 403 WRONG_APP)
class AuthError extends AuthState {
  final String message;
  const AuthError({required this.message});
  @override
  List<Object?> get props => [message];
}
