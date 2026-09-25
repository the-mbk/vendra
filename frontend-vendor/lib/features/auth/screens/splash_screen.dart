// ══════════════════════════════════════════════════════════════
// Vendra Vendor App - Splash Screen
// Checks auth state and navigates accordingly
// ══════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:vendra_vendor/vendra_core.dart';
import '../../../config/app_routes.dart';
import '../bloc/auth_bloc.dart';
import '../bloc/auth_event.dart';
import '../bloc/auth_state.dart';
import 'post_sign_in.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 1500));
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(CurvedAnimation(parent: _controller, curve: Curves.easeIn));
    _controller.forward();

    Future.delayed(const Duration(milliseconds: 1800), () {
      if (!mounted) return;
      context.read<AuthBloc>().add(CheckAuthRequested());
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<AuthBloc, AuthState>(
      listener: (context, state) {
        if (state is Authenticated) {
          if (!state.user.isVendor) {
            // A non-vendor account (customer/rider/admin) was signed in on this device.
            // This app only serves vendors, so sign them out and send to login.
            context.read<AuthBloc>().add(LogoutRequested());
            Navigator.pushReplacementNamed(context, AppRoutes.login);
          } else {
            // Temporary password → choose a new one first, then dashboard / pending approval
            continueAfterSignIn(context, state.user);
          }
        } else if (state is Unauthenticated || state is AuthError) {
          Navigator.pushReplacementNamed(context, AppRoutes.login);
        }
      },
      child: Scaffold(
        backgroundColor: AppColors.secondary,
        body: Center(
          child: FadeTransition(
            opacity: _fadeAnimation,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('Vendra', style: GoogleFonts.poppins(fontSize: 42, fontWeight: FontWeight.w700, color: Colors.white)),
                    const SizedBox(width: 8),
                    Container(
                      width: 32,
                      height: 22,
                      decoration: BoxDecoration(borderRadius: BorderRadius.circular(3), border: Border.all(color: Colors.white24)),
                      child: Row(
                        children: [
                          Expanded(flex: 1, child: Container(color: Colors.white)),
                          Expanded(flex: 3, child: Container(color: AppColors.pakistanGreen)),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text('Vendor Portal', style: GoogleFonts.poppins(fontSize: 14, color: Colors.white70)),
                const SizedBox(height: 48),
                const SizedBox(
                  width: 28,
                  height: 28,
                  child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white70),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
