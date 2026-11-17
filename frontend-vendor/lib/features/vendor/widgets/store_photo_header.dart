// ══════════════════════════════════════════════════════════════
// Vendra Vendor App - Store header on the Profile tab: the cover photo
// with the logo overlaid, as customers see the store page. The owner can
// change or remove either picture (gallery everywhere, camera on phones;
// the same picker as product photos). Staff signed in with a PIN see it
// read-only. After a change the signed-in user is re-read (onChanged) so
// the new pictures show on every screen.
// ══════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:vendra_vendor/vendra_core.dart';

import '../models/product_photo.dart';
import '../services/photo_picker.dart';
import '../services/store_photo_api.dart';

enum _PhotoAction { gallery, camera, remove }

class StorePhotoHeader extends StatefulWidget {
  final UserModel user;
  final StorePhotoApi api;
  final ImagePicker? picker;

  /// Called after a picture changed (the profile screen refreshes /api/auth/me)
  final VoidCallback? onChanged;

  /// Tests: supplies the "picked" photo instead of opening the system picker
  final Future<ProductPhoto?> Function(ImageSource source)? pickPhotoOverride;

  const StorePhotoHeader({
    super.key,
    required this.user,
    this.api = const StorePhotoApi(),
    this.picker,
    this.onChanged,
    this.pickPhotoOverride,
  });

  static const double coverHeight = 140;
  static const double logoSize = 76;

  @override
  State<StorePhotoHeader> createState() => _StorePhotoHeaderState();
}

class _StorePhotoHeaderState extends State<StorePhotoHeader> {
  late final ImagePicker _picker = widget.picker ?? ImagePicker();
  String? _logoUrl;
  String? _coverUrl;
  StorePhotoKind? _busy;

  bool get _canEdit => widget.user.isStoreOwner;

  @override
  void initState() {
    super.initState();
    _logoUrl = widget.user.storeLogoUrl;
    _coverUrl = widget.user.storeCoverUrl;
  }

  @override
  void didUpdateWidget(covariant StorePhotoHeader old) {
    super.didUpdateWidget(old);
    // The refreshed /api/auth/me wins over what the upload replied
    if (old.user.storeLogoUrl != widget.user.storeLogoUrl) _logoUrl = widget.user.storeLogoUrl;
    if (old.user.storeCoverUrl != widget.user.storeCoverUrl) _coverUrl = widget.user.storeCoverUrl;
  }

  String? _current(StorePhotoKind kind) => kind == StorePhotoKind.logo ? _logoUrl : _coverUrl;

