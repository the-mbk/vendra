// ══════════════════════════════════════════════════════════════
// Vendra Vendor App - POS dialogs
// ReservationConflictDialog (FR02): a walk-in customer wants units that
//   open online orders have reserved. Shows which order would lose them
//   and the dual-inventory numbers; the cashier drops the walk-in item or
//   overrides (the server cancels + refunds that order on completion).
// TenderDialog (SRDS §1.3): quick cash chips and the change to return.
// ══════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:vendra_vendor/vendra_core.dart';

final NumberFormat _money = NumberFormat('#,##0.##');
String _rs(double v) => 'Rs. ${_money.format(v)}';

enum ConflictChoice { dropWalkIn, override }

/// An open online order holding units of the product (GET …/products/:id/reservations)
class ProductReservation {
  final int orderId;
  final int quantity;
  final String status;
  final String? customerName;

  /// Units are still on the shelf (pending / confirmed), so a walk-in sale may take them
  final bool overridable;

  const ProductReservation({
    required this.orderId,
    required this.quantity,
    required this.status,
    this.customerName,
    required this.overridable,
  });

  factory ProductReservation.fromJson(Map<String, dynamic> json) => ProductReservation(
        orderId: toInt(json['orderId']),
        quantity: toInt(json['quantity']),
        status: (json['status'] ?? '').toString(),
        customerName: json['customerName']?.toString(),
        overridable: json['overridable'] == true,
      );
}

class ReservationConflictDialog extends StatefulWidget {
  final ProductModel product;

  /// Units the cashier is trying to ring up in total
  final int requested;

  /// Units the counter may sell without touching reservations
  final int sellable;

  const ReservationConflictDialog({super.key, required this.product, required this.requested, required this.sellable});

  @override
  State<ReservationConflictDialog> createState() => _ReservationConflictDialogState();
}

class _ReservationConflictDialogState extends State<ReservationConflictDialog> {
  List<ProductReservation>? _orders;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final res = await ApiService().get(ApiConfig.vendorProductReservations(widget.product.id));
      final list = (res.data['data'] as List<dynamic>? ?? const [])
          .whereType<Map>()
          .map((m) => ProductReservation.fromJson(Map<String, dynamic>.from(m)))
          .toList();
      if (mounted) setState(() => _orders = list);
    } catch (e) {
      if (mounted) setState(() => _error = ApiService.getErrorMessage(e));
    }
  }

  /// The orders the server would cancel: newest overridable first, until the shortfall is covered
  List<ProductReservation> get _toCancel {
    final shortfall = widget.requested - widget.sellable;
    final picked = <ProductReservation>[];
    var freed = 0;
    for (final o in _orders ?? const <ProductReservation>[]) {
      if (freed >= shortfall) break;
      if (!o.overridable) continue;
      picked.add(o);
      freed += o.quantity;
    }
    return freed >= shortfall ? picked : const [];
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.product;
    final cancel = _toCancel;
    final loading = _orders == null && _error == null;
    final orderLabel = cancel.map((o) => '#${o.orderId}').join(', ');
    final title = cancel.isEmpty
        ? 'Item reserved for online orders'
        : 'Item reserved for Online Order${cancel.length == 1 ? '' : 's'} $orderLabel';

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      icon: const Icon(Icons.lock_clock_outlined, color: AppColors.reservedAmber, size: 34),
      title: Text(title, textAlign: TextAlign.center, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                widget.sellable > 0
                    ? 'Only ${widget.sellable} ${p.name} can be sold at the counter; the rest of the shelf is reserved. '
                        'Selling ${widget.requested} to a walk-in customer will cancel the pending online order.'
                    : 'Only reserved units of ${p.name} remain on the shelf. Selling this to a walk-in customer '
                        'will force cancellation of the pending online order.',
                style: TextStyle(fontSize: 13, height: 1.45, color: AppColors.textSecondary),
              ),
              const SizedBox(height: 6),
              Text(
                'The customer is refunded in full, and the cancellation is recorded on your store\'s record for Vendra review.',
                style: TextStyle(fontSize: 12, height: 1.4, color: AppColors.warningInk),
              ),
              const SizedBox(height: 14),
              DualStockMatrix(
                privateStock: p.privateStock,
                buffer: p.buffer,
                reserved: p.reservedQuantity,
                compact: true,
              ),
              const SizedBox(height: 12),
              if (loading)
                const Center(child: Padding(padding: EdgeInsets.all(8), child: CircularProgressIndicator(strokeWidth: 2)))
              else if (_error != null)
                Text(_error!, style: const TextStyle(fontSize: 12, color: AppColors.error))
              else ...[
                for (final o in _orders!) _orderRow(o, cancel.contains(o)),
                if (cancel.isEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      'These units are already packed for orders in progress, so they can\'t be sold at the counter.',
                      style: TextStyle(fontSize: 12, color: AppColors.warningInk),
                    ),
                  ),
              ],
            ],
          ),
        ),
      ),
      actionsAlignment: MainAxisAlignment.spaceBetween,
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, ConflictChoice.dropWalkIn),
          child: Text(widget.sellable > 0 ? 'Sell ${widget.sellable} only' : 'Cancel walk-in item'),
        ),
        ElevatedButton.icon(
          onPressed: cancel.isEmpty ? null : () => Navigator.pop(context, ConflictChoice.override),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.reservedAmber,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          ),
          icon: const Icon(Icons.swap_horiz, size: 18),
          label: Text(cancel.length > 1 ? 'Override & cancel ${cancel.length} orders' : 'Override & cancel online order'),
        ),
      ],
    );
  }

  Widget _orderRow(ProductReservation o, bool willCancel) {
    final color = willCancel ? AppColors.error : AppColors.textSecondary;
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.surfaceMuted,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: willCancel ? AppColors.error.withValues(alpha: 0.4) : AppColors.hairline),
      ),
      child: Row(
        children: [
          Icon(willCancel ? Icons.cancel_outlined : Icons.receipt_long_outlined, size: 16, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Order #${o.orderId} · ${o.quantity} unit${o.quantity == 1 ? '' : 's'}'
              '${o.customerName != null ? ' · ${o.customerName}' : ''}',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: AppColors.textPrimary),
            ),
          ),
          Text(
            willCancel ? 'Will be cancelled' : (o.overridable ? o.status : 'Packed'),
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: color),
          ),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════
