// ══════════════════════════════════════════════════════════════
// Vendra App - Splash Screen
// Checks auth state and navigates accordingly
// ══════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../config/app_theme.dart';
import '../../../config/app_routes.dart';
import '../bloc/auth_bloc.dart';
import '../bloc/auth_event.dart';
import '../bloc/auth_state.dart';

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
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeIn),
    );
    _controller.forward();

    // Check auth after a brief delay for splash effect
    Future.delayed(const Duration(milliseconds: 1800), () {
      context.read<AuthBloc>().add(CheckAuthRequested());
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _navigateBasedOnRole(String role) {
    String route;
    switch (role) {
      case 'vendor':
        route = AppRoutes.vendorDashboard;
        break;
      case 'rider':
        route = AppRoutes.riderPlaceholder;
        break;
      case 'customer':
      default:
        route = AppRoutes.customerHome;
        break;
    }
    Navigator.pushReplacementNamed(context, route);
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<AuthBloc, AuthState>(
      listener: (context, state) {
        if (state is Authenticated) {
          // Unapproved vendors go to pending approval screen
          if (state.user.role == 'vendor' && state.user.isApproved != true) {
            Navigator.pushReplacementNamed(
              context,
              AppRoutes.vendorPendingApproval,
              arguments: state.user,
            );
          } else {
            _navigateBasedOnRole(state.user.role);
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
                // Vendra logo with Pakistan flag
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Vendra',
                      style: GoogleFonts.poppins(
                        fontSize: 42,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Pakistan flag icon
                    Container(
                      width: 32,
                      height: 22,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(3),
                        border: Border.all(color: Colors.white24),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            flex: 1,
                            child: Container(color: Colors.white),
                          ),
                          Expanded(
                            flex: 3,
                            child: Container(color: AppColors.pakistanGreen),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  "Pakistan's Leading Marketplace",
                  style: GoogleFonts.poppins(
                    fontSize: 14,
                    color: Colors.white70,
                  ),
                ),
                const SizedBox(height: 48),
                const SizedBox(
                  width: 28,
                  height: 28,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    color: Colors.white70,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
