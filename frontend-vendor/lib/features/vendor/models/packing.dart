// ══════════════════════════════════════════════════════════════
// Vendra Vendor App - Packing checklist helpers (FR07)
// A confirmed order is packed line by line (tick a line, or scan one unit
// at a time); "Mark as packed" opens up only once every unit is packed —
// the server enforces the same rule with 409 PACKING_INCOMPLETE.
// ══════════════════════════════════════════════════════════════

import 'package:vendra_vendor/vendra_core.dart';

/// "3/5 units packed" (singular for a one-unit order)
String packingProgressLabel(OrderModel order) {
  final total = order.totalUnits;
  return '${order.packedUnits}/$total unit${total == 1 ? '' : 's'} packed';
}

/// 0.0–1.0 for the progress bar
double packingFraction(OrderModel order) =>
    order.totalUnits == 0 ? 0 : (order.packedUnits / order.totalUnits).clamp(0.0, 1.0);

/// Checkbox state for one line: ticked, part-packed (null = tristate dash), or not started
bool? packCheckboxValue(OrderItemModel item) {
  if (item.isPacked) return true;
  if (item.packedQuantity > 0) return null;
  return false;
}

/// What tapping a line's checkbox asks for: a fully packed line is unticked,
/// anything else (empty or part-packed) is packed in full
bool packTargetFor(OrderItemModel item) => !item.isPacked;

/// "Mark as packed" is enabled only for a confirmed order with every unit packed
bool canMarkPacked(OrderModel order) => order.status == 'confirmed' && order.isFullyPacked;
