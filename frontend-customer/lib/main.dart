// ══════════════════════════════════════════════════════════════
// Vendra Customer App - Main Entry Point
// Loads the platform config (mode, features, card gateway) first, then
// initializes BLoC providers, theme, and routes, and signs the user out
// when the server reports the stored session expired/invalid.
// ══════════════════════════════════════════════════════════════

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:vendra_customer/vendra_core.dart';

// Config
import 'config/app_routes.dart';

// Auth
import 'features/auth/bloc/auth_bloc.dart';
import 'features/auth/bloc/auth_event.dart';
import 'features/auth/bloc/auth_state.dart';
import 'features/auth/screens/splash_screen.dart';
import 'features/auth/screens/login_screen.dart';

// Customer
import 'features/customer/bloc/customer_product_bloc.dart';
import 'features/customer/bloc/cart_bloc.dart';
import 'features/customer/bloc/order_bloc.dart';
import 'features/customer/bloc/category_bloc.dart';
import 'features/customer/screens/customer_home_screen.dart';
import 'features/customer/screens/product_detail_screen.dart';
import 'features/customer/screens/carts_screen.dart';
import 'features/customer/screens/order_confirmation_screen.dart';
import 'features/customer/screens/customer_orders_screen.dart';
import 'features/customer/screens/order_tracking_screen.dart';
import 'features/customer/screens/store_screen.dart';
import 'features/customer/screens/wallet_screen.dart';
import 'features/customer/screens/my_disputes_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Never throws and gives up after a few seconds: if the backend is down the
  // app starts on production-safe defaults and retries when a value is needed
  await AppConfig.load(role: 'customer');
  AppConfig.startLiveUpdates(); // admin policy changes reach the app straight away
  runApp(const VendraCustomerApp());
}

class VendraCustomerApp extends StatefulWidget {
  const VendraCustomerApp({super.key});

  @override
  State<VendraCustomerApp> createState() => _VendraCustomerAppState();
}

class _VendraCustomerAppState extends State<VendraCustomerApp> {
  /// Lets the session-expiry handler navigate from outside any screen
  final _navigatorKey = GlobalKey<NavigatorState>();
  final _authBloc = AuthBloc();
  StreamSubscription<AuthState>? _authSub;

  /// Set while a session expiry is being handled, so a burst of 401s from
  /// parallel requests signs out (and navigates) only once. Cleared on the
  /// next sign-in.
  bool _sessionExpiryHandled = false;

  @override
  void initState() {
    super.initState();
    ApiService.onSessionExpired = _onSessionExpired;
    _authSub = _authBloc.stream.listen((state) {
      if (state is Authenticated) _sessionExpiryHandled = false;
    });
  }

  @override
  void dispose() {
    ApiService.onSessionExpired = null;
    _authSub?.cancel();
    _authBloc.close();
    super.dispose();
  }

  /// 401 TOKEN_EXPIRED / INVALID_TOKEN: sign out and go back to the login screen
  Future<void> _onSessionExpired() async {
    if (_sessionExpiryHandled) return;
    _sessionExpiryHandled = true;

    NotificationCenter().stop();
    RealtimeService().disconnect();
    await StorageService.clearAll();
    _authBloc.add(SessionExpired());

    _navigatorKey.currentState?.pushNamedAndRemoveUntil(AppRoutes.login, (_) => false);
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
        BlocProvider<CustomerProductBloc>(create: (_) => CustomerProductBloc()),
        BlocProvider<CartBloc>(create: (_) => CartBloc()),
        BlocProvider<OrderBloc>(create: (_) => OrderBloc()),
        BlocProvider<CategoryBloc>(create: (_) => CategoryBloc()),
      ],
      child: MaterialApp(
        title: 'Vendra',
        navigatorKey: _navigatorKey,
        debugShowCheckedModeBanner: false,
        theme: _customerTheme(),
        // FR09: lets NotificationCenter show a banner for each new notification
        scaffoldMessengerKey: NotificationCenter.messengerKey,
        // Small "DEVELOPMENT" badge while the backend runs in development mode
        builder: (context, child) => DevBanner(child: child ?? const SizedBox.shrink()),

        initialRoute: AppRoutes.splash,

        routes: {
          AppRoutes.splash: (context) => const SplashScreen(),
          AppRoutes.login: (context) => const LoginScreen(),
          AppRoutes.customerHome: (context) => const CustomerHomeScreen(),
          AppRoutes.cart: (context) => const CartsScreen(), // one cart per store
          AppRoutes.customerOrders: (context) => const CustomerOrdersScreen(),
          AppRoutes.wallet: (context) => const WalletScreen(),
          AppRoutes.myDisputes: (context) => const MyDisputesScreen(),
        },

        onGenerateRoute: (settings) {
          if (settings.name == AppRoutes.productDetail) {
            final product = settings.arguments as ProductModel;
            return MaterialPageRoute(builder: (context) => ProductDetailScreen(product: product));
          }

          if (settings.name == AppRoutes.storeDetail) {
            final args = settings.arguments as Map<String, dynamic>;
            return MaterialPageRoute(
              builder: (context) => StoreScreen(
                vendorId: args['vendorId'],
                storeName: args['storeName'] ?? 'Store',
              ),
            );
          }

          if (settings.name == AppRoutes.orderConfirmation) {
            final order = settings.arguments as OrderModel;
            return MaterialPageRoute(builder: (context) => OrderConfirmationScreen(order: order));
          }

          if (settings.name == AppRoutes.orderTracking) {
            final args = settings.arguments;
            final order = args is OrderModel ? args : null;
            final orderId = order?.id ?? (args as int);
            return MaterialPageRoute(
              builder: (context) => OrderTrackingScreen(orderId: orderId, initialOrder: order),
            );
          }

          return null;
        },
      ),
    );
  }
}

/// The shared theme with a few customer-app refinements: neutral (not
/// orange-tinted) surfaces for sheets, drawers, dialogs and dividers, and
/// dark default body text so headings without an explicit colour stay readable.
ThemeData _customerTheme() {
  final base = AppTheme.lightTheme;
  const hairline = Color(0xFFE6E8EB);
  return base.copyWith(
    colorScheme: base.colorScheme.copyWith(
      surfaceTint: Colors.transparent,
      surfaceContainerLowest: Colors.white,
      surfaceContainerLow: Colors.white,
      surfaceContainer: Colors.white,
      surfaceContainerHigh: Colors.white,
      outlineVariant: hairline,
    ),
    dividerColor: hairline,
    dividerTheme: const DividerThemeData(color: hairline, thickness: 1),
    textTheme: base.textTheme.copyWith(
      bodyMedium: base.textTheme.bodyMedium?.copyWith(color: AppColors.textPrimary),
    ),
    appBarTheme: base.appBarTheme.copyWith(surfaceTintColor: Colors.transparent),
    bottomSheetTheme: const BottomSheetThemeData(backgroundColor: Colors.white, surfaceTintColor: Colors.transparent),
    drawerTheme: const DrawerThemeData(backgroundColor: Colors.white, surfaceTintColor: Colors.transparent),
    dialogTheme: const DialogThemeData(backgroundColor: Colors.white, surfaceTintColor: Colors.transparent),
  );
}
