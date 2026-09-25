// ══════════════════════════════════════════════════════════════
// Vendra Rider App - Where to go after signing in
// Login, sign-up and splash auto-login all land here. A rider who
// signed in with a temporary password (admin reset) must choose a
// new one first; everyone else goes straight to the home shell.
// ══════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:vendra_rider/vendra_core.dart';

import '../../config/app_routes.dart';

void openSignedInHome(BuildContext context, UserModel user) {
  final navigator = Navigator.of(context);
  void goHome() => navigator.pushNamedAndRemoveUntil(AppRoutes.riderHome, (_) => false);

  if (!user.mustChangePassword) {
    goHome();
    return;
  }
  navigator.pushAndRemoveUntil(
    MaterialPageRoute<void>(
      builder: (_) => ChangePasswordScreen(forced: true, onChanged: goHome),
    ),
    (_) => false,
  );
}
