// ══════════════════════════════════════════════════════════════
// Vendra Vendor App - Stock in (FR01: "Vendor adds stock via mobile
// camera barcode scanning")
// Scan a delivered item → the matching product opens with its shelf,
// reserved and online counts → enter how many arrived → the units are
// added (POST /api/vendor/products/:id/stock-in, an increment logged as
// stock_in). "Add and scan next" goes straight to the next item. A barcode
// that matches nothing can be added as a new product.
// ══════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:vendra_vendor/vendra_core.dart';

import '../bloc/vendor_product_bloc.dart';
import '../screens/add_edit_product_screen.dart';
import '../screens/barcode_scanner_screen.dart';

/// Units the store can still sell (on the shelf, not held by online orders)
int freeUnits(ProductModel p) => p.privateStock - p.reservedQuantity;

/// Online stock after adding [added] units: shelf − buffer − reserved, never below 0
int onlineAfter(ProductModel p, int added) {
  final online = p.privateStock + added - p.buffer - p.reservedQuantity;
  return online < 0 ? 0 : online;
}

/// Starts receiving stock: for [product] directly, or by scanning when it is null.
Future<void> startStockIn(BuildContext context, {ProductModel? product}) async {
  var next = product;
  while (context.mounted) {
    next ??= await _scanForProduct(context);
    if (next == null || !context.mounted) return;
    final scanNext = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _StockInSheet(product: next!, offerScanNext: product == null),
    );
    if (!context.mounted) return;
    context.read<VendorProductBloc>().add(const FetchVendorProducts(silent: true));
    if (scanNext != true) return;
    next = null; // scan the next item
  }
}

/// Scans a barcode and finds the product; offers to add an unknown one
Future<ProductModel?> _scanForProduct(BuildContext context) async {
  final code = await scanBarcode(context);
  if (code == null || code.trim().isEmpty || !context.mounted) return null;
  final messenger = ScaffoldMessenger.of(context);
  try {
    final res = await ApiService().get(ApiConfig.vendorProductByBarcode(code.trim()));
    return ProductModel.fromJson(Map<String, dynamic>.from(res.data['data'] as Map));
  } catch (e) {
    if (!context.mounted) return null;
    if (ApiService.getErrorCode(e) == 'UNKNOWN_BARCODE') {
      final add = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Not in your catalogue'),
          content: Text('No product has the barcode $code. Add it as a new product?'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
            ElevatedButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Add product')),
          ],
        ),
      );
      if (add == true && context.mounted) {
        await Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => AddEditProductScreen(initialBarcode: code.trim())),
        );
      }
    } else {
      messenger.showSnackBar(SnackBar(content: Text(ApiService.getErrorMessage(e)), backgroundColor: AppColors.error));
    }
    return null;
  }
}

class _StockInSheet extends StatefulWidget {
  final ProductModel product;
  final bool offerScanNext;
  const _StockInSheet({required this.product, required this.offerScanNext});

  @override
  State<_StockInSheet> createState() => _StockInSheetState();
}

class _StockInSheetState extends State<_StockInSheet> {
  final _qtyCtrl = TextEditingController(text: '1');
  final _noteCtrl = TextEditingController();
  bool _busy = false;
  String? _error;

  int get _qty => int.tryParse(_qtyCtrl.text.trim()) ?? 0;

  @override
  void dispose() {
    _qtyCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  void _step(int delta) {
    final next = (_qty + delta).clamp(1, 100000);
    setState(() => _qtyCtrl.text = '$next');
  }

  Future<void> _submit({required bool scanNext}) async {
    if (_qty < 1) {
      setState(() => _error = 'Enter how many units arrived.');
      return;
    }
    setState(() { _busy = true; _error = null; });
    try {
      final res = await ApiService().post(ApiConfig.vendorProductStockIn(widget.product.id), data: {
        'quantity': _qty,
        if (_noteCtrl.text.trim().isNotEmpty) 'note': _noteCtrl.text.trim(),
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(res.data['message'] as String? ?? 'Stock added.'),
        backgroundColor: AppColors.success,
      ));
      Navigator.pop(context, scanNext);
    } catch (e) {
      if (!mounted) return;
      setState(() { _busy = false; _error = ApiService.getErrorMessage(e); });
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.product;
    final label = GoogleFonts.poppins(fontSize: 12, color: AppColors.textSecondary);

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Stock in', style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
              const SizedBox(height: 12),
              Row(
                children: [
                  SizedBox(
                    width: 56,
                    height: 56,
                    child: ProductImage(product: p, iconSize: 24, borderRadius: BorderRadius.circular(12)),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(p.name,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                        if (p.barcode != null) Text(p.barcode!, style: label),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              _StockLine(p: p, added: _qty),
              const SizedBox(height: 16),
              Row(
                children: [
                  IconButton.outlined(
                    tooltip: 'One less',
                    onPressed: _busy || _qty <= 1 ? null : () => _step(-1),
                    icon: const Icon(Icons.remove),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _qtyCtrl,
                      enabled: !_busy,
                      textAlign: TextAlign.center,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(6)],
                      decoration: const InputDecoration(labelText: 'Units received'),
                      onChanged: (_) => setState(() => _error = null),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.outlined(
                    tooltip: 'One more',
                    onPressed: _busy ? null : () => _step(1),
                    icon: const Icon(Icons.add),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _noteCtrl,
                enabled: !_busy,
                maxLength: 200,
                decoration: const InputDecoration(labelText: 'Note (optional)', hintText: 'e.g. supplier invoice number'),
              ),
              if (_error != null) ...[
                const SizedBox(height: 4),
                Text(_error!, style: GoogleFonts.poppins(fontSize: 12, color: AppColors.error)),
              ],
              const SizedBox(height: 12),
              ElevatedButton.icon(
                onPressed: _busy ? null : () => _submit(scanNext: false),
                icon: _busy
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.add_box_outlined),
                label: Text(_qty > 0 ? 'Add $_qty to stock' : 'Add to stock'),
              ),
              if (widget.offerScanNext) ...[
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: _busy ? null : () => _submit(scanNext: true),
                  icon: const Icon(Icons.qr_code_scanner),
                  label: const Text('Add and scan next'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Shelf / reserved / online now, and online after this delivery
class _StockLine extends StatelessWidget {
  final ProductModel p;
  final int added;
  const _StockLine({required this.p, required this.added});

  @override
  Widget build(BuildContext context) {
    Widget cell(String label, String value, Color color) => Expanded(
          child: Column(
            children: [
              Text(value, style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.w700, color: color)),
              Text(label, style: GoogleFonts.poppins(fontSize: 11, color: AppColors.textSecondary)),
            ],
          ),
        );
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(color: AppColors.surfaceMuted, borderRadius: BorderRadius.circular(12)),
      child: Row(
        children: [
          cell('Shelf', '${p.privateStock}', AppColors.textPrimary),
          cell('Reserved', '${p.reservedQuantity}', AppColors.reservedAmber),
          cell('Online now', '${p.publicStock}', AppColors.textPrimary),
          cell('Online after', '${onlineAfter(p, added > 0 ? added : 0)}', AppColors.stockGreen),
        ],
      ),
    );
  }
}
