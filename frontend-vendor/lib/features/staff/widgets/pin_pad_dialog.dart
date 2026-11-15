// ══════════════════════════════════════════════════════════════
// Vendra Vendor App - PIN pad for "Switch user"
// POST /api/vendor/staff/switch { staffId, pin } → the staff token.
//   401 WRONG_PIN   { attemptsLeft } — the pad clears and says how many are left
//   429 PIN_LOCKED  five wrong PINs lock that person for 5 minutes
// Pops with the token on success (null if cancelled). Typing on a hardware
// keyboard works too (digits, Backspace, Enter).
// ══════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:vendra_vendor/vendra_core.dart';

import '../models/pin_buffer.dart';
import '../models/staff_member.dart';
import '../services/staff_api.dart';

class PinPadDialog extends StatefulWidget {
  final StaffMember member;
  final StaffApi? api;

  const PinPadDialog({super.key, required this.member, this.api});

  @override
  State<PinPadDialog> createState() => _PinPadDialogState();
}

class _PinPadDialogState extends State<PinPadDialog> {
  late final StaffApi _api = widget.api ?? StaffApi();
  final PinBuffer _pin = PinBuffer();
  final FocusNode _focus = FocusNode();

  bool _submitting = false;
  bool _locked = false;
  String? _error;

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  bool get _enabled => !_submitting && !_locked;

  void _type(String digit) {
    if (!_enabled) return;
    setState(() {
      _error = null;
      _pin.add(digit);
    });
    // Six digits is the longest PIN — no need to press OK
    if (_pin.isFull) _submit();
  }

  void _backspace() {
    if (!_enabled) return;
    setState(() => _pin.backspace());
  }

  Future<void> _submit() async {
    if (!_enabled || !_pin.canSubmit) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final token = await _api.switchTo(widget.member.id, _pin.value);
      if (mounted) Navigator.of(context).pop(token);
    } catch (e) {
      if (!mounted) return;
      final code = ApiService.getErrorCode(e);
      setState(() {
        _submitting = false;
        _pin.clear();
        // e.g. "Wrong PIN. 3 attempt(s) left." / "Too many wrong PINs. Try again in 5 min…"
        _error = ApiService.getErrorMessage(e);
        _locked = code == 'PIN_LOCKED' ||
            (code == 'WRONG_PIN' && toInt(ApiService.getErrorData(e)?['attemptsLeft'], 1) == 0);
      });
    }
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final ch = event.character;
    if (ch != null && RegExp(r'^\d$').hasMatch(ch)) {
      _type(ch);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.backspace) {
      _backspace();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.enter || event.logicalKey == LogicalKeyboardKey.numpadEnter) {
      _submit();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final role = widget.member.roleInfo;
    return Focus(
      focusNode: _focus,
      autofocus: true,
      onKeyEvent: _onKey,
      child: Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 340),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircleAvatar(
                  radius: 26,
                  backgroundColor: role.color.withValues(alpha: 0.12),
                  child: Icon(role.icon, color: role.color),
                ),
                const SizedBox(height: 8),
                Text(widget.member.fullName,
                    textAlign: TextAlign.center,
                    style: GoogleFonts.poppins(fontSize: 17, fontWeight: FontWeight.w600)),
                Text('${role.label} · enter your PIN',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.poppins(fontSize: 12, color: AppColors.textSecondary)),
                const SizedBox(height: 16),
                _PinDots(length: _pin.length),
                SizedBox(
                  height: 40,
                  child: Center(
                    child: _submitting
                        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                        : Text(
                            _error ?? '',
                            textAlign: TextAlign.center,
                            maxLines: 2,
                            style: GoogleFonts.poppins(fontSize: 12, color: AppColors.error, fontWeight: FontWeight.w500),
                          ),
                  ),
                ),
                _keypad(),
                const SizedBox(height: 4),
                TextButton(
                  onPressed: _submitting ? null : () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _keypad() {
    Widget row(List<Widget> keys) => Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: keys),
        );
    Widget digit(String d) => _PadKey(
          enabled: _enabled,
          onTap: () => _type(d),
          child: Text(d, style: GoogleFonts.poppins(fontSize: 22, fontWeight: FontWeight.w500)),
        );
    return Column(
      children: [
        row([digit('1'), digit('2'), digit('3')]),
        row([digit('4'), digit('5'), digit('6')]),
        row([digit('7'), digit('8'), digit('9')]),
        row([
          _PadKey(
            enabled: _enabled && !_pin.isEmpty,
            onTap: _backspace,
            tooltip: 'Delete',
            child: const Icon(Icons.backspace_outlined, size: 22),
          ),
          digit('0'),
          _PadKey(
            enabled: _enabled && _pin.canSubmit,
            onTap: _submit,
            filled: true,
            tooltip: 'Sign in',
            child: const Icon(Icons.check, size: 26, color: Colors.white),
          ),
        ]),
      ],
    );
  }
}

/// Six slots: the first four are required, the last two optional (lighter)
class _PinDots extends StatelessWidget {
  final int length;
  const _PinDots({required this.length});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(PinBuffer.maxLength, (i) {
        final filled = i < length;
        final optional = i >= PinBuffer.minLength;
        return Container(
          width: 14,
          height: 14,
          margin: const EdgeInsets.symmetric(horizontal: 6),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: filled ? AppColors.secondary : Colors.transparent,
            border: Border.all(
              color: filled
                  ? AppColors.secondary
                  : (optional ? Colors.grey.shade300 : Colors.grey.shade500),
              width: 1.5,
            ),
          ),
        );
      }),
    );
  }
}

class _PadKey extends StatelessWidget {
  final Widget child;
  final VoidCallback onTap;
  final bool enabled;
  final bool filled;
  final String? tooltip;

  const _PadKey({required this.child, required this.onTap, this.enabled = true, this.filled = false, this.tooltip});

  @override
  Widget build(BuildContext context) {
    final key = Material(
      color: filled
          ? (enabled ? AppColors.stockGreen : Colors.grey.shade300)
          : (enabled ? AppColors.secondary.withValues(alpha: 0.06) : Colors.grey.shade100),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: enabled ? onTap : null,
        child: SizedBox(
          width: 62,
          height: 62,
          child: Center(
            child: IconTheme.merge(
              data: IconThemeData(color: enabled ? AppColors.textPrimary : AppColors.textLight),
              child: DefaultTextStyle.merge(
                style: TextStyle(color: enabled ? AppColors.textPrimary : AppColors.textLight),
                child: child,
              ),
            ),
          ),
        ),
      ),
    );
    return tooltip == null ? key : Tooltip(message: tooltip!, child: key);
  }
}
