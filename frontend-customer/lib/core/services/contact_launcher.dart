// ══════════════════════════════════════════════════════════════
// Vendra App - Contact launcher
// Opens the phone dialer for a number. Where calling isn't possible
// (desktop, some browsers) the number is copied instead.
// ══════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

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
      await Clipboard.setData(ClipboardData(text: phone!));
      messenger?.showSnackBar(SnackBar(content: Text('Calling isn\'t available here. $phone copied.')));
    }
  }
}

/// A phone number with a call button, for store / customer / rider details
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
      label: Text(label ?? phone!),
    );
  }
}
