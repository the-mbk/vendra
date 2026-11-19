// ══════════════════════════════════════════════════════════════
// Vendra App - Edit profile (customers, riders, store owners)
// Photo, name and mobile number; the email is the login and stays fixed.
//   PUT    /api/auth/profile        { fullName, phone }
//   POST   /api/auth/profile/photo  multipart "image"
//   DELETE /api/auth/profile/photo
// An approved rider's name matches the CNIC an admin verified, so the
// screen shows it locked ([nameLocked]). [onSaved] lets the app reload the
// signed-in user (each app's AuthBloc re-reads /api/auth/me).
//
//   Navigator.push(context, MaterialPageRoute(builder: (_) => EditProfileScreen(
//     user: user, onSaved: () => context.read<AuthBloc>().add(...))));
// ══════════════════════════════════════════════════════════════

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';

import '../../config/app_theme.dart';
import '../models/user_model.dart';
import '../services/api_service.dart';
import 'user_avatar.dart';
import 'vendra_button.dart';

const _profilePath = '/api/auth/profile';
const _photoPath = '/api/auth/profile/photo';
const _maxPhotoBytes = 5 * 1024 * 1024;

/// "0300 1234567", "+92 300 1234567" → "0300-1234567"; null when it isn't a Pakistani mobile number
String? normalizePkMobile(String raw) {
  final digits = raw.replaceAll(RegExp(r'[\s-]'), '');
  final m = RegExp(r'^(?:\+92|0092|92|0)?(3\d{9})$').firstMatch(digits);
  if (m == null) return null;
  final local = '0${m.group(1)}';
  return '${local.substring(0, 4)}-${local.substring(4)}';
}

class EditProfileScreen extends StatefulWidget {
  final UserModel user;

  /// The name can't be changed here (an approved rider's verified CNIC name)
  final bool nameLocked;
  final VoidCallback onSaved;

