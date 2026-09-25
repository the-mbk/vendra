// ══════════════════════════════════════════════════════════════
// Customer Orders Screen — full-screen route with app bar
// ══════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:vendra_customer/vendra_core.dart';
import 'customer_orders_panel.dart';

class CustomerOrdersScreen extends StatelessWidget {
  const CustomerOrdersScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text('My Orders', style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
      ),
      body: const CustomerOrdersPanel(showTopPadding: false),
    );
  }
}
