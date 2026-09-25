// ══════════════════════════════════════════════════════════════
// Vendra Vendor App - Where to go after signing in
// Used by the login screen and the splash auto-login. A vendor who
// signed in with a temporary password (an admin reset) must choose a
// new one first; then approved stores open the dashboard and stores
// still under review see the pending-approval screen.
// ══════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:vendra_vendor/vendra_core.dart';
import '../../../config/app_routes.dart';
import '../bloc/auth_bloc.dart';
import '../bloc/auth_event.dart';

void continueAfterSignIn(BuildContext context, UserModel user) {
  final navigator = Navigator.of(context);
  if (!user.mustChangePassword) {
    _openHome(navigator, user);
    return;
  }

  final authBloc = context.read<AuthBloc>();
  navigator.pushAndRemoveUntil(
    MaterialPageRoute(
      builder: (_) => ChangePasswordScreen(
        forced: true,
        onChanged: () {
          // Re-read /me so the signed-in user no longer carries mustChangePassword
          authBloc.add(RefreshUserRequested());
          _openHome(navigator, user);
        },
      ),
    ),
    (_) => false,
  );
}

void _openHome(NavigatorState navigator, UserModel user) {
  if (user.isApproved != true) {
    navigator.pushNamedAndRemoveUntil(AppRoutes.vendorPendingApproval, (_) => false, arguments: user);
  } else {
    navigator.pushNamedAndRemoveUntil(AppRoutes.vendorDashboard, (_) => false);
  }
}
