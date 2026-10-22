// ══════════════════════════════════════════════════════════════
// Vendra Rider App - Profile tab
// Account details, wallet (withdraw), location settings, change password, logout.
// ══════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:vendra_rider/vendra_core.dart';

import '../../auth/bloc/auth_bloc.dart';
import '../../auth/bloc/auth_event.dart';
import '../../auth/bloc/auth_state.dart';
import '../bloc/earnings_bloc.dart';
import '../bloc/rider_home_bloc.dart';
import '../models/rider_models.dart';
import '../services/rider_location_service.dart';
import '../widgets/location_settings_sheet.dart';
import '../widgets/withdraw_action.dart';

class ProfileTab extends StatelessWidget {
  const ProfileTab({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthBloc>().state;
    final user = auth is Authenticated ? auth.user : null;
    final home = context.watch<RiderHomeBloc>().state;
    final loggingOut = auth is AuthLoading;
    // Freshest first: the wallet as loaded (and updated by a withdrawal), then earnings, then /me
    final earnings = context.watch<EarningsBloc>().state;
    final balance = earnings is EarningsLoaded
        ? earnings.wallet.balance
        : home.earnings?.walletBalance ?? user?.walletBalance ?? 0;

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
                  Text(user?.fullName ?? 'Rider',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.poppins(fontSize: 20, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                  const SizedBox(height: 6),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _pill(vehicleLabel(home.vehicleType ?? user?.vehicleType), AppColors.secondary),
                      const SizedBox(width: 8),
                      _pill(home.isOnline ? 'Online' : 'Offline',
                          home.isOnline ? AppColors.success : AppColors.textSecondary),
                    ],
                  ),
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
                ListTile(
                  leading: const Icon(Icons.account_balance_wallet_outlined, color: AppColors.secondary),
                  title: Text('Wallet', style: GoogleFonts.poppins(fontSize: 13, color: AppColors.textSecondary)),
                  subtitle: Text(rs(balance),
                      style: GoogleFonts.poppins(
                          fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                  trailing: WithdrawButton(balance: balance),
                ),
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
              label: Text('Logout', style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w600)),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.error,
                foregroundColor: Colors.white,
                elevation: 0,
                minimumSize: const Size.fromHeight(54),
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
      trailing: Text(value, style: GoogleFonts.poppins(fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
    );
  }

  static Widget _pill(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(20)),
      child: Text(text, style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w600, color: color)),
    );
  }
}
