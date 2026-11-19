// ══════════════════════════════════════════════════════════════
// Vendra Vendor App - Main Entry Point
// Loads the platform config (mode, features, card gateway) first, then
// initializes BLoC providers, theme, and routes
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
import 'features/vendor/bloc/store_location_bloc.dart';
import 'features/vendor/screens/vendor_dashboard_screen.dart';
import 'features/vendor/screens/add_edit_product_screen.dart';
import 'features/vendor/screens/pending_approval_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Never throws and gives up after a few seconds: if the backend is down the
  // app starts on production-safe defaults and retries when a value is needed
  await AppConfig.load(role: 'vendor');
  AppConfig.startLiveUpdates(); // admin policy changes reach the app straight away
  runApp(VendraVendorApp(themeMode: await ThemeCubit.loadSaved()));
}

/// Root navigator, so app-wide events (an expired session) can change screens
final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();

class VendraVendorApp extends StatefulWidget {
  /// The saved light / dark / system choice
  final ThemeMode themeMode;
  const VendraVendorApp({super.key, this.themeMode = ThemeMode.system});

  @override
  State<VendraVendorApp> createState() => _VendraVendorAppState();
}

class _VendraVendorAppState extends State<VendraVendorApp> {
  final AuthBloc _authBloc = AuthBloc();
  late final _themeCubit = ThemeCubit(widget.themeMode);
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
    _themeCubit.close();
    super.dispose();
  }

  /// The server rejected the stored token (TOKEN_EXPIRED / INVALID_TOKEN, or
  /// STAFF_INACTIVE when the owner removed the staff member signed in here)
  void _onSessionExpired() {
    if (_handlingSessionExpiry) return;
    // Only a signed-in session can expire; the splash check handles a stale token itself
    final state = _authBloc.state;
    if (state is! Authenticated) return;
    _handlingSessionExpiry = true;
    // A staff session drops to the owner's sign-in (the email is prefilled there)
    final wasStaff = state.user.staff != null;

    // Clears storage, stops the notification inbox + socket, emits Unauthenticated
    _authBloc.add(LogoutRequested());
    appNavigatorKey.currentState?.pushNamedAndRemoveUntil(AppRoutes.login, (_) => false);
    NotificationCenter.messengerKey.currentState
      ?..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(wasStaff
            ? 'Your staff session has ended. Ask the store owner to sign in.'
            : 'Your session has expired. Please sign in again.'),
        behavior: SnackBarBehavior.floating,
      ));
  }

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider<AuthBloc>.value(value: _authBloc),
        BlocProvider<ThemeCubit>.value(value: _themeCubit),
        BlocProvider<VendorProductBloc>(create: (_) => VendorProductBloc()),
        BlocProvider<VendorOrderBloc>(create: (_) => VendorOrderBloc()),
        BlocProvider<PosBloc>(create: (ctx) => PosBloc(productLookup: ctx.read<VendorProductBloc>().productById)),
        BlocProvider<StoreLocationBloc>(create: (_) => StoreLocationBloc()),
      ],
      child: BlocBuilder<ThemeCubit, ThemeMode>(
        builder: (context, themeMode) => MaterialApp(
          title: 'Vendra Vendor',
          debugShowCheckedModeBanner: false,
          // FR09: NotificationCenter shows a banner for every new notification
          scaffoldMessengerKey: NotificationCenter.messengerKey,
          navigatorKey: appNavigatorKey,
          theme: AppTheme.lightTheme,
          darkTheme: AppTheme.darkTheme,
          themeMode: themeMode,
          // "DEVELOPMENT" badge on every screen while the backend runs in development mode
          builder: (context, child) => ThemeScope(child: DevBanner(child: ConnectionBanner(child: child ?? const SizedBox.shrink()))),

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
      ),
    );
  }
}
