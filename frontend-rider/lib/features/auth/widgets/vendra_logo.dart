// ══════════════════════════════════════════════════════════════
// Vendra Rider App - Wordmark with the Pakistan flag chip
// ══════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:vendra_rider/vendra_core.dart';

class VendraLogo extends StatelessWidget {
  final String subtitle;
  const VendraLogo({super.key, this.subtitle = 'Rider App'});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              'Vendra',
              style: GoogleFonts.poppins(fontSize: 36, fontWeight: FontWeight.w700, color: AppColors.secondary),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 28,
              height: 20,
              child: Row(
                children: [
                  Expanded(flex: 1, child: Container(color: Colors.white)),
                  Expanded(
                    flex: 3,
                    child: Container(
                      decoration: const BoxDecoration(
                        color: AppColors.pakistanGreen,
                        borderRadius: BorderRadius.horizontal(right: Radius.circular(2)),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(subtitle, style: GoogleFonts.poppins(fontSize: 13, color: AppColors.textSecondary)),
      ],
    );
  }
}
