// ══════════════════════════════════════════════════════════════
// Vendra App - Card entry bottom sheet
// Number (4-4-4-4 with brand), expiry MM/YY and CVC → validated →
// tokenized straight at the gateway → returns the single-use token and
// card summary. The card number never leaves this sheet except to the
// gateway: it is not logged, stored or sent to the Vendra API.
// In development (`features.testCards`) a "Test cards" helper fills in a
// sandbox card on tap.
//
//   final token = await showCardEntrySheet(context, actionLabel: 'Pay Rs. 500');
//   if (token != null) api.post(..., data: {'token': token.id});
// ══════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../config/app_theme.dart';
import '../models/payment_model.dart';
import '../services/app_config.dart';
import '../services/card_gateway.dart';
import '../utils/card_utils.dart';
import 'vendra_button.dart';

/// Shows the card form; resolves to the token, or null if dismissed.
/// [forPayout] words the sheet for receiving money (withdrawals) and lists
/// the payout test cards first.
Future<CardToken?> showCardEntrySheet(
  BuildContext context, {
  String title = 'Pay by card',
  String? subtitle,
  String actionLabel = 'Continue',
  bool forPayout = false,
  CardGateway? gateway,
}) {
  return showModalBottomSheet<CardToken>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (_) => CardEntrySheet(
      title: title,
      subtitle: subtitle,
      actionLabel: actionLabel,
      forPayout: forPayout,
      gateway: gateway,
    ),
  );
}

/// Brand mark for a card network (icon tinted per brand + short name)
class CardBrandBadge extends StatelessWidget {
  final String brand;
  final double size;
  const CardBrandBadge({super.key, required this.brand, this.size = 22});

  static Color colorFor(String brand) {
    switch (brand) {
      case 'visa':
        return const Color(0xFF1A1F71);
      case 'mastercard':
        return const Color(0xFFEB001B);
      case 'amex':
        return const Color(0xFF2E77BC);
      default:
        return AppColors.textLight;
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = colorFor(brand);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.credit_card, size: size, color: color),
        if (brand != 'unknown') ...[
          const SizedBox(width: 4),
          Text(
            CardUtils.brandLabel(brand).toUpperCase(),
            style: GoogleFonts.poppins(fontSize: size * 0.45, fontWeight: FontWeight.w700, color: color),
          ),
        ],
      ],
    );
  }
}

class CardEntrySheet extends StatefulWidget {
  final String title;
  final String? subtitle;
  final String actionLabel;
  final bool forPayout;
  final CardGateway? gateway;

  const CardEntrySheet({
    super.key,
    this.title = 'Pay by card',
    this.subtitle,
    this.actionLabel = 'Continue',
    this.forPayout = false,
    this.gateway,
  });

  @override
  State<CardEntrySheet> createState() => _CardEntrySheetState();
}

class _CardEntrySheetState extends State<CardEntrySheet> {
  final _formKey = GlobalKey<FormState>();
  final _number = TextEditingController();
  final _expiry = TextEditingController();
  final _cvc = TextEditingController();
  final _expiryFocus = FocusNode();
  final _cvcFocus = FocusNode();
  late final CardGateway _gateway = widget.gateway ?? CardGateway();

  String _brand = 'unknown';
  bool _submitting = false;
  String? _error;

  /// Sandbox cards (development only)
  TestCardList? _testCards;
  bool _testCardsFailed = false;

  bool get _showTestCards => AppConfig.current.features.testCards;

  @override
  void initState() {
    super.initState();
    _number.addListener(() {
      final brand = CardUtils.detectBrand(_number.text);
      if (brand != _brand) setState(() => _brand = brand);
    });
    if (_showTestCards) _loadTestCards();
  }

  Future<void> _loadTestCards() async {
    try {
      final list = await _gateway.testCards();
      if (mounted) setState(() => _testCards = list);
    } catch (_) {
      if (mounted) setState(() => _testCardsFailed = true);
    }
  }

