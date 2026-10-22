// ══════════════════════════════════════════════════════════════
// Vendra App - Development badge
// A thin "DEVELOPMENT MODE" strip above every screen while the backend runs
// in development mode (test cards, demo logins, shortened timers). It takes
// its own space (the app below loses the status-bar padding it now covers),
// so it never sits on top of titles or buttons. Hidden in production.
//
//   MaterialApp(builder: (context, child) => DevBanner(child: child!), ...)
// ══════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';

import '../services/app_config.dart';

class DevBanner extends StatelessWidget {
  final Widget child;
  const DevBanner({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AppConfig>(
      valueListenable: AppConfig.notifier,
      child: child,
      builder: (context, config, child) {
        if (!config.isDevelopment) return child!;
        final media = MediaQuery.maybeOf(context);
        final top = media?.padding.top ?? 0;
        return Column(
          children: [
            Container(
              width: double.infinity,
              color: const Color(0xFFF39C12),
              padding: EdgeInsets.only(top: top),
              child: const SizedBox(
                height: 14,
                child: Center(
                  child: Text(
                    'DEVELOPMENT MODE',
                    textDirection: TextDirection.ltr,
                    style: TextStyle(
                      fontSize: 8.5,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.2,
                      color: Colors.white,
                      decoration: TextDecoration.none,
                      height: 1.2,
                    ),
                  ),
                ),
              ),
            ),
            Expanded(
              child: media == null ? child! : MediaQuery(data: media.removePadding(removeTop: true), child: child!),
            ),
          ],
        );
      },
    );
  }
}
