// ══════════════════════════════════════════════════════════════
// Vendra Vendor App - Receipt settings (store owner)
// GET / PUT /api/vendor/receipt-settings
//   { receiptHeader, receiptFooter, paymentAccount, paymentAccountTitle }
// The header and footer are printed on every walk-in slip. With a payment
// account (IBAN / Raast ID / wallet number) the slip carries a
// scan-to-pay QR for the sale's amount. An empty field clears it.
// A live preview shows the slip as it will print.
// ══════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:vendra_vendor/vendra_core.dart';

import '../../auth/bloc/auth_bloc.dart';
import '../../auth/bloc/auth_state.dart';
import '../models/pos_receipt.dart';
import '../widgets/receipt_slip.dart';

class ReceiptSettingsScreen extends StatefulWidget {
  const ReceiptSettingsScreen({super.key});

  @override
  State<ReceiptSettingsScreen> createState() => _ReceiptSettingsScreenState();
}

class _ReceiptSettingsScreenState extends State<ReceiptSettingsScreen> {
  final _api = ApiService();
  final _formKey = GlobalKey<FormState>();
  final _header = TextEditingController();
  final _footer = TextEditingController();
  final _account = TextEditingController();
  final _title = TextEditingController();

  bool _loading = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    for (final c in [_header, _footer, _account, _title]) {
      c.addListener(_onChanged);
    }
    _load();
  }

  @override
  void dispose() {
    for (final c in [_header, _footer, _account, _title]) {
      c.dispose();
    }
    super.dispose();
  }

  void _onChanged() => setState(() {}); // refresh the preview

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await _api.get(ApiConfig.receiptSettings);
      final d = Map<String, dynamic>.from(res.data['data'] as Map);
      _header.text = d['receiptHeader'] ?? '';
      _footer.text = d['receiptFooter'] ?? '';
      _account.text = d['paymentAccount'] ?? '';
      _title.text = d['paymentAccountTitle'] ?? '';
      if (mounted) setState(() => _loading = false);
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = ApiService.getErrorMessage(e);
        });
      }
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final res = await _api.put(ApiConfig.receiptSettings, data: {
        'receiptHeader': _header.text.trim(),
        'receiptFooter': _footer.text.trim(),
        'paymentAccount': _account.text.trim(),
        'paymentAccountTitle': _title.text.trim(),
      });
      messenger.showSnackBar(SnackBar(
        content: Text(res.data['message'] ?? 'Receipt settings saved.'),
        backgroundColor: AppColors.success,
        behavior: SnackBarBehavior.floating,
      ));
    } catch (e) {
      // 403 STAFF_FORBIDDEN / STAFF_NOT_ALLOWED for staff, 400 for a too-long field
      messenger.showSnackBar(SnackBar(
        content: Text(ApiService.getErrorMessage(e)),
        backgroundColor: AppColors.error,
        behavior: SnackBarBehavior.floating,
      ));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// A sample slip with the fields as typed
  PosReceipt _preview(UserModel? user) {
    final account = _account.text.trim();
    final title = _title.text.trim().isEmpty ? (user?.storeName ?? 'My Store') : _title.text.trim();
    const sample = [
      ReceiptLine(name: 'Basmati Rice 5kg', quantity: 1, unitPrice: 1850),
      ReceiptLine(name: 'Milk 1L', quantity: 2, unitPrice: 220),
    ];
    return PosReceipt(
      receiptNumber: 'POS-000000',
      storeName: user?.storeName ?? 'My Store',
      storeAddress: user?.storeAddress,
      storePhone: user?.phone,
      header: _header.text.trim().isEmpty ? null : _header.text.trim(),
      footer: _footer.text.trim().isEmpty ? null : _footer.text.trim(),
      saleId: 0,
      total: 2290,
      createdAt: DateTime.now(),
      cashier: user?.fullName,
      items: sample,
      paymentQr: account.isEmpty
          ? null
          : ReceiptPaymentQr(
              account: account,
              title: title,
              payload: 'vendra-pay:${Uri.encodeComponent(account)}?name=${Uri.encodeComponent(title)}&amount=2290.00&ref=POS-0',
            ),
    );
  }

  String? _maxLength(String? v, int max) => (v?.trim().length ?? 0) > max ? 'At most $max characters' : null;

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthBloc>().state;
    final user = auth is Authenticated ? auth.user : null;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: Text('Receipt settings', style: GoogleFonts.poppins(fontWeight: FontWeight.w600))),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_error!, textAlign: TextAlign.center, style: GoogleFonts.poppins(color: AppColors.textSecondary)),
                        const SizedBox(height: 12),
                        OutlinedButton(onPressed: _load, child: const Text('Retry')),
                      ],
                    ),
                  ),
                )
              : Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 640),
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(20),
                      child: Form(
                        key: _formKey,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _section('Printed on every slip'),
                            VendraTextField(
                              label: 'Header',
                              hint: 'e.g. Open 8am–11pm · Free home delivery',
                              controller: _header,
                              prefixIcon: Icons.vertical_align_top,
                              validator: (v) => _maxLength(v, 200),
                            ),
                            const SizedBox(height: 14),
                            VendraTextField(
                              label: 'Footer',
                              hint: 'Thank you for shopping with us!',
                              controller: _footer,
                              prefixIcon: Icons.vertical_align_bottom,
                              validator: (v) => _maxLength(v, 200),
                            ),
                            const SizedBox(height: 22),
                            _section('Scan-to-pay QR'),
                            Text(
                              'Customers scan the QR on the slip to pay the exact amount. Leave the account empty to print slips without a QR.',
                              style: GoogleFonts.poppins(fontSize: 12, color: AppColors.textSecondary),
                            ),
                            const SizedBox(height: 10),
                            VendraTextField(
                              label: 'Payment account',
                              hint: 'IBAN, Raast ID or wallet number',
                              controller: _account,
                              prefixIcon: Icons.account_balance_outlined,
                              validator: (v) => _maxLength(v, 60),
                            ),
                            const SizedBox(height: 14),
                            VendraTextField(
                              label: 'Account title',
                              hint: user?.storeName ?? 'Name on the account',
                              controller: _title,
                              prefixIcon: Icons.badge_outlined,
                              validator: (v) => _maxLength(v, 100),
                            ),
                            const SizedBox(height: 20),
                            VendraButton(text: 'Save settings', icon: Icons.check, isLoading: _saving, onPressed: _save),
                            const SizedBox(height: 24),
                            _section('Preview'),
                            Container(
                              padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
                              decoration: BoxDecoration(
                                color: const Color(0xFFE9EBEE),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: ReceiptSlip(receipt: _preview(user)),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
    );
  }

  Widget _section(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(text, style: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
      );
}
