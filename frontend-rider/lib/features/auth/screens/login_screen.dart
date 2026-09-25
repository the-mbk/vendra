// ══════════════════════════════════════════════════════════════
// Vendra Rider App - Login Screen (FR05)
// Email/password login sent with role: 'rider'. A non-rider account
// gets 403 WRONG_APP and the server's message is shown.
// ══════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:vendra_rider/vendra_core.dart';

import '../../../config/app_routes.dart';
import '../auth_navigation.dart';
import '../bloc/auth_bloc.dart';
import '../bloc/auth_event.dart';
import '../bloc/auth_state.dart';
import '../widgets/vendra_logo.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    context.read<AuthBloc>().add(LoginRequested(
          email: _emailController.text.trim(),
          password: _passwordController.text,
        ));
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<AuthBloc, AuthState>(
      // Login stays under Sign-up in the stack; only the visible screen reacts
      listenWhen: (_, __) => ModalRoute.of(context)?.isCurrent ?? true,
      listener: (context, state) {
        if (state is Authenticated) {
          openSignedInHome(context, state.user);
        } else if (state is AuthError) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(state.message),
            backgroundColor: AppColors.error,
            behavior: SnackBarBehavior.floating,
          ));
        }
      },
      builder: (context, state) {
        final isLoading = state is AuthLoading;
        return Scaffold(
          backgroundColor: AppColors.background,
          body: SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                children: [
                  const SizedBox(height: 40),
                  const VendraLogo(),
                  const SizedBox(height: 28),
                  Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 20, offset: const Offset(0, 4))],
                    ),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Welcome Back',
                              style: GoogleFonts.poppins(fontSize: 24, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                          Text('Sign in to start taking deliveries',
                              style: GoogleFonts.poppins(fontSize: 13, color: AppColors.textSecondary)),
                          const SizedBox(height: 20),
                          VendraTextField(
                            label: 'Email',
                            hint: 'rider@example.com',
                            controller: _emailController,
                            keyboardType: TextInputType.emailAddress,
                            prefixIcon: Icons.email_outlined,
                            validator: (v) {
                              if (v == null || v.isEmpty) return 'Email is required';
                              if (!v.contains('@')) return 'Enter a valid email';
                              return null;
                            },
                          ),
                          const SizedBox(height: 16),
                          VendraTextField(
                            label: 'Password',
                            hint: 'Enter your password',
                            controller: _passwordController,
                            obscureText: _obscurePassword,
                            prefixIcon: Icons.lock_outline,
                            suffixIcon: IconButton(
                              icon: Icon(_obscurePassword ? Icons.visibility_off_outlined : Icons.visibility_outlined, size: 20),
                              onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                            ),
                            validator: (v) {
                              if (v == null || v.isEmpty) return 'Password is required';
                              if (v.length < 6) return 'Password must be at least 6 characters';
                              return null;
                            },
                          ),
                          Align(
                            alignment: Alignment.centerRight,
                            child: TextButton(
                              onPressed: isLoading ? null : () => showForgotPasswordDialog(context),
                              child: Text('Forgot password?',
                                  style: GoogleFonts.poppins(
                                      fontSize: 13, fontWeight: FontWeight.w500, color: AppColors.secondary)),
                            ),
                          ),
                          const SizedBox(height: 8),
                          VendraButton(text: 'Login', icon: Icons.arrow_forward, isLoading: isLoading, onPressed: _submit),
                          const SizedBox(height: 20),
                          Text('Quick demo login',
                              style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              _demoChip(label: 'Bilal (Karachi)', email: 'bilal@rider.pk', enabled: !isLoading),
                              _demoChip(label: 'Hamza (Lahore)', email: 'hamza@rider.pk', enabled: !isLoading),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text("Don't have an account?  ", style: GoogleFonts.poppins(color: AppColors.textSecondary)),
                      GestureDetector(
                        onTap: isLoading ? null : () => Navigator.pushNamed(context, AppRoutes.signup),
                        child: Text('Become a rider',
                            style: GoogleFonts.poppins(color: AppColors.secondary, fontWeight: FontWeight.w600)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 32),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _demoChip({required String label, required String email, required bool enabled}) {
    return ActionChip(
      label: Text(label, style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w500)),
      onPressed: enabled
          ? () {
              _emailController.text = email;
              _passwordController.text = 'password123';
              context.read<AuthBloc>().add(LoginRequested(email: email, password: 'password123'));
            }
          : null,
      backgroundColor: AppColors.secondary.withValues(alpha: 0.08),
      side: BorderSide(color: AppColors.secondary.withValues(alpha: 0.35)),
    );
  }
}
