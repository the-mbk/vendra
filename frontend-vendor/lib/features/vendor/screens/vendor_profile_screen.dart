// ══════════════════════════════════════════════════════════════
// Vendra App - Vendor Profile Screen
// Shows the store header (cover photo + logo; the owner can change them),
// vendor info, wallet (+ withdraw to card) / disputes / change-password
// shortcuts and logout, plus the shop-staff tools: who is signed in on this
// device, Switch user / Back to owner, and (owner only) Shop staff and
// Receipt settings. Customer reviews are open to everyone.
// ══════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:vendra_vendor/vendra_core.dart';
import '../widgets/tab_header.dart';
import '../../../config/app_routes.dart';
import '../../auth/bloc/auth_bloc.dart';
import '../../auth/bloc/auth_event.dart';
import '../../auth/bloc/auth_state.dart';
import 'vendor_disputes_screen.dart';
import 'wallet_screen.dart';
import '../widgets/wallet_widgets.dart';
import '../../staff/permissions.dart';
import '../../staff/screens/staff_screen.dart';
import '../../staff/widgets/switch_user.dart';
import 'receipt_settings_screen.dart';
import 'vendor_reviews_screen.dart';
import '../widgets/store_photo_header.dart';

class VendorProfileScreen extends StatelessWidget {
  const VendorProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const TabHeader(icon: Icons.person, title: 'Profile', subtitle: 'Your store, wallet and account'),
        Expanded(
          child: BlocBuilder<AuthBloc, AuthState>(
            builder: (context, state) {
              if (state is Authenticated) {
                final user = state.user;
                final staff = user.staff;
                final isOwner = user.can(Perm.owner);
                return SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    children: [
                  // The store as customers see it; the owner changes its logo / cover photo here
                  StorePhotoHeader(
                    user: user,
                    onChanged: () => context.read<AuthBloc>().add(RefreshUserRequested()),
                  ),
                  const SizedBox(height: 24),

                  // Avatar
                  CircleAvatar(
                    radius: 48,
                    backgroundColor: AppColors.secondary,
                    child: Text(
                      (staff?.fullName ?? user.fullName).isNotEmpty
                          ? (staff?.fullName ?? user.fullName)[0].toUpperCase()
                          : 'V',
                      style: GoogleFonts.poppins(fontSize: 36, fontWeight: FontWeight.w600, color: Colors.white),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(staff?.fullName ?? user.fullName,
                      textAlign: TextAlign.center,
                      style: GoogleFonts.poppins(fontSize: 20, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                  const SizedBox(height: 4),
                  Text(staff != null ? 'Staff at ${user.storeName ?? 'this store'}' : user.email,
                      textAlign: TextAlign.center,
                      style: GoogleFonts.poppins(color: AppColors.textSecondary)),
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.secondary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(staff?.roleLabel ?? 'Owner',
                        style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.secondary)),
                  ),

                  const SizedBox(height: 24),

                  // Store info card
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8)],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Store Information',
                            style: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                        const Divider(height: 20),
                        _infoRow(Icons.storefront, 'Store Name', user.storeName ?? 'N/A'),
                        const SizedBox(height: 12),
                        _infoRow(Icons.badge, 'Vendor ID', '#${user.vendorId ?? "N/A"}'),
                        const SizedBox(height: 12),
                        _infoRow(Icons.verified, 'Status', 'Approved'),
                      ],
                    ),
                  ),

                  const SizedBox(height: 16),
                  // Shop device: anyone can hand over to someone else with a PIN
                  _actionTile(Icons.switch_account_outlined, 'Switch user', 'Signed in: ${signedInLabel(user)}',
                      () => showSwitchUser(context)),
                  if (staff != null)
                    _actionTile(Icons.storefront_outlined, 'Back to owner', "Needs the owner's password",
                        () => backToOwner(context)),
                  _linkTile(context, Icons.star_outline_rounded, 'Customer reviews', 'What customers say about your products',
                      const VendorReviewsScreen()),
                  if (isOwner) ...[
                    _linkTile(context, Icons.groups_outlined, 'Shop staff', 'Cashiers, packers and inventory managers',
                        const StaffScreen()),
                    _linkTile(context, Icons.receipt_outlined, 'Receipt settings', 'Slip header, footer and scan-to-pay account',
                        const ReceiptSettingsScreen()),
                    _linkTile(context, Icons.account_balance_wallet_outlined, 'Wallet',
                        'Rs. ${NumberFormat('#,##0').format(user.walletBalance)} · escrow releases', const WalletScreen()),
                    _actionTile(Icons.north_east, AppConfig.current.payments.withdrawLabel,
                        'Send your wallet balance to ${AppConfig.current.payments.payoutDestination}',
                        () => startWithdrawal(context, balance: user.walletBalance)),
                    _linkTile(context, Icons.gavel_outlined, 'Disputes', 'Disputes on your orders', const VendorDisputesScreen()),
                    _linkTile(context, Icons.lock_reset, 'Change password', 'Choose a new sign-in password',
                        const ChangePasswordScreen()),
                  ],

                  const SizedBox(height: 16),

                  // Logout button
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () {
                        context.read<AuthBloc>().add(LogoutRequested());
                        Navigator.pushNamedAndRemoveUntil(context, AppRoutes.login, (route) => false);
                      },
                      icon: const Icon(Icons.logout),
                      label: Text(staff != null ? 'Sign out of this device' : 'Logout'),
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
      ),
    );
  }

  Widget _linkTile(BuildContext context, IconData icon, String title, String subtitle, Widget screen) =>
      _actionTile(icon, title, subtitle, () => Navigator.push(context, MaterialPageRoute(builder: (_) => screen)));

  Widget _actionTile(IconData icon, String title, String subtitle, VoidCallback onTap) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8)],
      ),
      child: ListTile(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        leading: Icon(icon, color: AppColors.secondary),
        title: Text(title, style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w600)),
        subtitle: Text(subtitle, style: GoogleFonts.poppins(fontSize: 12, color: AppColors.textSecondary)),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }

  Widget _infoRow(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, size: 18, color: AppColors.textSecondary),
        const SizedBox(width: 10),
        Text('$label: ', style: GoogleFonts.poppins(fontSize: 13, color: AppColors.textSecondary)),
        Expanded(
          child: Text(value,
              overflow: TextOverflow.ellipsis, style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w500)),
        ),
      ],
    );
  }
}
