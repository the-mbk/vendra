// ══════════════════════════════════════════════════════════════
// Vendra App - Contact launcher
// Opens the phone dialer for a number. Where calling isn't possible
// (desktop, some browsers) the number is copied instead.
// Personal numbers are shown masked (0312-***566): the call button
// dials them, but they are never printed on screen.
// ══════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

/// "0312-1234566" → "0312-***566"; null for an empty number
String? maskPhone(String? phone) {
  final digits = (phone ?? '').replaceAll(RegExp(r'\D'), '');
  if (digits.isEmpty) return null;
  if (digits.length < 7) return '***';
  return '${digits.substring(0, 4)}-***${digits.substring(digits.length - 3)}';
}

class ContactLauncher {
  static Future<void> call(BuildContext context, String? phone) async {
    final number = (phone ?? '').replaceAll(RegExp(r'[^\d+]'), '');
    if (number.isEmpty) return;
    final messenger = ScaffoldMessenger.maybeOf(context);

    final uri = Uri(scheme: 'tel', path: number);
    var launched = false;
    try {
      launched = await launchUrl(uri);
    } catch (_) {
      launched = false;
    }
    if (!launched) {
      await Clipboard.setData(ClipboardData(text: number));
      messenger?.showSnackBar(const SnackBar(content: Text("Calling isn't available here. The number was copied.")));
    }
  }
}

/// A call button for customer / rider / store contact. Shows [label], or the
/// masked number when there is no label.
class PhoneAction extends StatelessWidget {
  final String? phone;
  final String? label;
  const PhoneAction({super.key, required this.phone, this.label});

  @override
  Widget build(BuildContext context) {
    if (phone == null || phone!.isEmpty) return const SizedBox.shrink();
    return TextButton.icon(
      onPressed: () => ContactLauncher.call(context, phone),
      icon: const Icon(Icons.call_outlined, size: 18),
      label: Text(label ?? maskPhone(phone)!),
    );
  }
}
