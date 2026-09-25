// ══════════════════════════════════════════════════════════════
// Vendra App - Secure Storage Service
// Wrapper around flutter_secure_storage for JWT token persistence
// ══════════════════════════════════════════════════════════════

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class StorageService {
  static const _storage = FlutterSecureStorage();

  // Storage keys
  static const String _tokenKey = 'vendra_auth_token';
  static const String _userRoleKey = 'vendra_user_role';

  /// Save JWT token to secure storage
  static Future<void> saveToken(String token) async {
    await _storage.write(key: _tokenKey, value: token);
  }

  /// Read JWT token from secure storage
  static Future<String?> getToken() async {
    return await _storage.read(key: _tokenKey);
  }

  /// Save user role for quick access (avoids decoding JWT)
  static Future<void> saveUserRole(String role) async {
    await _storage.write(key: _userRoleKey, value: role);
  }

  /// Get saved user role
  static Future<String?> getUserRole() async {
    return await _storage.read(key: _userRoleKey);
  }

  /// Clear all stored data (used for logout)
  static Future<void> clearAll() async {
    await _storage.deleteAll();
  }

  /// Check if user has a stored token
  static Future<bool> hasToken() async {
    final token = await getToken();
    return token != null && token.isNotEmpty;
  }
}
