// ══════════════════════════════════════════════════════════════
// Vendra Rider App - Main Entry Point
// Loads the platform config (mode, features, card gateway) first, then
// initializes BLoC providers, theme, and routes, and signs the rider
// out (back to login) on logout or when the server rejects the session
// ══════════════════════════════════════════════════════════════

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:vendra_rider/vendra_core.dart';

// Config
import 'config/app_routes.dart';

// Auth
import 'features/auth/bloc/auth_bloc.dart';
import 'features/auth/bloc/auth_event.dart';
import 'features/auth/bloc/auth_state.dart';
import 'features/auth/screens/splash_screen.dart';
import 'features/auth/screens/login_screen.dart';
import 'features/auth/screens/signup_screen.dart';

// Rider
import 'features/rider/bloc/delivery_bloc.dart';
import 'features/rider/bloc/earnings_bloc.dart';
import 'features/rider/bloc/rider_home_bloc.dart';
import 'features/rider/screens/active_delivery_screen.dart';
import 'features/rider/screens/rider_home_screen.dart';
import 'features/rider/services/rider_location_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Never throws and gives up after a few seconds: if the backend is down the
  // app starts on production-safe defaults (GPS only) and retries when needed
  await AppConfig.load(role: 'rider');
  AppConfig.startLiveUpdates(); // admin policy changes reach the app straight away
  runApp(const VendraRiderApp());
}

class VendraRiderApp extends StatefulWidget {
  const VendraRiderApp({super.key});

  @override
  State<VendraRiderApp> createState() => _VendraRiderAppState();
}

class _VendraRiderAppState extends State<VendraRiderApp> {
  /// Lets sign-out send the rider to login from wherever they are
  /// (home shell, active delivery, forced password change…)
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();
  final AuthBloc _authBloc = AuthBloc();

  /// Several requests can 401 at once; only the first one signs out
  bool _sessionExpiring = false;

  /// Location messages (manual location refused → GPS, simulated drive arrived)
  StreamSubscription<LocationNotice>? _locationNotices;

  @override
  void initState() {
    super.initState();
    ApiService.onSessionExpired = _onSessionExpired;
    _locationNotices = RiderLocationService().notices.listen(_showLocationNotice);
  }

  @override
  void dispose() {
    if (ApiService.onSessionExpired == _onSessionExpired) ApiService.onSessionExpired = null;
    _locationNotices?.cancel();
    _authBloc.close();
    super.dispose();
  }

  void _showLocationNotice(LocationNotice notice) {
    NotificationCenter.messengerKey.currentState
      ?..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(notice.text),
        backgroundColor: notice.isError ? AppColors.error : AppColors.success,
        behavior: SnackBarBehavior.floating,
        duration: Duration(seconds: notice.isError ? 6 : 4),
      ));
  }

  /// 401 TOKEN_EXPIRED / INVALID_TOKEN on a signed-in request. Ignored while
  /// not signed in (e.g. splash auto-login already handles a stale token).
  void _onSessionExpired() {
    if (_sessionExpiring || _authBloc.state is! Authenticated) return;
    _sessionExpiring = true;
    _authBloc.add(SessionExpired());
  }

  /// Logout or session expiry → back to the login screen
  void _onSignedOut(BuildContext context, AuthState state) {
    _sessionExpiring = false;
    _navigatorKey.currentState?.pushNamedAndRemoveUntil(AppRoutes.login, (_) => false);
    final message = state is Unauthenticated ? state.message : null;
    if (message != null) {
      NotificationCenter.messengerKey.currentState
        ?..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
          content: Text(message),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 5),
        ));
    }
  }

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider<AuthBloc>.value(value: _authBloc),
      ],
      child: MaterialApp(
        title: 'Vendra Rider',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightTheme,
        navigatorKey: _navigatorKey,
        scaffoldMessengerKey: NotificationCenter.messengerKey,
        // "DEVELOPMENT" badge while the backend runs in development mode
        builder: (context, child) => DevBanner(
          child: BlocListener<AuthBloc, AuthState>(
            // Signed-in → signed-out only (splash's own "no session" result is handled there)
            listenWhen: (prev, curr) => curr is Unauthenticated && (prev is Authenticated || prev is AuthLoading),
            listener: _onSignedOut,
            child: child ?? const SizedBox.shrink(),
          ),
        ),

        initialRoute: AppRoutes.splash,

        routes: {
          AppRoutes.splash: (context) => const SplashScreen(),
          AppRoutes.login: (context) => const LoginScreen(),
          AppRoutes.signup: (context) => const SignupScreen(),
          // Home + earnings blocs live with the signed-in shell and are closed on logout
          AppRoutes.riderHome: (context) => MultiBlocProvider(
                providers: [
                  BlocProvider<RiderHomeBloc>(create: (_) => RiderHomeBloc()..add(RiderHomeStarted())),
                  BlocProvider<EarningsBloc>(create: (_) => EarningsBloc()),
                ],
                child: const RiderHomeScreen(),
              ),
        },

        onGenerateRoute: (settings) {
          if (settings.name == AppRoutes.activeDelivery) {
            final orderId = settings.arguments as int?;
            return MaterialPageRoute<bool>(
              settings: settings,
              builder: (context) => BlocProvider<DeliveryBloc>(
                create: (_) => DeliveryBloc()..add(DeliveryLoadRequested(orderId: orderId)),
                child: const ActiveDeliveryScreen(),
              ),
            );
          }
          return null;
        },
      ),
    );
  }
}
