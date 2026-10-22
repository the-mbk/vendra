// ══════════════════════════════════════════════════════════════
// Vendra App - Demo login panel (development only)
// Lists the seeded accounts for this app's role from
// GET /api/public-config (`demoAccounts`). Tapping one fills the form and
// signs in. Renders nothing in production (`features.demoLogin` off).
//
//   DemoLoginPanel(
//     role: 'vendor',
//     emailController: _email, passwordController: _password,
//     onLogin: (email, password) => context.read<AuthBloc>().add(LoginRequested(...)),
//   )
// ══════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../config/app_theme.dart';
import '../models/app_config_model.dart';
import '../services/app_config.dart';

class DemoLoginPanel extends StatelessWidget {
  /// customer | vendor | rider
  final String role;

  /// Called with the account's credentials — trigger the app's normal login
  final void Function(String email, String password) onLogin;

  /// Filled in before [onLogin] so the user sees what was used
  final TextEditingController? emailController;
  final TextEditingController? passwordController;

  /// Disable while a sign-in is already running
  final bool enabled;

  const DemoLoginPanel({
    super.key,
    required this.role,
    required this.onLogin,
    this.emailController,
    this.passwordController,
    this.enabled = true,
  });

  void _use(DemoAccount account) {
    emailController?.text = account.email;
    passwordController?.text = account.password;
    onLogin(account.email, account.password);
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AppConfig>(
      valueListenable: AppConfig.notifier,
      builder: (context, config, _) {
        final accounts = config.features.demoLogin ? config.demoAccountsFor(role) : const <DemoAccount>[];
        if (accounts.isEmpty) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.science_outlined, size: 14, color: Colors.amber.shade800),
                const SizedBox(width: 6),
                Text(
                  'Demo accounts',
                  style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textSecondary),
                ),
                const SizedBox(width: 6),
                Text('· development only', style: GoogleFonts.poppins(fontSize: 11, color: AppColors.textLight)),
              ],
            ),
            const SizedBox(height: 8),
            for (final a in accounts)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Material(
                  color: AppColors.secondary.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(10),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(10),
                    onTap: enabled ? () => _use(a) : null,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      child: Row(
                        children: [
                          CircleAvatar(
                            radius: 14,
                            backgroundColor: AppColors.secondary.withValues(alpha: 0.12),
                            child: Text(
                              a.name.isNotEmpty ? a.name[0].toUpperCase() : '?',
                              style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.secondary),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(a.name, style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w500)),
                                Text(
                                  [a.email, if (a.note != null && a.note!.isNotEmpty) a.note!].join(' · '),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: GoogleFonts.poppins(fontSize: 11, color: AppColors.textSecondary),
                                ),
                              ],
                            ),
                          ),
                          const Icon(Icons.login, size: 18, color: AppColors.secondary),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
