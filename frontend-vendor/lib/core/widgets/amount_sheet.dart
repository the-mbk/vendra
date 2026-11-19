// ══════════════════════════════════════════════════════════════
// Vendra App - Amount bottom sheet
// Asks for a rupee amount within [min, max] (quick-pick chips + custom
// field). Used before card top-ups and withdrawals. [note] adds a live line
// under the field for the amount typed so far (e.g. the converted amount of a
// Stripe withdrawal); [footer] goes under the button.
//
//   final amount = await showAmountSheet(context, title: 'Add money', min: 100, max: 500000);
// ══════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../config/app_theme.dart';
import 'vendra_button.dart';
import '../models/json_utils.dart';

export '../models/json_utils.dart' show formatRupees;


/// Error text for an entered amount, or null when it is valid
String? validateAmount(String input, {required double min, required double max}) {
  final text = input.trim().replaceAll(',', '');
  if (text.isEmpty) return 'Enter an amount';
  final value = double.tryParse(text);
  if (value == null || value <= 0) return 'Enter a valid amount';
  if (RegExp(r'\.\d{3,}$').hasMatch(text)) return 'At most two decimal places';
  if (value < min) return 'The minimum is ${formatRupees(min)}';
  if (value > max) return 'The maximum is ${formatRupees(max)}';
  return null;
}

/// Resolves to the chosen amount, or null if dismissed
Future<double?> showAmountSheet(
  BuildContext context, {
  required String title,
  String? subtitle,
  required double min,
  required double max,
  List<double> quickAmounts = const [],
  String actionLabel = 'Continue',
  double? initial,
  String? Function(double amount)? note,
  Widget? footer,
}) {
  return showModalBottomSheet<double>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (_) => _AmountSheet(
      title: title,
      subtitle: subtitle,
      min: min,
      max: max,
      quickAmounts: quickAmounts.where((a) => a >= min && a <= max).toList(),
      actionLabel: actionLabel,
      initial: initial,
      note: note,
      footer: footer,
    ),
  );
}

class _AmountSheet extends StatefulWidget {
  final String title;
  final String? subtitle;
  final double min;
  final double max;
  final List<double> quickAmounts;
  final String actionLabel;
  final double? initial;
  final String? Function(double amount)? note;
  final Widget? footer;

  const _AmountSheet({
    required this.title,
    this.subtitle,
    required this.min,
    required this.max,
    required this.quickAmounts,
    required this.actionLabel,
    this.initial,
    this.note,
    this.footer,
  });

  @override
  State<_AmountSheet> createState() => _AmountSheetState();
}

class _AmountSheetState extends State<_AmountSheet> {
  final _formKey = GlobalKey<FormState>();
  late final _amount = TextEditingController(
    text: widget.initial == null ? '' : widget.initial!.toStringAsFixed(widget.initial! % 1 == 0 ? 0 : 2),
  );

  @override
  void initState() {
    super.initState();
    if (widget.note != null) _amount.addListener(_redraw);
  }

  void _redraw() => setState(() {});

  @override
  void dispose() {
    _amount.removeListener(_redraw);
    _amount.dispose();
    super.dispose();
  }

  /// The note for a valid amount typed so far
  String? get _noteText {
    final note = widget.note;
    if (note == null || validateAmount(_amount.text, min: widget.min, max: widget.max) != null) return null;
    return note(double.parse(_amount.text.trim().replaceAll(',', '')));
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.of(context).pop(double.parse(_amount.text.trim().replaceAll(',', '')));
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(left: 20, right: 20, top: 12, bottom: MediaQuery.of(context).viewInsets.bottom + 20),
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
              TextFormField(
                controller: _amount,
                autofocus: true,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
                style: GoogleFonts.poppins(fontSize: 20, fontWeight: FontWeight.w600),
                onFieldSubmitted: (_) => _submit(),
                decoration: InputDecoration(
                  prefixText: 'Rs. ',
                  hintText: '0',
                  helperText: '${formatRupees(widget.min)} – ${formatRupees(widget.max)}',
                  filled: true,
                  fillColor: AppColors.surfaceMuted,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
                validator: (v) => validateAmount(v ?? '', min: widget.min, max: widget.max),
              ),
              if (_noteText != null) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(Icons.currency_exchange, size: 16, color: AppColors.secondary),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(_noteText!,
                          style: GoogleFonts.poppins(
                              fontSize: 13, fontWeight: FontWeight.w500, color: AppColors.secondary)),
                    ),
                  ],
                ),
              ],
              if (widget.quickAmounts.isNotEmpty) ...[
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final a in widget.quickAmounts)
                      ActionChip(
                        label: Text(formatRupees(a), style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w500)),
                        onPressed: () => setState(() => _amount.text = a.toStringAsFixed(a % 1 == 0 ? 0 : 2)),
                        backgroundColor: AppColors.secondary.withValues(alpha: 0.06),
                        side: BorderSide(color: AppColors.secondary.withValues(alpha: 0.3)),
                      ),
                  ],
                ),
              ],
              const SizedBox(height: 20),
              VendraButton(text: widget.actionLabel, icon: Icons.arrow_forward, onPressed: _submit),
              if (widget.footer != null) ...[
                const SizedBox(height: 8),
                Center(child: widget.footer!),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
