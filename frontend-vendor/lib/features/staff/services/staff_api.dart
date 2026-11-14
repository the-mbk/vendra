// ══════════════════════════════════════════════════════════════
// Vendra Vendor App - Shop staff API calls
//   roster / switch     anyone signed in on the shop's device
//   list / add / edit   the store owner only (403 STAFF_NOT_ALLOWED /
//                       STAFF_FORBIDDEN for staff tokens)
//   ownerSignIn         "Back to owner": a normal vendor login
// Errors are thrown as-is; callers show ApiService.getErrorMessage(e).
// ══════════════════════════════════════════════════════════════

import 'package:vendra_vendor/vendra_core.dart';

import '../models/staff_member.dart';

class StaffApi {
  final ApiService _api = ApiService();

  static List<StaffMember> _parse(dynamic data) =>
      (data as List).map((j) => StaffMember.fromJson(Map<String, dynamic>.from(j as Map))).toList();

  /// Active staff for the switch-user screen
  Future<List<StaffMember>> roster() async {
    final res = await _api.get(ApiConfig.staffRoster);
    return _parse(res.data['data']);
  }

  /// PIN sign-in → the staff token (12 h). 401 WRONG_PIN { attemptsLeft }, 429 PIN_LOCKED
  Future<String> switchTo(int staffId, String pin) async {
    final res = await _api.post(ApiConfig.staffSwitch, data: {'staffId': staffId, 'pin': pin});
    return res.data['data']['token'] as String;
  }

  /// The owner's password → the owner token again
  Future<String> ownerSignIn(String email, String password) async {
    final res = await _api.post(ApiConfig.login, data: {'email': email, 'password': password, 'role': 'vendor'});
    return res.data['data']['token'] as String;
  }

  /// Everyone, removed staff last
  Future<List<StaffMember>> list() async {
    final res = await _api.get(ApiConfig.staff);
    return _parse(res.data['data']);
  }

  /// Returns the server's confirmation message
  Future<String> add({required String fullName, required String role, required String pin}) async {
    final res = await _api.post(ApiConfig.staff, data: {'fullName': fullName, 'role': role, 'pin': pin});
    return res.data['message'] ?? 'Staff member added.';
  }

  /// Any of name / role / new PIN (also lifts a lockout) / active
  Future<String> update(int id, {String? fullName, String? role, String? pin, bool? isActive}) async {
    final res = await _api.put(ApiConfig.staffMember(id), data: {
      if (fullName != null) 'fullName': fullName,
      if (role != null) 'role': role,
      if (pin != null) 'pin': pin,
      if (isActive != null) 'isActive': isActive,
    });
    return res.data['message'] ?? 'Staff member updated.';
  }

  /// Deactivates; their sessions end straight away
  Future<String> remove(int id) async {
    final res = await _api.delete(ApiConfig.staffMember(id));
    return res.data['message'] ?? 'Staff member removed.';
  }
}
