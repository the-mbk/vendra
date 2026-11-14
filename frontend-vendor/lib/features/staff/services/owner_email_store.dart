// ══════════════════════════════════════════════════════════════
// Vendra Vendor App - The store owner's email, kept on the shop's device
// When a staff member switches in, "Back to owner" (and the sign-in screen
// after a staff session ends) only asks for the owner's password.
// Kept in shared preferences, not secure storage: it is not a secret, and
// sign-out wipes secure storage while the email should stay for next time.
// ══════════════════════════════════════════════════════════════

import 'package:shared_preferences/shared_preferences.dart';

class OwnerEmailStore {
  static const _key = 'vendra_vendor_owner_email';

  static Future<void> remember(String email) async {
    if (email.isEmpty) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key, email);
    } catch (_) {
      // Only a convenience — never block a sign-in over it
    }
  }

  static Future<String?> read() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(_key);
    } catch (_) {
      return null;
    }
  }
}
