// ══════════════════════════════════════════════════════════════
// Vendra Vendor App - Self-pickup handover
// PUT /api/vendor/orders/:id/deliver { otp } with the customer's 4-digit
// handover code → delivered (the dispute window starts).
//   400 OTP_REQUIRED   no code sent
//   422 WRONG_OTP      { attemptsLeft } — the dialog stays open
//   429 OTP_LOCKED     too many wrong codes; try again later
// Orders that don't need a code (otp_required false) get a plain confirm;
// if the server still asks for one (OTP_REQUIRED) the code field appears.
// Resolves to true once the order was handed over.
// ══════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:vendra_vendor/vendra_core.dart';

Future<bool> showHandoverDialog(BuildContext context, OrderModel order) async {
  final done = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) => HandoverCodeDialog(order: order),
  );
  return done ?? false;
}

class HandoverCodeDialog extends StatefulWidget {
  final OrderModel order;
  const HandoverCodeDialog({super.key, required this.order});

  @override
  State<HandoverCodeDialog> createState() => _HandoverCodeDialogState();
}

class _HandoverCodeDialogState extends State<HandoverCodeDialog> {
  final _code = TextEditingController();
  bool _busy = false;
  bool _locked = false;
  String? _error;

  late bool _needsCode = widget.order.otpRequired;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _confirm() async {
    final otp = _code.text.trim();
    if (_needsCode && otp.length != 4) {
      setState(() => _error = "Enter the customer's 4-digit code");
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ApiService().put(ApiConfig.deliverOrder(widget.order.id), data: {if (otp.isNotEmpty) 'otp': otp});
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      final code = ApiService.getErrorCode(e);
      final data = ApiService.getErrorData(e);
      String message = ApiService.getErrorMessage(e);
      if (code == 'WRONG_OTP' && data?['attemptsLeft'] != null) {
        final left = toInt(data!['attemptsLeft']);
        message = left > 0
            ? 'Wrong code. $left attempt${left == 1 ? '' : 's'} left.'
            : 'Wrong code. The handover is locked for now — try again later.';
        if (left == 0) _locked = true;
      }
      if (code == 'OTP_LOCKED') _locked = true;
      setState(() {
        if (code == 'OTP_REQUIRED') _needsCode = true;
        _busy = false;
        _error = message;
        if (code == 'WRONG_OTP') _code.clear();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final order = widget.order;
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      icon: Icon(_needsCode ? Icons.pin_outlined : Icons.done_all, color: AppColors.success, size: 32),
      title: Text('Hand over #ORD-${order.id.toString().padLeft(3, '0')}',
          textAlign: TextAlign.center, style: GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 18)),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _needsCode
                  ? 'Ask ${order.customerName ?? 'the customer'} for the 4-digit handover code shown in their Vendra app.'
                  : 'Confirm ${order.customerName ?? 'the customer'} has collected this order.',
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(fontSize: 13, color: AppColors.textSecondary),
            ),
            if (_needsCode) ...[
              const SizedBox(height: 14),
              TextField(
                controller: _code,
                autofocus: true,
                enabled: !_busy && !_locked,
                textAlign: TextAlign.center,
                keyboardType: TextInputType.number,
                maxLength: 4,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                onSubmitted: (_) => _confirm(),
                style: GoogleFonts.poppins(fontSize: 26, fontWeight: FontWeight.w700, letterSpacing: 12),
                decoration: const InputDecoration(counterText: '', hintText: '••••'),
              ),
            ],
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(_error!,
                    textAlign: TextAlign.center,
                    style: GoogleFonts.poppins(fontSize: 12, color: AppColors.error, fontWeight: FontWeight.w500)),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(false),
          child: Text(_locked ? 'Close' : 'Cancel'),
        ),
        if (!_locked)
          ElevatedButton(
            onPressed: _busy ? null : _confirm,
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.success, foregroundColor: Colors.white),
            child: _busy
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Text('Hand over'),
          ),
      ],
    );
  }
}
