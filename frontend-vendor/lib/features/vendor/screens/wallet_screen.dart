// ══════════════════════════════════════════════════════════════
// Vendra Vendor App - Wallet Screen (FR03)
// Online order payments sit in escrow until the order is delivered and
// the dispute window passes; the store then receives the subtotal minus
// the platform commission ("escrow_release"). Withdraw sends the balance
// out; failed payouts come back. The body is the shared MoneyLedgerView
// (balance, money on hold, plain-language rows with the commission
// breakdown, withdrawal history), also shown on the Ledger tab.
// ══════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:vendra_vendor/vendra_core.dart';

import '../widgets/money_ledger.dart';

class WalletScreen extends StatelessWidget {
  const WalletScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: Text('Wallet', style: GoogleFonts.poppins(fontWeight: FontWeight.w600))),
      body: const MoneyLedgerView(),
    );
  }
}
