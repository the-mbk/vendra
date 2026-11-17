// ══════════════════════════════════════════════════════════════
// Vendra Vendor App - The store's logo and cover photo (owner only)
//   POST   /api/vendor/store/photos/logo|cover   multipart field `image`
//   DELETE /api/vendor/store/photos/logo|cover
// Both answer { data: { logoUrl, coverUrl } } (paths under /uploads, or null).
// ══════════════════════════════════════════════════════════════

import 'package:vendra_vendor/vendra_core.dart';

import '../models/product_photo.dart';

enum StorePhotoKind {
  logo('logo', ApiConfig.storeLogo),
  cover('cover photo', ApiConfig.storeCover);

  /// For messages: "Logo updated", "Cover photo removed"
  final String label;
  final String endpoint;
  const StorePhotoKind(this.label, this.endpoint);
}

class StorePictures {
  final String? logoUrl;
  final String? coverUrl;
  const StorePictures({this.logoUrl, this.coverUrl});

  factory StorePictures.fromJson(Map<String, dynamic> json) {
    String? path(Object? v) => v is String && v.isNotEmpty ? v : null;
    return StorePictures(
      logoUrl: path(json['logoUrl'] ?? json['logo_url']),
      coverUrl: path(json['coverUrl'] ?? json['cover_url']),
    );
  }
}

/// Talks to the store-photo endpoints; replaced by a fake in widget tests
class StorePhotoApi {
  const StorePhotoApi();

  Future<StorePictures> upload(StorePhotoKind kind, ProductPhoto photo) async {
    try {
      return _parse((await ApiService().postMultipart(kind.endpoint, photo.toFormData())).data);
    } catch (e) {
      throw StorePhotoException(_message(e, 'Upload failed'));
    }
  }

  Future<StorePictures> remove(StorePhotoKind kind) async {
    try {
      return _parse((await ApiService().delete(kind.endpoint)).data);
    } catch (e) {
      throw StorePhotoException(_message(e, 'Could not remove the ${kind.label}'));
    }
  }

  static StorePictures _parse(Object? body) {
    if (body is! Map || body['success'] == false || body['data'] is! Map) {
      throw StorePhotoException(body is Map && body['message'] is String ? body['message'] as String : 'Unexpected reply');
    }
    return StorePictures.fromJson(Map<String, dynamic>.from(body['data'] as Map));
  }

  static String _message(Object e, String fallback) {
    if (e is StorePhotoException) return e.message;
    final message = ApiService.getErrorMessage(e);
    return message.isEmpty ? fallback : message;
  }
}

class StorePhotoException implements Exception {
  final String message;
  const StorePhotoException(this.message);

  @override
  String toString() => message;
}
