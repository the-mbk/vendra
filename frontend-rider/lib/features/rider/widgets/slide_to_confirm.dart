// ══════════════════════════════════════════════════════════════
// Vendra Rider App - Slide to confirm
// The final handover is a deliberate slide, not a tap, so a phone in a
// pocket can't confirm a delivery. Let go before the end and the thumb
// springs back. Screen readers get a normal "activate" action instead.
// ══════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:vendra_rider/vendra_core.dart';

class SlideToConfirm extends StatefulWidget {
  final String label;
  final VoidCallback? onConfirmed;
  final bool busy;
  const SlideToConfirm({super.key, required this.label, required this.onConfirmed, this.busy = false});

  @override
  State<SlideToConfirm> createState() => _SlideToConfirmState();
}

class _SlideToConfirmState extends State<SlideToConfirm> with SingleTickerProviderStateMixin {
  static const double _height = 56;
  static const double _thumb = 48;
  static const double _threshold = 0.9;

  /// 0 = start, 1 = end
  double _progress = 0;
  late final AnimationController _back = AnimationController(vsync: this, duration: const Duration(milliseconds: 250))
    ..addListener(() => setState(() => _progress = _from * (1 - _back.value)));
  double _from = 0;

  bool get _enabled => widget.onConfirmed != null && !widget.busy;

  @override
  void didUpdateWidget(SlideToConfirm old) {
    super.didUpdateWidget(old);
    // A finished (or failed) confirmation resets the slider
    if (old.busy && !widget.busy) _progress = 0;
  }

  @override
  void dispose() {
    _back.dispose();
    super.dispose();
  }

  void _release() {
    if (_progress >= _threshold) {
      setState(() => _progress = 1);
      HapticFeedback.mediumImpact();
      widget.onConfirmed?.call();
    } else {
      _from = _progress;
      _back.forward(from: 0);
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = _enabled ? AppColors.success : AppColors.textLight;
    return LayoutBuilder(builder: (context, constraints) {
      final travel = constraints.maxWidth - _thumb - 8;
      return Semantics(
        button: true,
        enabled: _enabled,
        label: widget.label,
        onTap: _enabled ? widget.onConfirmed : null,
        child: Container(
          height: _height,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(_height / 2),
            border: Border.all(color: color.withValues(alpha: 0.4)),
          ),
          child: Stack(
            alignment: Alignment.centerLeft,
            children: [
              // Filled part behind the thumb
              Container(
                width: _thumb + 8 + travel * _progress,
                decoration: BoxDecoration(color: color.withValues(alpha: 0.25), borderRadius: BorderRadius.circular(_height / 2)),
              ),
              Center(
                child: Opacity(
                  opacity: (1 - _progress * 1.4).clamp(0.0, 1.0),
                  child: Text(
                    widget.busy ? 'Confirming…' : widget.label,
                    style: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w600, color: color),
                  ),
                ),
              ),
              Positioned(
                left: 4 + travel * _progress,
                child: GestureDetector(
                  onHorizontalDragUpdate: _enabled
                      ? (d) => setState(() => _progress = (_progress + d.delta.dx / travel).clamp(0.0, 1.0))
                      : null,
                  onHorizontalDragEnd: _enabled ? (_) => _release() : null,
                  child: Container(
                    width: _thumb,
                    height: _thumb,
                    decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                    child: widget.busy
                        ? const Padding(
                            padding: EdgeInsets.all(14),
                            child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
                          )
                        : const Icon(Icons.double_arrow_rounded, color: Colors.white),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    });
  }
}