  @override
  void dispose() {
    // Wipe the fields before releasing them
    _number.clear();
    _cvc.clear();
    _number.dispose();
    _expiry.dispose();
    _cvc.dispose();
    _expiryFocus.dispose();
    _cvcFocus.dispose();
    super.dispose();
  }

  void _fillTestCard(TestCard card) {
    final expYear = (DateTime.now().year + 3) % 100;
    setState(() {
      _number.text = card.formattedNumber;
      _expiry.text = '12/${expYear.toString().padLeft(2, '0')}';
      _cvc.text = '123';
      _error = null;
    });
  }

  Future<void> _submit() async {
    setState(() => _error = null);
    if (!_formKey.currentState!.validate()) return;
    final exp = CardUtils.parseExpiry(_expiry.text)!;
    setState(() => _submitting = true);
    try {
      final token = await _gateway.tokenize(
        number: CardUtils.digitsOnly(_number.text),
        expMonth: exp.month,
        expYear: exp.year,
        cvc: CardUtils.digitsOnly(_cvc.text),
      );
      if (mounted) Navigator.of(context).pop(token);
    } on CardGatewayException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  InputDecoration _decoration(String label, {String? hint, Widget? suffix, Widget? prefix}) => InputDecoration(
        labelText: label,
        hintText: hint,
        suffixIcon: suffix,
        prefixIcon: prefix,
        filled: true,
        fillColor: Colors.grey.shade50,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        counterText: '',
      );

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
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)),
                ),
              ),
              const SizedBox(height: 16),
              Text(widget.title, style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.w600)),
              if (widget.subtitle != null) ...[
                const SizedBox(height: 4),
                Text(widget.subtitle!, style: GoogleFonts.poppins(fontSize: 12, color: AppColors.textSecondary)),
              ],
              const SizedBox(height: 16),

              // ── Card number ──
              TextFormField(
                controller: _number,
                enabled: !_submitting,
                keyboardType: TextInputType.number,
                autofillHints: const [AutofillHints.creditCardNumber],
                inputFormatters: [_CardNumberFormatter()],
                textInputAction: TextInputAction.next,
                onFieldSubmitted: (_) => _expiryFocus.requestFocus(),
                style: GoogleFonts.poppins(fontSize: 15, letterSpacing: 1.2),
                decoration: _decoration(
                  'Card number',
                  hint: '1234 5678 9012 3456',
                  prefix: const Icon(Icons.credit_card_outlined, size: 20),
                  suffix: Padding(
                    padding: const EdgeInsets.only(right: 12),
                    child: CardBrandBadge(brand: _brand, size: 20),
                  ),
                ).copyWith(suffixIconConstraints: const BoxConstraints(minHeight: 24)),
                validator: (v) => CardUtils.validateNumber(v ?? ''),
              ),
              const SizedBox(height: 12),

              // ── Expiry + CVC ──
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _expiry,
                      focusNode: _expiryFocus,
                      enabled: !_submitting,
                      keyboardType: TextInputType.number,
                      autofillHints: const [AutofillHints.creditCardExpirationDate],
                      inputFormatters: [_ExpiryFormatter()],
                      textInputAction: TextInputAction.next,
                      onFieldSubmitted: (_) => _cvcFocus.requestFocus(),
                      style: GoogleFonts.poppins(fontSize: 15),
                      decoration: _decoration('Expiry', hint: 'MM/YY'),
                      validator: (v) => CardUtils.validateExpiry(v ?? ''),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _cvc,
                      focusNode: _cvcFocus,
                      enabled: !_submitting,
                      keyboardType: TextInputType.number,
                      autofillHints: const [AutofillHints.creditCardSecurityCode],
                      obscureText: true,
                      maxLength: _brand == 'amex' ? 4 : 3,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      textInputAction: TextInputAction.done,
                      onFieldSubmitted: (_) => _submit(),
                      style: GoogleFonts.poppins(fontSize: 15),
                      decoration: _decoration('CVC', hint: '123'),
                      validator: (v) => CardUtils.validateCvc(v ?? '', brand: _brand),
                    ),
                  ),
                ],
              ),

              if (_error != null) ...[
                const SizedBox(height: 12),
                _ErrorBox(message: _error!),
              ],

              const SizedBox(height: 12),
              Row(
                children: [
                  const Icon(Icons.lock_outline, size: 14, color: AppColors.textLight),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      widget.forPayout
                          ? 'Your card details go straight to our payment partner. Vendra only keeps the last 4 digits.'
                          : 'Your card details go straight to our payment partner, never to Vendra.',
                      style: GoogleFonts.poppins(fontSize: 11, color: AppColors.textLight),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              VendraButton(
                text: widget.actionLabel,
                icon: widget.forPayout ? Icons.north_east : Icons.lock_outline,
                isLoading: _submitting,
                onPressed: _submitting ? null : _submit,
              ),

              if (_showTestCards) ...[
                const SizedBox(height: 16),
                _testCardsHelper(),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// Development only: tap a sandbox card to fill the form
  Widget _testCardsHelper() {
    final list = _testCards;
    final cards = [...?list?.cards];
    if (widget.forPayout) {
      // Cards that mention payouts (succeed or bounce) are the useful ones here
      cards.sort((a, b) => (b.mentionsPayouts ? 1 : 0) - (a.mentionsPayouts ? 1 : 0));
    }
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFFFF8E1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.amber.shade200),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          dense: true,
          tilePadding: const EdgeInsets.symmetric(horizontal: 12),
          childrenPadding: const EdgeInsets.only(bottom: 8),
          leading: Icon(Icons.science_outlined, color: Colors.amber.shade800, size: 20),
          title: Text('Test cards',
              style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.amber.shade900)),
          subtitle: Text(
            [
              'Sandbox only · tap one to fill it in',
              if (list?.otp != null) 'code ${list!.otp}',
            ].join(' · '),
            style: GoogleFonts.poppins(fontSize: 11, color: Colors.amber.shade800),
          ),
          children: [
            if (list == null && !_testCardsFailed)
              const Padding(
                padding: EdgeInsets.all(12),
                child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
              )
            else if (_testCardsFailed || cards.isEmpty)
              Padding(
                padding: const EdgeInsets.all(12),
                child: Text("Couldn't load the test cards.",
                    style: GoogleFonts.poppins(fontSize: 12, color: AppColors.textSecondary)),
              )
            else
              for (final card in cards)
                InkWell(
                  onTap: _submitting ? null : () => _fillTestCard(card),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    child: Row(
                      children: [
                        SizedBox(width: 30, child: Icon(Icons.credit_card, size: 18, color: CardBrandBadge.colorFor(card.brand))),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${card.formattedNumber}${card.isDebit ? '  · debit' : ''}',
                                style: GoogleFonts.robotoMono(fontSize: 12, fontWeight: FontWeight.w600),
                              ),
                              Text(card.label, style: GoogleFonts.poppins(fontSize: 11, color: AppColors.textSecondary)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
          ],
        ),
      ),
    );
  }
}

class _ErrorBox extends StatelessWidget {
  final String message;
  const _ErrorBox({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.error.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.error.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, size: 18, color: AppColors.error),
          const SizedBox(width: 8),
          Expanded(child: Text(message, style: GoogleFonts.poppins(fontSize: 12, color: AppColors.error))),
        ],
      ),
    );
  }
}

/// "4242424242424242" → "4242 4242 4242 4242" while typing
class _CardNumberFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    final formatted = CardUtils.formatNumber(newValue.text);
    return TextEditingValue(text: formatted, selection: TextSelection.collapsed(offset: formatted.length));
  }
}

/// "1230" → "12/30" while typing (the slash appears with the third digit,
/// so backspace never gets stuck on it)
class _ExpiryFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    final formatted = CardUtils.formatExpiry(newValue.text);
    return TextEditingValue(text: formatted, selection: TextSelection.collapsed(offset: formatted.length));
  }
}
