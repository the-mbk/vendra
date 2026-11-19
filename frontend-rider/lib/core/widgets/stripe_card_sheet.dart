// ══════════════════════════════════════════════════════════════
// Vendra App - Stripe card bottom sheet (payments.provider == 'stripe')
// Stripe's own card field (number, expiry, CVC) → PaymentMethod (pm_…)
// created on Stripe's servers → returned as a CardToken whose id is sent to
// the Vendra API as `token`. The card number never reaches Vendra: on the web
// the field is a Stripe.js iframe, on Android/iOS a native Stripe view.
// In development (`features.testCards`) Stripe's test cards are listed under
// the field; tapping one copies its number (Stripe's field can't be filled
// in by the app).
//
//   final token = await showStripeCardSheet(context, actionLabel: 'Pay Rs. 500');
//   if (token != null) api.post(..., data: {'token': token.id});
// ══════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_stripe/flutter_stripe.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../config/app_theme.dart';
import '../models/payment_model.dart';
import '../services/app_config.dart';
import '../services/card_gateway.dart';
import '../services/stripe_payments.dart';
import 'card_entry_sheet.dart';
import 'vendra_button.dart';

/// Shows Stripe's card field; resolves to the PaymentMethod, or null if dismissed.
/// Call [StripePayments.ensureReady] first.
Future<CardToken?> showStripeCardSheet(
  BuildContext context, {
  String title = 'Pay by card',
  String? subtitle,
  String actionLabel = 'Continue',
}) {
  return showModalBottomSheet<CardToken>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (_) => StripeCardSheet(title: title, subtitle: subtitle, actionLabel: actionLabel),
  );
}

class StripeCardSheet extends StatefulWidget {
  final String title;
  final String? subtitle;
  final String actionLabel;

  /// For tests: replaces Stripe's card field (which needs the Stripe SDK). It
  /// reports whether the card is complete through the callback.
  final Widget Function(ValueChanged<bool> onComplete)? cardFieldBuilder;

  /// For tests: replaces [StripePayments.createPaymentMethod]
  final Future<CardToken> Function()? createPaymentMethod;

  const StripeCardSheet({
    super.key,
    this.title = 'Pay by card',
    this.subtitle,
    this.actionLabel = 'Continue',
    this.cardFieldBuilder,
    this.createPaymentMethod,
  });

  @override
  State<StripeCardSheet> createState() => _StripeCardSheetState();
}

class _StripeCardSheetState extends State<StripeCardSheet> {
  bool _complete = false;
  bool _submitting = false;
  String? _error;

  /// The test card whose number was just copied
  String? _copied;

  bool get _showTestCards => AppConfig.current.features.testCards;

  void _onComplete(bool complete) {
    if (complete != _complete || _error != null) {
      setState(() {
        _complete = complete;
        _error = null;
      });
    }
  }

  Future<void> _submit() async {
    if (!_complete || _submitting) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final token = await (widget.createPaymentMethod ?? StripePayments.createPaymentMethod)();
      if (mounted) Navigator.of(context).pop(token);
    } on CardGatewayException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (mounted) setState(() => _error = StripePayments.toException(e).message);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _copy(String number) async {
    await Clipboard.setData(ClipboardData(text: number.replaceAll(' ', '')));
    if (mounted) setState(() => _copied = number);
  }

  Widget _cardField() {
    if (widget.cardFieldBuilder != null) return widget.cardFieldBuilder!(_onComplete);
    return CardField(
      enablePostalCode: false,
      disabled: _submitting,
      style: TextStyle(fontSize: 16, color: AppColors.textPrimary),
      decoration: InputDecoration(
        labelText: 'Card details',
        filled: true,
        fillColor: AppColors.surfaceMuted,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      ),
      onCardChanged: (details) => _onComplete(details?.complete ?? false),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 12,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(color: AppColors.hairline, borderRadius: BorderRadius.circular(2)),
              ),
            ),
            const SizedBox(height: 16),
            Text(widget.title, style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.w600)),
            if (widget.subtitle != null) ...[
              const SizedBox(height: 4),
              Text(widget.subtitle!, style: GoogleFonts.poppins(fontSize: 12, color: AppColors.textSecondary)),
            ],
            const SizedBox(height: 16),

            // ── Stripe's card field ──
            _cardField(),

            if (_showTestCards) ...[
              const SizedBox(height: 10),
              _testCardsHint(),
            ],

            if (_error != null) ...[
              const SizedBox(height: 12),
              CardErrorBox(message: _error!),
            ],

            const SizedBox(height: 12),
            Row(
              children: [
                Icon(Icons.lock_outline, size: 14, color: AppColors.textLight),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Your card details go straight to Stripe, our payment partner, never to Vendra.',
                    style: GoogleFonts.poppins(fontSize: 11, color: AppColors.textLight),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            VendraButton(
              text: widget.actionLabel,
              icon: Icons.lock_outline,
              isLoading: _submitting,
              onPressed: _complete && !_submitting ? _submit : null,
            ),
          ],
        ),
      ),
    );
  }

  /// Development only: Stripe's test cards, tap to copy the number
  Widget _testCardsHint() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
      decoration: BoxDecoration(
        color: AppColors.warningSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.amber.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.science_outlined, color: Colors.amber.shade800, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text('Stripe test cards',
                    style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.amber.shade900)),
              ),
            ],
          ),
          Text(
            'Test mode only · any future expiry and any CVC · tap one to copy it',
            style: GoogleFonts.poppins(fontSize: 11, color: Colors.amber.shade800),
          ),
          const SizedBox(height: 4),
          for (final card in StripePayments.testCards)
            InkWell(
              onTap: _submitting ? null : () => _copy(card.number),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Row(
                  children: [
                    Icon(_copied == card.number ? Icons.check : Icons.copy_rounded,
                        size: 16, color: _copied == card.number ? AppColors.success : AppColors.textSecondary),
                    const SizedBox(width: 10),
                    Text(card.number, style: GoogleFonts.robotoMono(fontSize: 12, fontWeight: FontWeight.w600)),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(card.label,
                          style: GoogleFonts.poppins(fontSize: 11, color: AppColors.textSecondary),
                          overflow: TextOverflow.ellipsis),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
