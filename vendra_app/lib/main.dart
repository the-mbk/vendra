// ══════════════════════════════════════════════════════════════
// Vendra App - Main Entry Point
// Initializes BLoC providers, theme, and routes
// ══════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

// Config
import 'config/app_theme.dart';
import 'config/app_routes.dart';

// Models
import 'core/models/product_model.dart';
import 'core/models/order_model.dart';
import 'core/models/user_model.dart';

// Auth
import 'features/auth/bloc/auth_bloc.dart';
import 'features/auth/screens/splash_screen.dart';
import 'features/auth/screens/login_screen.dart';

// Customer
import 'features/customer/bloc/customer_product_bloc.dart';
import 'features/customer/bloc/cart_bloc.dart';
import 'features/customer/bloc/order_bloc.dart';
import 'features/customer/screens/customer_home_screen.dart';
import 'features/customer/screens/product_detail_screen.dart';
import 'features/customer/screens/cart_screen.dart';
import 'features/customer/screens/order_confirmation_screen.dart';
import 'features/customer/screens/customer_orders_screen.dart';
import 'features/customer/screens/order_tracking_screen.dart';
import 'features/customer/screens/store_screen.dart';

// Vendor
import 'features/vendor/bloc/vendor_product_bloc.dart';
import 'features/vendor/bloc/vendor_order_bloc.dart';
import 'features/vendor/screens/vendor_dashboard_screen.dart';
import 'features/vendor/screens/add_edit_product_screen.dart';
import 'features/vendor/screens/pending_approval_screen.dart';

// Placeholder
import 'features/placeholder/under_development_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const VendraApp());
}

class VendraApp extends StatelessWidget {
  const VendraApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider<AuthBloc>(create: (_) => AuthBloc()),
        BlocProvider<CustomerProductBloc>(create: (_) => CustomerProductBloc()),
        BlocProvider<CartBloc>(create: (_) => CartBloc()),
        BlocProvider<OrderBloc>(create: (_) => OrderBloc()),
        BlocProvider<VendorProductBloc>(create: (_) => VendorProductBloc()),
        BlocProvider<VendorOrderBloc>(create: (_) => VendorOrderBloc()),
      ],
      child: MaterialApp(
        title: 'Vendra',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightTheme,

        // Initial route
        initialRoute: AppRoutes.splash,

        // Named routes
        routes: {
          AppRoutes.splash: (context) => const SplashScreen(),
          AppRoutes.login: (context) => const LoginScreen(),
          AppRoutes.customerHome: (context) => const CustomerHomeScreen(),
          AppRoutes.cart: (context) => const CartScreen(),
          AppRoutes.customerOrders: (context) => const CustomerOrdersScreen(),
          AppRoutes.vendorDashboard: (context) => const VendorDashboardScreen(),
          AppRoutes.addProduct: (context) => const AddEditProductScreen(),
          AppRoutes.riderPlaceholder: (context) => const UnderDevelopmentScreen(title: 'Rider Dashboard'),
          AppRoutes.adminPlaceholder: (context) => const UnderDevelopmentScreen(title: 'Admin Panel'),
          AppRoutes.underDevelopment: (context) => const UnderDevelopmentScreen(),
        },

        // Dynamic routes (require arguments)
        onGenerateRoute: (settings) {
          // Product Detail Screen
          if (settings.name == AppRoutes.productDetail) {
            final product = settings.arguments as ProductModel;
            return MaterialPageRoute(
              builder: (context) => ProductDetailScreen(product: product),
            );
          }

          // Store Screen (vendor shop page)
          if (settings.name == AppRoutes.storeDetail) {
            final args = settings.arguments as Map<String, dynamic>;
            return MaterialPageRoute(
              builder: (context) => StoreScreen(
                vendorId: args['vendorId'],
                storeName: args['storeName'] ?? 'Store',
              ),
            );
          }

          // Order Confirmation Screen
          if (settings.name == AppRoutes.orderConfirmation) {
            final order = settings.arguments as OrderModel;
            return MaterialPageRoute(
              builder: (context) => OrderConfirmationScreen(order: order),
            );
          }

          // Order Tracking Screen
          if (settings.name == AppRoutes.orderTracking) {
            final order = settings.arguments as OrderModel;
            return MaterialPageRoute(
              builder: (context) => OrderTrackingScreen(order: order),
            );
          }

          // Edit Product Screen
          if (settings.name == AppRoutes.editProduct) {
            final product = settings.arguments as ProductModel;
            return MaterialPageRoute(
              builder: (context) => AddEditProductScreen(product: product),
            );
          }

          // Vendor Pending Approval Screen
          if (settings.name == AppRoutes.vendorPendingApproval) {
            final user = settings.arguments as UserModel;
            return MaterialPageRoute(
              builder: (context) => PendingApprovalScreen(user: user),
            );
          }

          return null;
        },
      ),
    );
  }
}
