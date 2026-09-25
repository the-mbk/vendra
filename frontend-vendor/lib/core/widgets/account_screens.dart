// ══════════════════════════════════════════════════════════════
// Vendra App - Account screens shared by every app
//   ChangePasswordScreen      from Profile, or forced after an admin reset
//   showForgotPasswordDialog  explains how to get a password reset
// ══════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';

import '../../config/api_config.dart';
import '../../config/app_theme.dart';
import '../services/api_service.dart';
import 'vendra_button.dart';
import 'vendra_text_field.dart';

class ChangePasswordScreen extends StatefulWidget {
  /// True right after signing in with a temporary password: no way back until changed
  final bool forced;

  /// Called after the password is changed (e.g. continue to the home screen)
  final VoidCallback? onChanged;

  const ChangePasswordScreen({super.key, this.forced = false, this.onChanged});

  @override
  State<ChangePasswordScreen> createState() => _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends State<ChangePasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _current = TextEditingController();
  final _next = TextEditingController();
  final _confirm = TextEditingController();
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _current.dispose();
    _next.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ApiService().post(ApiConfig.changePassword, data: {
        'currentPassword': _current.text,
        'newPassword': _next.text,
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Password changed.')));
      if (widget.onChanged != null) {
        widget.onChanged!();
      } else {
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      setState(() => _error = ApiService.getErrorMessage(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !widget.forced,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Change password'),
          automaticallyImplyLeading: !widget.forced,
        ),
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Form(
                key: _formKey,
                child: ListView(
                  padding: const EdgeInsets.all(24),
                  children: [
                    if (widget.forced) ...[
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: AppColors.warning.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Text(
                          'You signed in with a temporary password from Vendra support. '
                          'Choose your own password to continue.',
                        ),
                      ),
                      const SizedBox(height: 20),
                    ],
                    VendraTextField(
                      label: widget.forced ? 'Temporary password' : 'Current password',
                      controller: _current,
                      obscureText: true,
                      prefixIcon: Icons.lock_outline,
                      validator: (v) => (v == null || v.isEmpty) ? 'Enter your current password' : null,
                    ),
                    const SizedBox(height: 16),
                    VendraTextField(
                      label: 'New password',
                      hint: 'At least 8 characters',
                      controller: _next,
                      obscureText: true,
                      prefixIcon: Icons.lock_reset,
                      validator: (v) {
                        if (v == null || v.length < 8) return 'Use at least 8 characters';
                        if (v == _current.text) return 'Choose a different password';
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    VendraTextField(
                      label: 'Confirm new password',
                      controller: _confirm,
                      obscureText: true,
                      prefixIcon: Icons.lock_reset,
                      validator: (v) => v != _next.text ? 'Passwords don\'t match' : null,
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 16),
                      Text(_error!, style: const TextStyle(color: AppColors.error)),
                    ],
                    const SizedBox(height: 24),
                    VendraButton(text: 'Change password', isLoading: _saving, onPressed: _saving ? null : _submit),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// There is no email/SMS service, so password resets go through Vendra support (an admin)
Future<void> showForgotPasswordDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Forgot your password?'),
      content: const Text(
        'Contact Vendra support at admin@vendra.pk with the email you signed up with. '
        'Support will give you a temporary password; after signing in with it you\'ll '
        'be asked to choose a new one.',
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('OK')),
      ],
    ),
  );
}