  void _snack(String message, {bool error = false}) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(message),
        backgroundColor: error ? AppColors.error : null,
        behavior: SnackBarBehavior.floating,
      ));
  }

  static String _capitalized(String s) => s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';

  /// Gallery / camera / remove. Straight to the gallery when that's the only choice.
  Future<_PhotoAction?> _chooseAction(StorePhotoKind kind) async {
    final hasPhoto = _current(kind) != null;
    final camera = photoCameraAvailable(_picker);
    if (!hasPhoto && !camera) return _PhotoAction.gallery;
    return showModalBottomSheet<_PhotoAction>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
              child: Text(
                kind == StorePhotoKind.logo
                    ? 'Store logo · a square picture works best'
                    : 'Cover photo · a wide picture works best',
                style: GoogleFonts.poppins(fontSize: 13, color: AppColors.textSecondary),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Choose from gallery'),
              onTap: () => Navigator.pop(ctx, _PhotoAction.gallery),
            ),
            if (camera)
              ListTile(
                leading: const Icon(Icons.photo_camera_outlined),
                title: const Text('Take a photo'),
                onTap: () => Navigator.pop(ctx, _PhotoAction.camera),
              ),
            if (hasPhoto)
              ListTile(
                leading: const Icon(Icons.delete_outline, color: AppColors.error),
                title: Text('Remove ${kind.label}', style: const TextStyle(color: AppColors.error)),
                onTap: () => Navigator.pop(ctx, _PhotoAction.remove),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _change(StorePhotoKind kind) async {
    if (_busy != null) return;
    final action = await _chooseAction(kind);
    if (action == null || !mounted) return;
    if (action == _PhotoAction.remove) {
      await _run(kind, () => widget.api.remove(kind), '${_capitalized(kind.label)} removed');
      return;
    }

    final source = action == _PhotoAction.camera ? ImageSource.camera : ImageSource.gallery;
    final ProductPhoto? photo;
    try {
      photo = widget.pickPhotoOverride != null
          ? await widget.pickPhotoOverride!(source)
          : await pickPhoto(
              _picker,
              source,
              namePrefix: 'store_${kind.name}',
              maxDimension: kind == StorePhotoKind.logo ? 800 : 1600,
            );
    } on PhotoPickException catch (e) {
      if (mounted) _snack(e.message, error: true);
      return;
    }
    if (photo == null || !mounted) return;
    final ProductPhoto picked = photo;
    await _run(kind, () => widget.api.upload(kind, picked), '${_capitalized(kind.label)} updated');
  }

  Future<void> _run(StorePhotoKind kind, Future<StorePictures> Function() call, String done) async {
    setState(() => _busy = kind);
    try {
      final pictures = await call();
      if (!mounted) return;
      setState(() {
        _logoUrl = pictures.logoUrl;
        _coverUrl = pictures.coverUrl;
      });
      widget.onChanged?.call();
      _snack(done);
    } on StorePhotoException catch (e) {
      if (mounted) _snack(e.message, error: true);
    } catch (e) {
      debugPrint('Store photo change failed: $e');
      if (mounted) _snack("Couldn't update the ${kind.label}. Please try again.", error: true);
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  Widget _progress({required double size}) => Center(
        child: SizedBox(
          width: size,
          height: size,
          child: const CircularProgressIndicator(strokeWidth: 3, color: Colors.white),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final user = widget.user;
    final storeName = user.storeName ?? 'My Store';
    const coverHeight = StorePhotoHeader.coverHeight;
    const logoSize = StorePhotoHeader.logoSize;

    return Container(
      width: double.infinity,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: coverHeight + logoSize / 2,
            child: Stack(
              children: [
                Positioned(
                  left: 0,
                  right: 0,
                  top: 0,
                  height: coverHeight,
                  child: Semantics(
                    label: 'Store cover photo',
                    image: true,
                    child: StoreCover(key: const ValueKey('store-cover'), coverUrl: _coverUrl),
                  ),
                ),
                if (_busy == StorePhotoKind.cover)
                  Positioned(
                    left: 0,
                    right: 0,
                    top: 0,
                    height: coverHeight,
                    child: ColoredBox(color: Colors.black38, child: _progress(size: 32)),
                  ),
                Positioned(
                  left: 16,
                  top: coverHeight - logoSize / 2,
                  child: Stack(
                    children: [
                      Semantics(
                        label: 'Store logo',
                        image: true,
                        child: StoreLogo(storeName: storeName, logoUrl: _logoUrl, size: logoSize, square: true, ring: true),
                      ),
                      if (_busy == StorePhotoKind.logo)
                        Positioned.fill(
                          child: Container(
                            margin: const EdgeInsets.all(3),
                            decoration: BoxDecoration(
                              color: Colors.black45,
                              borderRadius: BorderRadius.circular(logoSize * 0.2),
                            ),
                            child: _progress(size: 24),
                          ),
                        ),
                    ],
                  ),
                ),
                Positioned(
                  left: 16 + logoSize + 12,
                  right: 12,
                  top: coverHeight + 6,
                  child: Text(storeName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.poppins(fontSize: 17, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if ((user.storeAddress ?? '').isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.place_outlined, size: 16, color: AppColors.textSecondary),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(user.storeAddress!,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.poppins(fontSize: 12, color: AppColors.textSecondary)),
                        ),
                      ],
                    ),
                  ),
                if (_canEdit)
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      OutlinedButton.icon(
                        onPressed: _busy == null ? () => _change(StorePhotoKind.logo) : null,
                        icon: const Icon(Icons.account_circle_outlined, size: 18),
                        label: const Text('Change logo'),
                      ),
                      OutlinedButton.icon(
                        onPressed: _busy == null ? () => _change(StorePhotoKind.cover) : null,
                        icon: const Icon(Icons.panorama_outlined, size: 18),
                        label: const Text('Change cover photo'),
                      ),
                    ],
                  )
                else
                  Text("Only the store owner can change the store's logo and cover photo.",
                      style: GoogleFonts.poppins(fontSize: 12, color: AppColors.textSecondary)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
