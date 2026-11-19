// Walk-in POS vs online reservations (FR02) and the dual-inventory matrix (FR01)
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vendra_vendor/features/vendor/bloc/pos_bloc.dart';
import 'package:vendra_vendor/features/vendor/widgets/pos_dialogs.dart';
import 'package:vendra_vendor/vendra_core.dart';

ProductModel _product({int privateStock = 3, int reserved = 2, int buffer = 1}) => ProductModel(
      id: 7,
      vendorId: 1,
      name: 'Olper\'s Milk 1L',
      price: 340,
      privateStock: privateStock,
      buffer: buffer,
      reservedQuantity: reserved,
      publicStock: 0,
    );

void main() {
  group('PosBloc reservation conflicts', () {
    test('ringing up more than the sellable units raises a conflict instead of adding', () async {
      var live = _product(); // sellable = 3 − 2 = 1
      final bloc = PosBloc(productLookup: (_) => live);
      bloc.add(PosAddProduct(live));
      await Future<void>.delayed(Duration.zero);
      expect(bloc.state.quantityOf(7), 1);

      bloc.add(PosAddProduct(live));
      await Future<void>.delayed(Duration.zero);
      expect(bloc.state.quantityOf(7), 1, reason: 'the reserved unit is not added');
      expect(bloc.state.notice?.code, 'RESERVATION_CONFLICT');
      expect(bloc.state.notice?.requested, 2);
      expect(bloc.state.notice?.sellable, 1);

      // Override: the line takes the reserved unit and is flagged for the server
      bloc.add(PosOverrideReservation(live, 2));
      await Future<void>.delayed(Duration.zero);
      expect(bloc.state.quantityOf(7), 2);
      expect(bloc.state.lineFor(7)!.overrideReservation, isTrue);

      // Once overridden, more units don't ask again
      live = _product(privateStock: 4);
      bloc.add(const PosSetQuantity(7, 3));
      await Future<void>.delayed(Duration.zero);
      expect(bloc.state.quantityOf(7), 3);
      await bloc.close();
    });

    test('no reservations means no conflict (the server still checks real stock)', () async {
      final p = _product(reserved: 0, privateStock: 1);
      final bloc = PosBloc(productLookup: (_) => p);
      bloc
        ..add(PosAddProduct(p))
        ..add(PosAddProduct(p));
      await Future<void>.delayed(Duration.zero);
      expect(bloc.state.quantityOf(7), 2);
      expect(bloc.state.notice, isNull);
      await bloc.close();
    });
  });

  test('DualStockMatrix: online = private − buffer − reserved, never below zero', () {
    expect(const DualStockMatrix(privateStock: 20, buffer: 5, reserved: 3).onlineAvailable, 12);
    expect(const DualStockMatrix(privateStock: 4, buffer: 5, reserved: 3).onlineAvailable, 0);
  });

  testWidgets('TenderDialog: quick cash chips and the change to return', (tester) async {
    double? result;
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () async => result = await showDialog<double>(context: context, builder: (_) => const TenderDialog(bill: 340)),
          child: const Text('open'),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('Exact bill'), findsOneWidget);
    await tester.tap(find.text('Rs. 1,000'));
    await tester.pump();
    expect(find.text('Return Rs. 660'), findsOneWidget);

    await tester.enterText(find.byType(TextField), '300');
    await tester.pump();
    expect(find.text('Short by Rs. 40'), findsOneWidget);
    await tester.tap(find.text('Rs. 500'));
    await tester.pump();
    await tester.tap(find.text('Complete sale'));
    await tester.pumpAndSettle();
    expect(result, 500);
  });
}
