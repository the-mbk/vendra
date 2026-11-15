// ══════════════════════════════════════════════════════════════
// Vendra Vendor App - Packing checklist on a confirmed order card (FR07)
// Each line has a checkbox (PUT …/items/:itemId/pack { packed }) and shows
// units packed so far; "Scan to pack" reads a barcode with the camera (or
// the typed fallback) and packs one unit (POST …/scan). A progress bar
// shows "3/5 units packed". Read-only for roles without orders.fulfil.
// ══════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:vendra_vendor/vendra_core.dart';

import '../bloc/vendor_order_bloc.dart';
import '../models/packing.dart';
import '../screens/barcode_scanner_screen.dart';

class PackingChecklist extends StatelessWidget {
  final OrderModel order;
  /// The signed-in person may tick lines and scan (orders.fulfil)
  final bool canPack;

  const PackingChecklist({super.key, required this.order, required this.canPack});

  Future<void> _scan(BuildContext context) async {
    final bloc = context.read<VendorOrderBloc>();
    final code = await scanBarcode(context);
    if (code != null && code.trim().isNotEmpty) bloc.add(ScanPackOrder(orderId: order.id, barcode: code));
  }

  @override
  Widget build(BuildContext context) {
    final bloc = context.read<VendorOrderBloc>();
    final done = order.isFullyPacked;
    final scanning = bloc.isScanningOrder(order.id);
    final color = done ? AppColors.stockGreen : Colors.indigo;

    return Container(
      margin: const EdgeInsets.only(top: 4),
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(done ? Icons.inventory : Icons.checklist, size: 18, color: color),
              const SizedBox(width: 6),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Packing checklist',
                        style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w600, color: color)),
                    Text(packingProgressLabel(order),
                        style: GoogleFonts.poppins(fontSize: 11, color: AppColors.textSecondary)),
                  ],
                ),
              ),
              if (canPack)
                TextButton.icon(
                  onPressed: scanning || done ? null : () => _scan(context),
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.indigo,
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                  ),
                  icon: scanning
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.qr_code_scanner, size: 18),
                  label: Text('Scan to pack', style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w600)),
                ),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: packingFraction(order),
              minHeight: 6,
              backgroundColor: Colors.grey.shade200,
              color: color,
            ),
          ),
          const SizedBox(height: 4),
          for (final item in order.items) _line(context, bloc, item),
        ],
      ),
    );
  }

  Widget _line(BuildContext context, VendorOrderBloc bloc, OrderItemModel item) {
    final busy = item.id != null && bloc.isPackingItem(item.id!);
    final packed = item.isPacked;
    final enabled = canPack && item.id != null && !busy;
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: enabled
          ? () => bloc.add(PackOrderItem(orderId: order.id, itemId: item.id!, packed: packTargetFor(item)))
          : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          children: [
            SizedBox(
              width: 36,
              height: 36,
              child: busy
                  ? const Padding(
                      padding: EdgeInsets.all(9),
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Checkbox(
                      tristate: true,
                      value: packCheckboxValue(item),
                      activeColor: AppColors.stockGreen,
                      onChanged: enabled
                          ? (_) => bloc.add(PackOrderItem(orderId: order.id, itemId: item.id!, packed: packTargetFor(item)))
                          : null,
                    ),
            ),
            const SizedBox(width: 4),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${item.quantity} × ${item.productName ?? 'Product #${item.productId}'}',
                    style: GoogleFonts.poppins(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: packed ? AppColors.textSecondary : AppColors.textPrimary,
                      decoration: packed ? TextDecoration.lineThrough : null,
                    ),
                  ),
                  if (item.barcode != null && item.barcode!.isNotEmpty)
                    Text('Barcode ${item.barcode}',
                        style: GoogleFonts.poppins(fontSize: 10, color: AppColors.textLight)),
                ],
              ),
            ),
            const SizedBox(width: 6),
            Text(
              '${item.packedQuantity}/${item.quantity}',
              style: GoogleFonts.poppins(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: packed ? AppColors.stockGreen : AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
