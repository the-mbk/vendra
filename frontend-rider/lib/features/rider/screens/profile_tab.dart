// ══════════════════════════════════════════════════════════════
// Vendra Rider App - Profile tab
// Account details, location settings, change password, logout.
// ══════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:vendra_rider/vendra_core.dart';

import '../../auth/bloc/auth_bloc.dart';
import '../../auth/bloc/auth_event.dart';
import '../../auth/bloc/auth_state.dart';
import '../bloc/rider_home_bloc.dart';
import '../models/rider_models.dart';
import '../services/rider_location_service.dart';
import '../widgets/location_settings_sheet.dart';

class ProfileTab extends StatelessWidget {
  const ProfileTab({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthBloc>().state;
    final user = auth is Authenticated ? auth.user : null;
    final home = context.watch<RiderHomeBloc>().state;
    final loggingOut = auth is AuthLoading;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Profile'), automaticallyImplyLeading: false),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  CircleAvatar(
                    radius: 34,
                    backgroundColor: AppColors.secondary,
                    child: Icon(
                      _vehicleIcon(home.vehicleType ?? user?.vehicleType),
                      color: Colors.white,
                      size: 32,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(user?.fullName ?? 'Rider', style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.w700)),
                  Text(vehicleLabel(home.vehicleType ?? user?.vehicleType),
                      style: GoogleFonts.poppins(color: AppColors.textSecondary)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Card(
            child: Column(
              children: [
                _tile(Icons.email_outlined, 'Email', user?.email ?? '—'),
                const Divider(height: 1),
                _tile(Icons.phone_outlined, 'Phone', user?.phone ?? '—'),
                const Divider(height: 1),
                _tile(Icons.account_balance_wallet_outlined, 'Wallet',
                    rs(home.earnings?.walletBalance ?? user?.walletBalance ?? 0)),
                const Divider(height: 1),
                _tile(Icons.circle, 'Status', home.isOnline ? 'Online' : 'Offline',
                    iconColor: home.isOnline ? AppColors.success : AppColors.textLight),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Card(
            child: ListenableBuilder(
              listenable: RiderLocationService(),
              builder: (context, _) {
                final sim = RiderLocationService().simulate;
                return ListTile(
                  leading: Icon(sim ? Icons.science_outlined : Icons.my_location,
                      color: sim ? AppColors.reservedAmber : AppColors.secondary),
                  title: Text('Location settings', style: GoogleFonts.poppins(fontWeight: FontWeight.w500)),
                  subtitle: Text(sim ? 'Simulated location is ON' : 'Using device GPS',
                      style: GoogleFonts.poppins(
                          fontSize: 12, color: sim ? AppColors.reservedAmber : AppColors.textSecondary)),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => showLocationSettings(context),
                );
              },
            ),
          ),
          const SizedBox(height: 8),
          Card(
            child: ListTile(
              leading: const Icon(Icons.lock_reset, color: AppColors.secondary),
              title: Text('Change password', style: GoogleFonts.poppins(fontWeight: FontWeight.w500)),
              trailing: const Icon(Icons.chevron_right),
              onTap: loggingOut
                  ? null
                  : () => Navigator.of(context).push(
                        MaterialPageRoute<bool>(builder: (_) => const ChangePasswordScreen()),
                      ),
            ),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: loggingOut ? null : () => context.read<AuthBloc>().add(LogoutRequested()),
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
          if (home.activeOrderId != null) ...[
            const SizedBox(height: 8),
            Text(
              'You have an active delivery — you stay online until it is delivered.',
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(fontSize: 12, color: AppColors.textSecondary),
            ),
          ],
        ],
      ),
    );
  }

  static IconData _vehicleIcon(String? type) {
    switch (type) {
      case 'bicycle':
        return Icons.pedal_bike;
      case 'car':
        return Icons.directions_car;
      default:
        return Icons.two_wheeler;
    }
  }

  Widget _tile(IconData icon, String label, String value, {Color? iconColor}) {
    return ListTile(
      leading: Icon(icon, color: iconColor ?? AppColors.secondary, size: iconColor != null ? 14 : 22),
      title: Text(label, style: GoogleFonts.poppins(fontSize: 13, color: AppColors.textSecondary)),
      trailing: Text(value, style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
    );
  }
}
