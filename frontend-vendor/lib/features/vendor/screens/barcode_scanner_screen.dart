// ══════════════════════════════════════════════════════════════
// Vendra Vendor App - Barcode Scanner (FR01)
// Camera scanning via mobile_scanner on Android / iOS / macOS / web,
// with a typed-barcode fallback for Windows/Linux desktops, emulators
// without a camera, or a denied camera permission.
//
// Usage:  final code = await scanBarcode(context);   // null if cancelled
// ══════════════════════════════════════════════════════════════

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:vendra_vendor/vendra_core.dart';

/// Whether mobile_scanner has a camera implementation on this platform
bool get cameraScanSupported {
  if (kIsWeb) return true;
  switch (defaultTargetPlatform) {
    case TargetPlatform.android:
    case TargetPlatform.iOS:
    case TargetPlatform.macOS:
      return true;
    default:
      return false;
  }
}

/// Opens the camera scanner (or the typed fallback) and returns the barcode
Future<String?> scanBarcode(BuildContext context) {
  if (!cameraScanSupported) return enterBarcodeManually(context);
  return Navigator.of(context).push<String>(
    MaterialPageRoute(builder: (_) => const BarcodeScannerScreen()),
  );
}

/// Dialog for typing a barcode (desktop, emulator, or no camera)
Future<String?> enterBarcodeManually(BuildContext context) {
  return showDialog<String>(
    context: context,
    builder: (_) => const TextPromptDialog(
      title: 'Enter barcode',
      hint: 'e.g. 8806094975123',
      icon: Icons.qr_code_2,
      confirmLabel: 'Use barcode',
    ),
  );
}

/// Small one-field dialog that returns the trimmed text (or null if cancelled).
/// Owns its controller so it is disposed only after the exit animation.
class TextPromptDialog extends StatefulWidget {
  final String title;
  final String? hint;
  final String? label;
  final String initialValue;
  final IconData? icon;
  final String confirmLabel;
  final TextInputType keyboardType;

  const TextPromptDialog({
    super.key,
    required this.title,
    this.hint,
    this.label,
    this.initialValue = '',
    this.icon,
    this.confirmLabel = 'OK',
    this.keyboardType = TextInputType.number,
  });

  @override
  State<TextPromptDialog> createState() => _TextPromptDialogState();
}

class _TextPromptDialogState extends State<TextPromptDialog> {
  late final TextEditingController _ctrl = TextEditingController(text: widget.initialValue);

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _submit() {
    final value = _ctrl.text.trim();
    if (value.isNotEmpty) Navigator.pop(context, value);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Text(widget.title, style: GoogleFonts.poppins(fontSize: 17, fontWeight: FontWeight.w600)),
      content: TextField(
        controller: _ctrl,
        autofocus: true,
        keyboardType: widget.keyboardType,
        textInputAction: TextInputAction.done,
        onSubmitted: (_) => _submit(),
        decoration: InputDecoration(
          hintText: widget.hint,
          labelText: widget.label,
          prefixIcon: widget.icon != null ? Icon(widget.icon, size: 20) : null,
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        ElevatedButton(
          onPressed: _submit,
          style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12)),
          child: Text(widget.confirmLabel),
        ),
      ],
    );
  }
}

class BarcodeScannerScreen extends StatefulWidget {
  const BarcodeScannerScreen({super.key});

  @override
  State<BarcodeScannerScreen> createState() => _BarcodeScannerScreenState();
}

class _BarcodeScannerScreenState extends State<BarcodeScannerScreen> {
  final MobileScannerController _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
    formats: const [
      BarcodeFormat.ean13,
      BarcodeFormat.ean8,
      BarcodeFormat.upcA,
      BarcodeFormat.upcE,
      BarcodeFormat.code128,
      BarcodeFormat.code39,
      BarcodeFormat.qrCode,
    ],
  );
  bool _done = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_done) return;
    for (final b in capture.barcodes) {
      final value = b.rawValue?.trim();
      if (value != null && value.isNotEmpty) {
        _done = true;
        Navigator.pop(context, value);
        return;
      }
    }
  }

  Future<void> _typeInstead() async {
    final code = await enterBarcodeManually(context);
    if (code != null && mounted) Navigator.pop(context, code);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text('Scan barcode', style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.w600)),
        actions: [
          IconButton(
            tooltip: 'Torch',
            icon: const Icon(Icons.flashlight_on_outlined),
            onPressed: () => _controller.toggleTorch(),
          ),
          IconButton(
            tooltip: 'Switch camera',
            icon: const Icon(Icons.cameraswitch_outlined),
            onPressed: () => _controller.switchCamera(),
          ),
        ],
      ),
      body: Stack(
        children: [
          MobileScanner(
            controller: _controller,
            onDetect: _onDetect,
            errorBuilder: (context, error) => _CameraUnavailable(
              message: error.errorCode == MobileScannerErrorCode.permissionDenied
                  ? 'Camera permission was denied. Allow camera access in settings, or type the barcode.'
                  : 'The camera is not available on this device. Type the barcode instead.',
              onTypeInstead: _typeInstead,
            ),
          ),
          // Scan window guide
          Center(
            child: Container(
              width: 280,
              height: 160,
              decoration: BoxDecoration(
                border: Border.all(color: AppColors.primary, width: 3),
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
          Positioned(
            left: 16,
            right: 16,
            bottom: 24,
            child: SafeArea(
              top: false,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Point the camera at the product barcode',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.poppins(color: Colors.white, fontSize: 14),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: _typeInstead,
                    icon: const Icon(Icons.keyboard_outlined),
                    label: const Text('Type barcode instead'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: const BorderSide(color: Colors.white70),
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CameraUnavailable extends StatelessWidget {
  final String message;
  final VoidCallback onTypeInstead;
  const _CameraUnavailable({required this.message, required this.onTypeInstead});

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Colors.black,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.no_photography_outlined, color: Colors.white54, size: 56),
              const SizedBox(height: 16),
              Text(message,
                  textAlign: TextAlign.center, style: GoogleFonts.poppins(color: Colors.white70, fontSize: 14)),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: onTypeInstead,
                icon: const Icon(Icons.keyboard_outlined),
                label: const Text('Type barcode'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
