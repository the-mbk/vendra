// ══════════════════════════════════════════════════════════════
// Vendra App - Vendor Profile Screen
// Shows vendor info and logout
// ══════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../config/app_theme.dart';
import '../../../config/app_routes.dart';
import '../../auth/bloc/auth_bloc.dart';
import '../../auth/bloc/auth_event.dart';
import '../../auth/bloc/auth_state.dart';

class VendorProfileScreen extends StatelessWidget {
  const VendorProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Text('Profile', style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.w600)),
        ),
        Expanded(
          child: BlocBuilder<AuthBloc, AuthState>(
            builder: (context, state) {
              if (state is Authenticated) {
                final user = state.user;
                return SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    children: [
                  // Avatar
                  CircleAvatar(
                    radius: 48,
                    backgroundColor: AppColors.secondary,
                    child: Text(
                      user.fullName.isNotEmpty ? user.fullName[0].toUpperCase() : 'V',
                      style: GoogleFonts.poppins(fontSize: 36, fontWeight: FontWeight.w600, color: Colors.white),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(user.fullName, style: GoogleFonts.poppins(fontSize: 20, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  Text(user.email, style: GoogleFonts.poppins(color: AppColors.textSecondary)),
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.secondary.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text('Vendor', style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.secondary)),
                  ),

                  const SizedBox(height: 24),

                  // Store info card
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8)],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Store Information', style: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w600)),
                        const Divider(height: 20),
                        _infoRow(Icons.storefront, 'Store Name', user.storeName ?? 'N/A'),
                        const SizedBox(height: 12),
                        _infoRow(Icons.badge, 'Vendor ID', '#${user.vendorId ?? "N/A"}'),
                        const SizedBox(height: 12),
                        _infoRow(Icons.verified, 'Status', 'Approved'),
                      ],
                    ),
                  ),

                  const SizedBox(height: 32),

                  // Logout button
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () {
                        context.read<AuthBloc>().add(LogoutRequested());
                        Navigator.pushNamedAndRemoveUntil(context, AppRoutes.login, (route) => false);
                      },
                      icon: const Icon(Icons.logout),
                      label: const Text('Logout'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.error,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                ],
              ),
            );
          }
          return const Center(child: CircularProgressIndicator());
        },
          ),
        ),
      ],
    );
  }

  Widget _infoRow(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, size: 18, color: AppColors.textSecondary),
        const SizedBox(width: 10),
        Text('$label: ', style: GoogleFonts.poppins(fontSize: 13, color: AppColors.textSecondary)),
        Text(value, style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w500)),
      ],
    );
  }
}
