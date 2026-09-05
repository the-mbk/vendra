// ══════════════════════════════════════════════════════════════
// Vendra App - Under Development Placeholder Screen
// Used for Rider, Admin, Escrow, Dispute, GPS tracking
// ══════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../config/app_theme.dart';
import '../../config/app_routes.dart';
import '../auth/bloc/auth_bloc.dart';
import '../auth/bloc/auth_event.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class UnderDevelopmentScreen extends StatelessWidget {
  final String title;

  const UnderDevelopmentScreen({super.key, this.title = 'Feature'});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: Text(title, style: GoogleFonts.poppins(fontWeight: FontWeight.w600))),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                  color: AppColors.secondary.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.construction, size: 48, color: AppColors.secondary),
              ),
              const SizedBox(height: 24),
              Text(
                '🚧 Under Development',
                style: GoogleFonts.poppins(fontSize: 22, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
              ),
              const SizedBox(height: 8),
              Text(
                'This feature is coming soon.\nStay tuned for updates!',
                textAlign: TextAlign.center,
                style: GoogleFonts.poppins(fontSize: 14, color: AppColors.textSecondary, height: 1.5),
              ),
              const SizedBox(height: 32),
              ElevatedButton.icon(
                onPressed: () {
                  context.read<AuthBloc>().add(LogoutRequested());
                  Navigator.pushNamedAndRemoveUntil(context, AppRoutes.login, (route) => false);
                },
                icon: const Icon(Icons.logout),
                label: const Text('Logout'),
                style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
