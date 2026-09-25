// ══════════════════════════════════════════════════════════════
// Vendra Customer App - Login Screen
// Single-role (customer) version of the Stitch login design:
// email/password, login button, signup toggle
// ══════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:vendra_customer/vendra_core.dart';
import '../../../config/app_routes.dart';
import '../bloc/auth_bloc.dart';
import '../bloc/auth_event.dart';
import '../bloc/auth_state.dart';

/// After a successful sign-in (login or splash auto-login): go to home, or —
/// when an admin issued a temporary password — to the forced change-password
/// screen first, which then continues to home.
void continueAfterSignIn(BuildContext context, UserModel user) {
  final navigator = Navigator.of(context);
  if (!user.mustChangePassword) {
    navigator.pushReplacementNamed(AppRoutes.customerHome);
    return;
  }
  navigator.pushReplacement(MaterialPageRoute(
    builder: (_) => ChangePasswordScreen(
      forced: true,
      onChanged: () => navigator.pushNamedAndRemoveUntil(AppRoutes.customerHome, (_) => false),
    ),
  ));
}

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();

  bool _isSignup = false;
  bool _obscurePassword = true;

  void _submit() {
    if (!_formKey.currentState!.validate()) return;

    if (_isSignup) {
      context.read<AuthBloc>().add(SignupRequested(
            fullName: _nameController.text.trim(),
            email: _emailController.text.trim(),
            password: _passwordController.text,
            role: 'customer',
            phone: _phoneController.text.trim().isNotEmpty ? _phoneController.text.trim() : null,
          ));
    } else {
      context.read<AuthBloc>().add(LoginRequested(
            email: _emailController.text.trim(),
            password: _passwordController.text,
          ));
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _nameController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<AuthBloc, AuthState>(
      listener: (context, state) {
        if (state is Authenticated) {
          // FR09: load the inbox and open the realtime socket for this user
          NotificationCenter().start();
          // Signed in with a temporary password from support: choose a new one first
          continueAfterSignIn(context, state.user);
        } else if (state is AuthError) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(state.message),
              backgroundColor: AppColors.error,
              behavior: SnackBarBehavior.floating,
            ),
          );
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

                  // ── Vendra Logo ──
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        'Vendra',
                        style: GoogleFonts.poppins(
                          fontSize: 36,
                          fontWeight: FontWeight.w700,
                          color: AppColors.secondary,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        width: 28,
                        height: 20,
                        decoration: BoxDecoration(borderRadius: BorderRadius.circular(2)),
                        child: Row(
                          children: [
                            Expanded(flex: 1, child: Container(color: Colors.white)),
                            Expanded(
                              flex: 3,
                              child: Container(
                                decoration: const BoxDecoration(
                                  color: AppColors.pakistanGreen,
                                  borderRadius: BorderRadius.horizontal(right: Radius.circular(2)),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    "Pakistan's Leading Marketplace",
                    style: GoogleFonts.poppins(fontSize: 13, color: AppColors.textSecondary),
                  ),

                  const SizedBox(height: 28),

                  // ── Form Card ──
                  Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 20, offset: const Offset(0, 4)),
                      ],
                    ),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _isSignup ? 'Create Account' : 'Welcome Back',
                            style: GoogleFonts.poppins(fontSize: 24, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
                          ),
                          const SizedBox(height: 20),

                          if (_isSignup) ...[
                            VendraTextField(
                              label: 'Full Name',
                              hint: 'Enter your full name',
                              controller: _nameController,
                              prefixIcon: Icons.person_outline,
                              validator: (v) => (v == null || v.isEmpty) ? 'Name is required' : null,
                            ),
                            const SizedBox(height: 16),
                            VendraTextField(
                              label: 'Phone Number',
                              hint: '03XX-XXXXXXX',
                              controller: _phoneController,
                              prefixIcon: Icons.phone_outlined,
                              keyboardType: TextInputType.phone,
                            ),
                            const SizedBox(height: 16),
                          ],

                          VendraTextField(
                            label: 'Phone Number or Email',
                            hint: '03XX-XXXXXXX / email@example.com',
                            controller: _emailController,
                            keyboardType: TextInputType.emailAddress,
                            prefixIcon: Icons.person_outline,
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
                              icon: Icon(
                                _obscurePassword ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                                size: 20,
                              ),
                              onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                            ),
                            validator: (v) {
                              if (v == null || v.isEmpty) return 'Password is required';
                              if (v.length < 6) return 'Password must be at least 6 characters';
                              return null;
                            },
                          ),

                          if (!_isSignup) ...[
                            const SizedBox(height: 8),
                            Align(
                              alignment: Alignment.centerRight,
                              child: TextButton(
                                onPressed: () => showForgotPasswordDialog(context),
                                child: Text(
                                  'Forgot?',
                                  style: GoogleFonts.poppins(color: AppColors.secondary, fontWeight: FontWeight.w500),
                                ),
                              ),
                            ),
                          ],

                          const SizedBox(height: 20),

                          VendraButton(
                            text: _isSignup ? 'Sign Up' : 'Login',
                            icon: Icons.arrow_forward,
                            isLoading: isLoading,
                            onPressed: _submit,
                          ),

                          if (!_isSignup) ...[
                            const SizedBox(height: 20),
                            Align(
                              alignment: Alignment.centerLeft,
                              child: Text(
                                'Quick demo login',
                                style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textSecondary),
                              ),
                            ),
                            const SizedBox(height: 10),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                _demoLoginChip(context, label: 'Customer 1', email: 'ahmed@customer.pk'),
                                _demoLoginChip(context, label: 'Customer 2', email: 'fatima@customer.pk'),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 24),

                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        _isSignup ? 'Already have an account?  ' : "Don't have an account?  ",
                        style: GoogleFonts.poppins(color: AppColors.textSecondary),
                      ),
                      GestureDetector(
                        onTap: () => setState(() => _isSignup = !_isSignup),
                        child: Text(
                          _isSignup ? 'Login' : 'Sign up now',
                          style: GoogleFonts.poppins(color: AppColors.secondary, fontWeight: FontWeight.w600),
                        ),
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

  Widget _demoLoginChip(BuildContext context, {required String label, required String email}) {
    return ActionChip(
      label: Text(label, style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w500)),
      onPressed: () {
        _emailController.text = email;
        _passwordController.text = 'password123';
        context.read<AuthBloc>().add(LoginRequested(email: email, password: 'password123'));
      },
      backgroundColor: AppColors.secondary.withValues(alpha: 0.08),
      side: BorderSide(color: AppColors.secondary.withValues(alpha: 0.35)),
    );
  }
}