  const EditProfileScreen({super.key, required this.user, required this.onSaved, this.nameLocked = false});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _name = TextEditingController(text: widget.user.fullName);
  late final TextEditingController _phone = TextEditingController(text: widget.user.phone ?? '');
  late String? _photoUrl = widget.user.avatarUrl;
  bool _saving = false;
  bool _photoBusy = false;

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    super.dispose();
  }

  void _snack(String text, {bool error = false}) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(text),
        backgroundColor: error ? AppColors.error : AppColors.success,
        behavior: SnackBarBehavior.floating,
      ));
  }

  Future<void> _changePhoto() async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Choose from gallery'),
              onTap: () => Navigator.pop(context, 'gallery'),
            ),
            if (!kIsWeb)
              ListTile(
                leading: const Icon(Icons.photo_camera_outlined),
                title: const Text('Take a photo'),
                onTap: () => Navigator.pop(context, 'camera'),
              ),
            if (_photoUrl != null)
              ListTile(
                leading: const Icon(Icons.delete_outline, color: AppColors.error),
                title: const Text('Remove photo', style: TextStyle(color: AppColors.error)),
                onTap: () => Navigator.pop(context, 'remove'),
              ),
          ],
        ),
      ),
    );
    if (choice == null || !mounted) return;
    setState(() => _photoBusy = true);
    try {
      final Response res;
      if (choice == 'remove') {
        res = await ApiService().delete(_photoPath);
      } else {
        final picked = await ImagePicker().pickImage(
          source: choice == 'camera' ? ImageSource.camera : ImageSource.gallery,
          maxWidth: 800,
          maxHeight: 800,
          imageQuality: 85,
        );
        if (picked == null) return;
        final bytes = await picked.readAsBytes();
        if (bytes.length > _maxPhotoBytes) throw const _PhotoTooBig();
        final name = picked.name.isEmpty ? 'profile.jpg' : picked.name;
        res = await ApiService().postMultipart(
          _photoPath,
          FormData.fromMap({
            'image': MultipartFile.fromBytes(bytes, filename: name, contentType: DioMediaType.parse(_mimeFor(name, picked.mimeType))),
          }),
        );
      }
      if (!mounted) return;
      setState(() => _photoUrl = (res.data['data'] as Map?)?['avatarUrl'] as String?);
      widget.onSaved();
      _snack(choice == 'remove' ? 'Photo removed.' : 'Photo updated.');
    } on _PhotoTooBig {
      if (mounted) _snack('That photo is over 5 MB. Choose a smaller one.', error: true);
    } catch (e) {
      if (mounted) _snack(ApiService.getErrorMessage(e), error: true);
    } finally {
      if (mounted) setState(() => _photoBusy = false);
    }
  }

  static String _mimeFor(String name, String? reported) {
    if (reported != null && reported.startsWith('image/')) return reported;
    final lower = name.toLowerCase();
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.webp')) return 'image/webp';
    if (lower.endsWith('.heic') || lower.endsWith('.heif')) return 'image/heic';
    return 'image/jpeg';
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      await ApiService().put(_profilePath, data: {
        if (!widget.nameLocked) 'fullName': _name.text.trim(),
        'phone': normalizePkMobile(_phone.text),
      });
      if (!mounted) return;
      widget.onSaved();
      _snack('Profile saved.');
      Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) _snack(ApiService.getErrorMessage(e), error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(text, style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
      );

  @override
  Widget build(BuildContext context) {
    final user = widget.user;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Edit profile')),
      body: SafeArea(
        child: Form(
          key: _form,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
            children: [
              Center(
                child: Semantics(
                  button: true,
                  label: 'Change profile photo',
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: _photoBusy ? null : _changePhoto,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        UserAvatar(name: _name.text, photoUrl: _photoUrl, size: 104, badge: Icons.photo_camera),
                        if (_photoBusy)
                          const SizedBox(width: 104, height: 104, child: CircularProgressIndicator(strokeWidth: 3)),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Center(
                child: TextButton(
                  onPressed: _photoBusy ? null : _changePhoto,
                  child: Text(_photoUrl == null ? 'Add a photo' : 'Change photo'),
                ),
              ),
              Center(
                child: Text(
                  user.isRider
                      ? 'Customers see your photo and first name while you deliver to them.'
                      : user.isCustomer
                          ? 'Your rider sees your photo and first name while delivering.'
                          : 'Shown on your account.',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.poppins(fontSize: 12, color: AppColors.textSecondary),
                ),
              ),
              const SizedBox(height: 24),
              _label('Full name'),
              TextFormField(
                controller: _name,
                enabled: !widget.nameLocked,
                textCapitalization: TextCapitalization.words,
                maxLength: 100,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  counterText: '',
                  prefixIcon: const Icon(Icons.person_outline),
                  suffixIcon: widget.nameLocked ? const Icon(Icons.lock_outline) : null,
                  helperText: widget.nameLocked ? 'Matches your verified CNIC. Contact Vendra support to change it.' : null,
                  helperMaxLines: 2,
                ),
                validator: (v) => (v ?? '').trim().length < 2 ? 'Enter your name' : null,
              ),
              const SizedBox(height: 16),
              _label('Mobile number'),
              TextFormField(
                controller: _phone,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(prefixIcon: Icon(Icons.phone_outlined), hintText: '0300-1234567'),
                validator: (v) => normalizePkMobile(v ?? '') == null ? 'Enter a Pakistani mobile number, e.g. 0300-1234567' : null,
              ),
              const SizedBox(height: 16),
              _label('Email'),
              TextFormField(
                initialValue: user.email,
                enabled: false,
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.mail_outline),
                  helperText: 'Your email is your sign-in and can\'t be changed.',
                ),
              ),
              const SizedBox(height: 28),
              VendraButton(text: 'Save changes', icon: Icons.check, isLoading: _saving, onPressed: _saving ? null : _save),
            ],
          ),
        ),
      ),
    );
  }
}

class _PhotoTooBig implements Exception {
  const _PhotoTooBig();
}
