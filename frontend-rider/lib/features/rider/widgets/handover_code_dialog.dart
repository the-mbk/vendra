// ══════════════════════════════════════════════════════════════
// Vendra Rider App - Handover code dialog (anti GPS-spoofing)
// "Ask the customer for their delivery code": four digit boxes on the
// numeric keyboard, then Confirm. A wrong code shows the attempts left;
// after five the handover is locked and the dialog says until when.
// The DeliveryBloc decides when it opens and closes (awaitingCode).
// Customer unavailable leaves the code entry for the photo report.
// ══════════════════════════════════════════════════════════════

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:vendra_rider/vendra_core.dart';

import '../bloc/delivery_bloc.dart';
import '../models/handover_code.dart';

/// Shows the dialog bound to [bloc]. The screen closes it (Navigator.pop)
/// once the bloc stops awaiting the code; Cancel and Back only tell the bloc.
/// [onUnavailable] runs when the rider reports the customer unavailable (the
/// code entry is cancelled first).
Future<void> showHandoverCodeDialog(BuildContext context, DeliveryBloc bloc, {required VoidCallback onUnavailable}) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => BlocProvider<DeliveryBloc>.value(
      value: bloc,
      child: BlocBuilder<DeliveryBloc, DeliveryState>(
        builder: (context, state) => PopScope(
          canPop: false,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop && !state.busy) bloc.add(DeliveryCodeCancelled());
          },
          child: HandoverCodeForm(
            busy: state.busy,
            feedback: state.codeFeedback,
            onSubmit: (code) => bloc.add(DeliveryCodeSubmitted(code)),
            onCancel: () => bloc.add(DeliveryCodeCancelled()),
            onUnavailable: () {
              onUnavailable();
              bloc.add(DeliveryCodeCancelled());
            },
          ),
        ),
      ),
    ),
  );
}

final _timeFmt = DateFormat('h:mm a');

class HandoverCodeForm extends StatefulWidget {
  final bool busy;
  final HandoverCodeFeedback? feedback;
  final ValueChanged<String> onSubmit;
  final VoidCallback onCancel;
  final VoidCallback onUnavailable;

  const HandoverCodeForm({
    super.key,
    required this.busy,
    required this.onSubmit,
    required this.onCancel,
    required this.onUnavailable,
    this.feedback,
  });

  @override
  State<HandoverCodeForm> createState() => _HandoverCodeFormState();
}

class _HandoverCodeFormState extends State<HandoverCodeForm> {
  final _code = TextEditingController();
  final _focus = FocusNode();

  /// Rebuilds while locked so the form unlocks itself when the time is up
  Timer? _lockTicker;

  @override
  void initState() {
    super.initState();
    _code.addListener(() => setState(() {}));
    _syncLockTicker();
  }

  @override
  void didUpdateWidget(HandoverCodeForm old) {
    super.didUpdateWidget(old);
    if (widget.feedback?.id != old.feedback?.id && widget.feedback != null) {
      // Refused: clear the boxes for the next try
      _code.clear();
      if (!widget.feedback!.isLocked()) _focus.requestFocus();
    }
    _syncLockTicker();
  }

  void _syncLockTicker() {
    final locked = widget.feedback?.isLocked() ?? false;
    if (locked && _lockTicker == null) {
      _lockTicker = Timer.periodic(const Duration(seconds: 5), (_) {
        if (!mounted) return;
        setState(() {});
        if (!(widget.feedback?.isLocked() ?? false)) {
          _lockTicker?.cancel();
          _lockTicker = null;
        }
      });
    } else if (!locked) {
      _lockTicker?.cancel();
      _lockTicker = null;
    }
  }

  @override
  void dispose() {
    _lockTicker?.cancel();
    _code.dispose();
    _focus.dispose();
    super.dispose();
  }

  bool get _locked => widget.feedback?.isLocked() ?? false;
  bool get _complete => _code.text.length == handoverCodeLength;

  void _submit() {
    if (!_complete || widget.busy || _locked) return;
    widget.onSubmit(_code.text);
  }

