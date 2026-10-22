// ══════════════════════════════════════════════════════════════
// Vendra App - One-time password dialog (3-D Secure)
// Shown when a card payment comes back `requires_action`. The code goes
// straight to the gateway (POST /v1/payment_intents/:id/verify); a wrong
// code keeps the dialog open with the attempts left, and the third wrong
// code fails the payment. Afterwards the CALLER refreshes the payment
// (POST /api/payments/:id/refresh) to learn the outcome.
// The sandbox code is shown only when a development backend sent a hint.
// ══════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../config/app_theme.dart';
import '../models/payment_model.dart';
import '../services/card_gateway.dart';

/// Resolves to true once the gateway reached a final answer (approved, or
/// failed after too many wrong codes) — refresh the payment then. False if
/// the user cancelled (the payment stays unconfirmed and is not charged).
Future<bool> showOtpDialog(BuildContext context, {required PaymentModel payment, CardGateway? gateway}) async {
  final done = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) => OtpDialog(payment: payment, gateway: gateway),
  );
  return done ?? false;
}

class OtpDialog extends StatefulWidget {
  final PaymentModel payment;
  final CardGateway? gateway;

  const OtpDialog({super.key, required this.payment, this.gateway});

  @override
  State<OtpDialog> createState() => _OtpDialogState();
}

class _OtpDialogState extends State<OtpDialog> {
  final _code = TextEditingController();
  late final CardGateway _gateway = widget.gateway ?? CardGateway();

  bool _verifying = false;
  String? _error;
  late int? _attemptsLeft = widget.payment.nextAction?.attemptsLeft;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _verify() async {
    final otp = _code.text.trim();
    if (otp.length < 4) {
      setState(() => _error = 'Enter the code you received');
      return;
    }
    final intentId = widget.payment.gatewayIntentId;
    if (intentId == null) {
      Navigator.of(context).pop(true);
      return;
    }
    setState(() {
      _verifying = true;
      _error = null;
    });
    try {
      await _gateway.verifyOtp(intentId, otp);
      if (mounted) Navigator.of(context).pop(true);
    } on CardGatewayException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _code.clear();
        if (e.isIncorrectOtp) {
          // "That code is incorrect. 2 attempts left."
          final m = RegExp(r'(\d+) attempt').firstMatch(e.message);
          _attemptsLeft = m != null ? int.parse(m.group(1)!) : (_attemptsLeft ?? 1) - 1;
        }
      });
      // The payment is no longer waiting for a code (expired/cancelled): let the caller refresh
      if (e.code == 'resource_missing') Navigator.of(context).pop(true);
    } finally {
      if (mounted) setState(() => _verifying = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.payment;
    final hint = p.nextAction?.hint;
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Row(
        children: [
          const Icon(Icons.verified_user_outlined, color: AppColors.secondary),
          const SizedBox(width: 8),
          Expanded(child: Text('Confirm payment', style: GoogleFonts.poppins(fontWeight: FontWeight.w600))),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Your bank wants to confirm Rs. ${p.amount.toStringAsFixed(0)} with ${p.cardLabel}. '
              'Enter the one-time password it sent you.',
              style: GoogleFonts.poppins(fontSize: 13, color: AppColors.textSecondary),
            ),
            if (hint != null && hint.isNotEmpty) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF8E1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.amber.shade200),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.science_outlined, size: 16, color: Colors.amber.shade800),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(hint, style: GoogleFonts.poppins(fontSize: 12, color: Colors.amber.shade900)),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 14),
            TextField(
              controller: _code,
              autofocus: true,
              enabled: !_verifying,
              keyboardType: TextInputType.number,
              autofillHints: const [AutofillHints.oneTimeCode],
              inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(8)],
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(fontSize: 22, letterSpacing: 8, fontWeight: FontWeight.w600),
              onSubmitted: (_) => _verify(),
              decoration: InputDecoration(
                hintText: '••••••',
                errorText: _error,
                errorMaxLines: 3,
                filled: true,
                fillColor: Colors.grey.shade50,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
            if (_attemptsLeft != null && _error == null) ...[
              const SizedBox(height: 6),
              Text(
                '$_attemptsLeft attempt${_attemptsLeft == 1 ? '' : 's'} left',
                style: GoogleFonts.poppins(fontSize: 11, color: AppColors.textLight),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _verifying ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _verifying ? null : _verify,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
          child: _verifying
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Text('Confirm'),
        ),
      ],
    );
  }
}
