// ══════════════════════════════════════════════════════════════
// Vendra App - Connection banner
// When the live connection (orders, stock, rider position) drops, a
// small amber pill appears at the top, non-blocking, until it is back.
// Short blips (under 2 s) don't show. "Retry now" reconnects at once
// instead of waiting for the socket's own back-off.
//
//   MaterialApp(builder: (context, child) => ConnectionBanner(child: child!))
// ══════════════════════════════════════════════════════════════

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../config/app_theme.dart';
import '../services/realtime_service.dart';

class ConnectionBanner extends StatefulWidget {
  final Widget child;
  const ConnectionBanner({super.key, required this.child});

  @override
  State<ConnectionBanner> createState() => _ConnectionBannerState();
}

class _ConnectionBannerState extends State<ConnectionBanner> {
  static const _grace = Duration(seconds: 2);
  final _realtime = RealtimeService();
  Timer? _delay;
  bool _show = false;

  @override
  void initState() {
    super.initState();
    _realtime.reconnecting.addListener(_onChange);
  }

  @override
  void dispose() {
    _realtime.reconnecting.removeListener(_onChange);
    _delay?.cancel();
    super.dispose();
  }

  void _onChange() {
    _delay?.cancel();
    if (_realtime.reconnecting.value) {
      _delay = Timer(_grace, () {
        if (mounted && _realtime.reconnecting.value) setState(() => _show = true);
      });
    } else if (_show) {
      setState(() => _show = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        widget.child,
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: SafeArea(
            bottom: false,
            child: IgnorePointer(
              ignoring: !_show,
              child: AnimatedSlide(
                offset: _show ? Offset.zero : const Offset(0, -1.5),
                duration: const Duration(milliseconds: 250),
                child: Center(
                  child: Material(
                    color: AppColors.warningSurface,
                    elevation: 3,
                    borderRadius: BorderRadius.circular(24),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(14, 6, 6, 6),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.wifi_off_rounded, size: 18, color: AppColors.warningInk),
                          const SizedBox(width: 8),
                          Text('Connection dropped. Reconnecting…',
                              style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.warningInk)),
                          TextButton(
                            onPressed: () => _realtime.connect(),
                            child: const Text('Retry now'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
