// ══════════════════════════════════════════════════════════════
// Vendra Customer App - Store helpers
// haversineKm / distanceLabel  straight-line distance to a store
// StoreBannerCard              store card with its cover photo and logo
//                              (search results); uses StoreCover/StoreLogo
// ══════════════════════════════════════════════════════════════

import 'dart:math';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:vendra_customer/vendra_core.dart';

/// Straight-line distance in km between two points
double haversineKm(double lat1, double lon1, double lat2, double lon2) {
  const r = 6371.0;
  final dLat = (lat2 - lat1) * pi / 180;
  final dLon = (lon2 - lon1) * pi / 180;
  final a = sin(dLat / 2) * sin(dLat / 2) +
      cos(lat1 * pi / 180) * cos(lat2 * pi / 180) * sin(dLon / 2) * sin(dLon / 2);
  return r * 2 * atan2(sqrt(a), sqrt(1 - a));
}

/// "850 m" / "2.4 km"
String distanceLabel(double km) => km < 1 ? '${(km * 1000).toStringAsFixed(0)} m' : '${km.toStringAsFixed(1)} km';

/// A store with its cover photo as a banner and the logo overlapping it
class StoreBannerCard extends StatelessWidget {
  final String storeName;
  final String? logoUrl;
  final String? coverUrl;
  final String subtitle;

  /// Shows the subtitle in orange (e.g. "pickup only")
  final bool warn;
  final VoidCallback onTap;
  final double width;

  const StoreBannerCard({
    super.key,
    required this.storeName,
    this.logoUrl,
    this.coverUrl,
    this.subtitle = '',
    this.warn = false,
    required this.onTap,
    this.width = 220,
  });

  static const bannerHeight = 64.0;
  static const logoSize = 44.0;
  static const height = 140.0;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      height: height,
      child: Material(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Ink(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.hairline),
            ),
            child: Stack(
              children: [
                Positioned(
                  left: 0,
                  right: 0,
                  top: 0,
                  height: bannerHeight,
                  child: StoreCover(coverUrl: coverUrl),
                ),
                Positioned(
                  left: 12,
                  top: bannerHeight - logoSize / 2,
                  child: StoreLogo(storeName: storeName, logoUrl: logoUrl, size: logoSize, ring: true),
                ),
                Positioned(
                  left: 12,
                  right: 12,
                  bottom: 10,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(storeName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                      if (subtitle.isNotEmpty)
                        Text(subtitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.poppins(
                                fontSize: 11, color: warn ? AppColors.warningInk : AppColors.textSecondary)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
