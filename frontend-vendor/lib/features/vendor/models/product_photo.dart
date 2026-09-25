// ══════════════════════════════════════════════════════════════
// Vendra Vendor App - A product photo picked on the add/edit screen,
// uploaded after the product is saved:
//   POST /api/vendor/products/:id/image   multipart field `image`
// The server accepts JPEG, PNG, WebP or HEIC up to 5 MB and filters by
// MIME type, so the part's content type is always set explicitly.
// ══════════════════════════════════════════════════════════════

import 'dart:typed_data';

import 'package:dio/dio.dart';

class ProductPhoto {
  final String name;
  final Uint8List bytes;
  final String mimeType;

  const ProductPhoto({required this.name, required this.bytes, required this.mimeType});

  static const int maxBytes = 5 * 1024 * 1024; // server limit

  /// MIME type from the picker, or from the file extension when the platform doesn't report one
  static String mimeFor(String name, [String? reported]) {
    if (reported != null && reported.startsWith('image/')) return reported;
    final lower = name.toLowerCase();
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.webp')) return 'image/webp';
    if (lower.endsWith('.heic') || lower.endsWith('.heif')) return 'image/heic';
    return 'image/jpeg';
  }

  FormData toFormData() => FormData.fromMap({
        'image': MultipartFile.fromBytes(
          bytes,
          filename: name,
          contentType: DioMediaType.parse(mimeType),
        ),
      });
}
