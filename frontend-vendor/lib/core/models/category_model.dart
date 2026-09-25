// ══════════════════════════════════════════════════════════════
// Vendra App - Category Model (FR06)
// ══════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'json_utils.dart';

class CategoryModel {
  final int id;
  final String name;
  final String? icon;

  CategoryModel({required this.id, required this.name, this.icon});

  factory CategoryModel.fromJson(Map<String, dynamic> json) =>
      CategoryModel(id: toInt(json['id']), name: json['name'] ?? '', icon: json['icon']);

  /// Material icon for the server-side icon name
  IconData get iconData {
    switch (icon) {
      case 'devices': return Icons.devices_outlined;
      case 'phone_android': return Icons.phone_android;
      case 'checkroom': return Icons.checkroom;
      case 'local_grocery_store': return Icons.local_grocery_store_outlined;
      case 'kitchen': return Icons.kitchen_outlined;
      case 'spa': return Icons.spa_outlined;
      case 'menu_book': return Icons.menu_book_outlined;
      default: return Icons.category_outlined;
    }
  }
}
