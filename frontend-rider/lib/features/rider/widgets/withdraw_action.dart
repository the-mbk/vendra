// ══════════════════════════════════════════════════════════════
// Vendra Rider App - Withdraw earnings to a card
// Runs the shared withdraw flow (amount → card → POST /api/withdrawals)
// and keeps every balance the rider sees in sync with the API's answer.
// ══════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:vendra_rider/vendra_core.dart';

import '../../auth/bloc/auth_bloc.dart';
import '../../auth/bloc/auth_event.dart';
import '../bloc/earnings_bloc.dart';
import '../bloc/rider_home_bloc.dart';

/// Needs [EarningsBloc] and [RiderHomeBloc] above [context] (the signed-in
/// shell provides both). Returns true when a withdrawal was sent.
Future<bool> startRiderWithdrawal(BuildContext context, {required double balance}) async {
  final result = await showWithdrawSheet(context, balance: balance);
  if (result == null || !context.mounted) return false;
  final newBalance = result.walletBalance;
  if (newBalance != null) {
    context.read<AuthBloc>().add(AuthWalletBalanceUpdated(walletBalance: newBalance));
  }
  context.read<EarningsBloc>().add(EarningsWithdrawalCompleted(walletBalance: newBalance));
  context.read<RiderHomeBloc>().add(const RiderHomeRefreshed());
  return true;
}

/// "Withdraw" button used next to a balance
class WithdrawButton extends StatelessWidget {
  final double balance;

  /// White button for the blue balance card
  final bool onDark;

  const WithdrawButton({super.key, required this.balance, this.onDark = false});

  @override
  Widget build(BuildContext context) {
    return ElevatedButton.icon(
      onPressed: () => startRiderWithdrawal(context, balance: balance),
      icon: const Icon(Icons.north_east, size: 18),
      label: Text('Withdraw', style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
      style: ElevatedButton.styleFrom(
        backgroundColor: onDark ? Colors.white : AppColors.secondary,
        foregroundColor: onDark ? AppColors.secondary : Colors.white,
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }
}