// Cash tender
// ══════════════════════════════════════════════════════════════

/// Returns the cash received (≥ the bill) or null when cancelled
class TenderDialog extends StatefulWidget {
  final double bill;
  const TenderDialog({super.key, required this.bill});

  @override
  State<TenderDialog> createState() => _TenderDialogState();
}

class _TenderDialogState extends State<TenderDialog> {
  static const _notes = [500.0, 1000.0, 5000.0];
  final _ctrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _set(widget.bill);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _set(double v) {
    _ctrl.text = _money.format(v).replaceAll(',', '');
    _ctrl.selection = TextSelection.collapsed(offset: _ctrl.text.length);
    setState(() {});
  }

  double? get _received => double.tryParse(_ctrl.text.trim());

  @override
  Widget build(BuildContext context) {
    final received = _received;
    final enough = received != null && received >= widget.bill;

    Widget chip(String label, double value) {
      final selected = received == value;
      return ChoiceChip(
        label: Text(label),
        selected: selected,
        showCheckmark: false,
        onSelected: (_) => _set(value),
        selectedColor: AppColors.secondary,
        labelStyle: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: selected ? Colors.white : AppColors.textPrimary,
        ),
      );
    }

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Text('Cash payment', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Text('Bill', style: TextStyle(fontSize: 14, color: AppColors.textSecondary)),
                const Spacer(),
                Text(_rs(widget.bill), style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: AppColors.secondary)),
              ],
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                chip('Exact bill', widget.bill),
                for (final note in _notes)
                  if (note > widget.bill) chip(_rs(note), note),
              ],
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _ctrl,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(labelText: 'Cash received (Rs.)', prefixIcon: Icon(Icons.payments_outlined)),
            ),
            const SizedBox(height: 14),
            if (received != null)
              enough
                  ? CashChangeLine(bill: widget.bill, received: received)
                  : Text(
                      'Short by ${_rs(widget.bill - received)}',
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.error),
                    ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Back')),
        ElevatedButton.icon(
          onPressed: enough ? () => Navigator.pop(context, received) : null,
          style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12)),
          icon: const Icon(Icons.check_circle_outline, size: 18),
          label: const Text('Complete sale'),
        ),
      ],
    );
  }
}

/// "Bill: Rs. 340 | Received: Rs. 1,000 → Return: Rs. 660"
class CashChangeLine extends StatelessWidget {
  final double bill;
  final double received;
  const CashChangeLine({super.key, required this.bill, required this.received});

  @override
  Widget build(BuildContext context) {
    final change = received - bill;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.successSurface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.success.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'Bill ${_rs(bill)}  ·  Received ${_rs(received)}',
              style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            'Return ${_rs(change)}',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: AppColors.successInk,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}
