// ══════════════════════════════════════════════════════════════
// Vendra Vendor App - Main Entry Point
// Initializes BLoC providers, theme, and routes
// ══════════════════════════════════════════════════════════════

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:vendra_vendor/vendra_core.dart';

// Config
import 'config/app_routes.dart';

// Auth
import 'features/auth/bloc/auth_bloc.dart';
import 'features/auth/bloc/auth_event.dart';
import 'features/auth/bloc/auth_state.dart';
import 'features/auth/screens/splash_screen.dart';
import 'features/auth/screens/login_screen.dart';

// Vendor
import 'features/vendor/bloc/vendor_product_bloc.dart';
import 'features/vendor/bloc/vendor_order_bloc.dart';
import 'features/vendor/bloc/pos_bloc.dart';
import 'features/vendor/screens/vendor_dashboard_screen.dart';
import 'features/vendor/screens/add_edit_product_screen.dart';
import 'features/vendor/screens/pending_approval_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const VendraVendorApp());
}

/// Root navigator, so app-wide events (an expired session) can change screens
final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();

class VendraVendorApp extends StatefulWidget {
  const VendraVendorApp({super.key});

  @override
  State<VendraVendorApp> createState() => _VendraVendorAppState();
}

class _VendraVendorAppState extends State<VendraVendorApp> {
  final AuthBloc _authBloc = AuthBloc();
  StreamSubscription<AuthState>? _authSub;

  /// Several requests can fail with 401 at once — sign out only once
  bool _handlingSessionExpiry = false;

  @override
  void initState() {
    super.initState();
    ApiService.onSessionExpired = _onSessionExpired;
    // Signing in again re-arms the handler
    _authSub = _authBloc.stream.listen((state) {
      if (state is Authenticated) _handlingSessionExpiry = false;
    });
  }

  @override
  void dispose() {
    ApiService.onSessionExpired = null;
    _authSub?.cancel();
    _authBloc.close();
    super.dispose();
  }

  /// The server rejected the stored token (TOKEN_EXPIRED / INVALID_TOKEN)
  void _onSessionExpired() {
    if (_handlingSessionExpiry) return;
    // Only a signed-in session can expire; the splash check handles a stale token itself
    if (_authBloc.state is! Authenticated) return;
    _handlingSessionExpiry = true;

    // Clears storage, stops the notification inbox + socket, emits Unauthenticated
    _authBloc.add(LogoutRequested());
    appNavigatorKey.currentState?.pushNamedAndRemoveUntil(AppRoutes.login, (_) => false);
    NotificationCenter.messengerKey.currentState
      ?..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(
        content: Text('Your session has expired. Please sign in again.'),
        behavior: SnackBarBehavior.floating,
      ));
  }

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider<AuthBloc>.value(value: _authBloc),
        BlocProvider<VendorProductBloc>(create: (_) => VendorProductBloc()),
        BlocProvider<VendorOrderBloc>(create: (_) => VendorOrderBloc()),
        BlocProvider<PosBloc>(create: (_) => PosBloc()),
      ],
      child: MaterialApp(
        title: 'Vendra Vendor',
        debugShowCheckedModeBanner: false,
        // FR09: NotificationCenter shows a banner for every new notification
        scaffoldMessengerKey: NotificationCenter.messengerKey,
        navigatorKey: appNavigatorKey,
        theme: AppTheme.lightTheme,

        initialRoute: AppRoutes.splash,

        routes: {
          AppRoutes.splash: (context) => const SplashScreen(),
          AppRoutes.login: (context) => const LoginScreen(),
          AppRoutes.vendorDashboard: (context) => const VendorDashboardScreen(),
          AppRoutes.addProduct: (context) => const AddEditProductScreen(),
        },

        onGenerateRoute: (settings) {
          if (settings.name == AppRoutes.editProduct) {
            final product = settings.arguments as ProductModel;
            return MaterialPageRoute(builder: (context) => AddEditProductScreen(product: product));
          }

          if (settings.name == AppRoutes.vendorPendingApproval) {
            final user = settings.arguments as UserModel;
            return MaterialPageRoute(builder: (context) => PendingApprovalScreen(user: user));
          }

          return null;
        },
      ),
    );
  }
}
