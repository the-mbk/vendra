// ══════════════════════════════════════════════════════════════
// Vendra Rider App - Wordmark with the Pakistan flag chip & Icon
// ══════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:vendra_rider/vendra_core.dart';

class VendraLogo extends StatelessWidget {
  final String subtitle;
  final bool isDark;
  final double titleSize;

  const VendraLogo({
    super.key,
    this.subtitle = 'Rider Portal · Delivery Partner',
    this.isDark = false,
    this.titleSize = 34,
  });

  @override
  Widget build(BuildContext context) {
    return VendraBrandHeader(
      subtitle: subtitle,
      variant: BrandVariant.rider,
      iconStyle: HeaderIconStyle.inline,
      isDark: isDark,
      titleSize: titleSize,
    );
  }
}
