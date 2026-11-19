// ══════════════════════════════════════════════════════════════
// Vendra App - Directions hand-off (SRDS §2.5.1)
// Opens the installed Google Maps app with directions to a point:
// riders get two-wheeler navigation (Android), customers going to a
// store for self pickup get ordinary directions. Falls back to the geo:
// intent, then to Google Maps on the web.
// ══════════════════════════════════════════════════════════════

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

class MapsLauncher {
  MapsLauncher._();

  static Future<void> navigate(BuildContext context, double lat, double lng, {String? label, bool twoWheeler = false}) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    final web = Uri.https('www.google.com', '/maps/dir/', {
      'api': '1',
      'destination': '$lat,$lng',
      'travelmode': twoWheeler ? 'two-wheeler' : 'driving',
    });
    final candidates = <Uri>[
      if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) ...[
        Uri.parse('google.navigation:q=$lat,$lng${twoWheeler ? '&mode=l' : ''}'),
        Uri.parse('geo:$lat,$lng?q=$lat,$lng(${Uri.encodeComponent(label ?? 'Destination')})'),
      ],
      if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS)
        Uri.parse('comgooglemaps://?daddr=$lat,$lng&directionsmode=driving'),
      web,
    ];
    for (final uri in candidates) {
      try {
        if (await launchUrl(uri, mode: LaunchMode.externalApplication)) return;
      } catch (_) {
        // Not handled on this device: try the next option
      }
    }
    messenger?.showSnackBar(const SnackBar(content: Text('Could not open a maps app on this device.')));
  }
}