  @override
  Widget build(BuildContext context) {
    final feedback = widget.feedback;
    final locked = _locked;
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Row(
        children: [
          Icon(Icons.pin_outlined, color: AppColors.secondary),
          const SizedBox(width: 8),
          Expanded(child: Text('Delivery code', style: GoogleFonts.poppins(fontWeight: FontWeight.w600))),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Ask the customer for their delivery code. It is shown in their app; '
              'enter it only once you have handed over the order.',
              style: GoogleFonts.poppins(fontSize: 13, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 16),
            _CodeBoxes(
              controller: _code,
              focusNode: _focus,
              enabled: !widget.busy && !locked,
              onCompleted: _submit,
            ),
            if (locked) ...[
              const SizedBox(height: 12),
              _notice(
                Icons.lock_clock,
                AppColors.error,
                'Too many wrong codes. Delivery is locked until ${_timeFmt.format(feedback!.lockedUntil!)}.',
              ),
            ] else if (feedback != null) ...[
              const SizedBox(height: 12),
              _notice(
                Icons.error_outline,
                AppColors.error,
                feedback.attemptsLeft != null
                    ? 'Wrong code. ${feedback.attemptsLeft} attempt${feedback.attemptsLeft == 1 ? '' : 's'} left.'
                    : feedback.message,
              ),
            ],
            const SizedBox(height: 16),
            const Divider(height: 1),
            const SizedBox(height: 4),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: widget.busy ? null : widget.onUnavailable,
                style: TextButton.styleFrom(foregroundColor: AppColors.error, padding: EdgeInsets.zero),
                icon: const Icon(Icons.no_accounts_outlined, size: 18),
                label: const Text('Customer unavailable / issue at handover'),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: widget.busy ? null : widget.onCancel, child: const Text('Cancel')),
        ElevatedButton(
          onPressed: widget.busy || locked || !_complete ? null : _submit,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
          child: widget.busy
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Text('Confirm delivery'),
        ),
      ],
    );
  }

  Widget _notice(IconData icon, Color color, String text) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 6),
        Expanded(child: Text(text, style: GoogleFonts.poppins(fontSize: 12, color: color))),
      ],
    );
  }
}

/// Four boxes over one hidden numeric field (so paste, autofill and
/// backspace behave like a normal text field)
class _CodeBoxes extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final bool enabled;
  final VoidCallback onCompleted;

  const _CodeBoxes({
    required this.controller,
    required this.focusNode,
    required this.enabled,
    required this.onCompleted,
  });

  @override
  Widget build(BuildContext context) {
    final text = controller.text;
    return Stack(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (var i = 0; i < handoverCodeLength; i++)
              Flexible(
                child: Container(
                  constraints: const BoxConstraints(maxWidth: 56),
                  height: 60,
                  margin: const EdgeInsets.symmetric(horizontal: 5),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: enabled ? AppColors.surfaceMuted : AppColors.surfaceMuted,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: enabled && i == text.length.clamp(0, handoverCodeLength - 1)
                          ? AppColors.primary
                          : AppColors.hairline,
                      width: enabled && i == text.length.clamp(0, handoverCodeLength - 1) ? 2 : 1,
                    ),
                  ),
                  child: Text(i < text.length ? text[i] : '',
                      style: GoogleFonts.poppins(fontSize: 26, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                ),
              ),
          ],
        ),
        Positioned.fill(
          child: Opacity(
            opacity: 0,
            child: TextField(
              controller: controller,
              focusNode: focusNode,
              enabled: enabled,
              autofocus: true,
              keyboardType: TextInputType.number,
              autofillHints: const [AutofillHints.oneTimeCode],
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(handoverCodeLength),
              ],
              showCursor: false,
              enableInteractiveSelection: false,
              decoration: const InputDecoration(border: InputBorder.none, counterText: ''),
              onSubmitted: (_) => onCompleted(),
            ),
          ),
        ),
      ],
    );
  }
}
