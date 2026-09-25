// Widget tests for the Vendra rider app: an incoming task card, and the
// login screen's "Forgot password?" link.
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vendra_rider/features/auth/bloc/auth_bloc.dart';
import 'package:vendra_rider/features/auth/screens/login_screen.dart';
import 'package:vendra_rider/features/rider/models/rider_models.dart';
import 'package:vendra_rider/features/rider/widgets/task_card.dart';

void main() {
  testWidgets('Task card shows store, distances and payout', (WidgetTester tester) async {
    final task = RiderOrder.fromJson(const {
      'id': 2,
      'status': 'ready_for_pickup',
      'storeName': 'Lahore Fashion Store',
      'storeAddress': 'MM Alam Road',
      'deliveryAddress': '45-C, Model Town, Lahore',
      'itemCount': 3,
      'distanceToStoreKm': 0.67,
      'tripDistanceKm': 4.06,
      'estimatedPayout': 161.45,
    });
    var accepted = false;

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: TaskCard(task: task, onAccept: () => accepted = true, onDecline: () {}),
        ),
      ),
    ));

    expect(find.text('Lahore Fashion Store'), findsOneWidget);
    expect(find.text('Rs. 161.45'), findsOneWidget);
    await tester.tap(find.text('Accept'));
    expect(accepted, isTrue);
  });

  testWidgets('Login screen explains how to reset a forgotten password', (WidgetTester tester) async {
    await tester.pumpWidget(BlocProvider<AuthBloc>(
      create: (_) => AuthBloc(),
      child: const MaterialApp(home: LoginScreen()),
    ));

    await tester.tap(find.text('Forgot password?'));
    await tester.pumpAndSettle();
    expect(find.text('Forgot your password?'), findsOneWidget);
  });
}
