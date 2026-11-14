// ══════════════════════════════════════════════════════════════
// Vendra Vendor App - Shop staff models
//   GET /api/vendor/staff         (owner)  → StaffMember rows
//   GET /api/vendor/staff/roster  (anyone) → { id, fullName, role } (same class)
// ══════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:vendra_vendor/vendra_core.dart';

/// A role the owner can give a staff member, with what it unlocks
class StaffRole {
  final String key;
  final String label;
  final String summary;
  final IconData icon;
  final Color color;

  const StaffRole({
    required this.key,
    required this.label,
    required this.summary,
    required this.icon,
    required this.color,
  });
}

const List<StaffRole> staffRoles = [
  StaffRole(
    key: 'cashier',
    label: 'Cashier',
    summary: 'Walk-in POS sales · views products',
    icon: Icons.point_of_sale,
    color: AppColors.primary,
  ),
  StaffRole(
    key: 'packer',
    label: 'Packer',
    summary: 'Accepts, packs and hands over orders',
    icon: Icons.inventory_outlined,
    color: Colors.indigo,
  ),
  StaffRole(
    key: 'inventory_manager',
    label: 'Inventory Manager',
    summary: 'Products, stock, photos and ledger · views orders',
    icon: Icons.warehouse_outlined,
    color: AppColors.stockGreen,
  ),
];

/// Role details for a key; unknown roles fall back to a neutral entry
StaffRole staffRoleOf(String key) => staffRoles.firstWhere(
      (r) => r.key == key,
      orElse: () => StaffRole(key: key, label: key, summary: '', icon: Icons.badge_outlined, color: Colors.blueGrey),
    );

class StaffMember {
  final int id;
  final String fullName;
  final String role; // cashier | packer | inventory_manager
  final bool isActive;
  final DateTime? lastLoginAt;
  /// Set while 5 wrong PINs have locked this person out (a new PIN lifts it)
  final DateTime? lockedUntil;

  const StaffMember({
    required this.id,
    required this.fullName,
    required this.role,
    this.isActive = true,
    this.lastLoginAt,
    this.lockedUntil,
  });

  factory StaffMember.fromJson(Map<String, dynamic> json) => StaffMember(
        id: toInt(json['id']),
        fullName: json['fullName'] ?? '',
        role: json['role'] ?? '',
        isActive: json['isActive'] != false,
        lastLoginAt: toDate(json['lastLoginAt']),
        lockedUntil: toDate(json['lockedUntil']),
      );

  StaffRole get roleInfo => staffRoleOf(role);
  bool get isLocked => lockedUntil != null && lockedUntil!.isAfter(DateTime.now());
}

/// 4–6 digits, as the server requires
String? validatePin(String? value, {bool required = true}) {
  final v = value?.trim() ?? '';
  if (v.isEmpty) return required ? 'Enter a PIN' : null;
  if (!RegExp(r'^\d{4,6}$').hasMatch(v)) return 'PIN must be 4 to 6 digits';
  return null;
}
