// ══════════════════════════════════════════════════════════════
// Vendra Vendor App - Picking a photo to upload (product photos and the
// store's logo / cover). The gallery works everywhere (a file chooser
// on web / desktop); the camera only where the platform has one. The
// photo is read into memory, so the same bytes upload from web and
// mobile (see ProductPhoto.toFormData).
// ══════════════════════════════════════════════════════════════

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../models/product_photo.dart';

/// Why a picked photo can't be used (shown to the user as-is)
class PhotoPickException implements Exception {
  final String message;
  const PhotoPickException(this.message);

  @override
  String toString() => message;
}

/// The camera is offered on phones only; the web picker can't open it directly
bool photoCameraAvailable(ImagePicker picker) => !kIsWeb && picker.supportsImageSource(ImageSource.camera);

/// "Choose from gallery" / "Take a photo" sheet. Without a camera, straight to the gallery.
/// Null if dismissed.
Future<ImageSource?> choosePhotoSource(BuildContext context, ImagePicker picker) async {
  if (!photoCameraAvailable(picker)) return ImageSource.gallery;
  return showModalBottomSheet<ImageSource>(
    context: context,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.photo_library_outlined),
            title: const Text('Choose from gallery'),
            onTap: () => Navigator.pop(ctx, ImageSource.gallery),
          ),
          ListTile(
            leading: const Icon(Icons.photo_camera_outlined),
            title: const Text('Take a photo'),
            onTap: () => Navigator.pop(ctx, ImageSource.camera),
          ),
        ],
      ),
    ),
  );
}

/// Opens the picker; null if cancelled. Throws [PhotoPickException] when the photo
/// is over the server's 5 MB limit or can't be read.
Future<ProductPhoto?> pickPhoto(
  ImagePicker picker,
  ImageSource source, {
  String namePrefix = 'photo',
  double maxDimension = 1600,
}) async {
  final XFile? file;
  final Uint8List bytes;
  try {
    // Gallery on mobile, a file chooser on web / desktop
    file = await picker.pickImage(source: source, maxWidth: maxDimension, maxHeight: maxDimension, imageQuality: 85);
    if (file == null) return null;
    bytes = await file.readAsBytes();
  } catch (e) {
    throw PhotoPickException('Could not open photos: $e');
  }
  if (bytes.length > ProductPhoto.maxBytes) {
    throw const PhotoPickException('That photo is over 5 MB — please choose a smaller one.');
  }
  final name = file.name.isNotEmpty ? file.name : '${namePrefix}_${DateTime.now().millisecondsSinceEpoch}.jpg';
  return ProductPhoto(name: name, bytes: bytes, mimeType: ProductPhoto.mimeFor(name, file.mimeType));
}
