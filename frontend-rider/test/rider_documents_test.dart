// Tests for rider documents: the CNIC format (12345-1234567-1) while
// typing, the validators that mirror the server, and the sign-up fields
// hiding licence and registration for a bicycle.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vendra_rider/features/rider/models/rider_documents_rules.dart';
import 'package:vendra_rider/features/rider/widgets/rider_documents_fields.dart';

TextEditingValue _type(String old, String typed) {
  const f = CnicInputFormatter();
  return f.formatEditUpdate(
    TextEditingValue(text: old, selection: TextSelection.collapsed(offset: old.length)),
    TextEditingValue(text: typed, selection: TextSelection.collapsed(offset: typed.length)),
  );
}

void main() {
  group('CNIC', () {
    test('formats any layout as 12345-1234567-1', () {
      expect(formatCnic('3520212345671'), '35202-1234567-1');
      expect(formatCnic('35202 1234567 1'), '35202-1234567-1');
      expect(formatCnic('352021'), '35202-1');
      expect(formatCnic('35202123456789'), '35202-1234567-8'); // extra digits dropped
    });

    test('validates 13 digits', () {
      expect(validateCnic(''), 'CNIC is required');
      expect(validateCnic('35202-12345'), isNotNull);
      expect(validateCnic('35202-1234567-1'), isNull);
    });

    test('formatter inserts dashes while typing', () {
      expect(_type('35202', '352021').text, '35202-1');
      expect(_type('35202-123456', '35202-1234567').text, '35202-1234567');
      expect(_type('35202-1234567', '35202-12345671').text, '35202-1234567-1');
      expect(_type('', '3520212345671').text, '35202-1234567-1'); // paste
    });

    test('backspace over a dash removes the digit before it', () {
      const f = CnicInputFormatter();
      final r = f.formatEditUpdate(
        const TextEditingValue(text: '35202-1', selection: TextSelection.collapsed(offset: 6)),
        const TextEditingValue(text: '352021', selection: TextSelection.collapsed(offset: 5)),
      );
      expect(r.text, '35201');
      expect(r.selection.baseOffset, 4);
    });
  });

  group('licence and registration', () {
    test('bicycles need neither', () {
      expect(vehicleNeedsLicence('bicycle'), isFalse);
      expect(vehicleNeedsLicence('motorcycle'), isTrue);
      expect(vehicleNeedsLicence('car'), isTrue);
    });

    test('validated like the server', () {
      expect(validateLicenceNumber('LHR-DL-123456'), isNull);
      expect(validateLicenceNumber('ab'), isNotNull);
      expect(validateLicenceNumber('LHR_DL_1234'), isNotNull); // underscores not allowed
      expect(validateVehicleNumber('lea 1234'), isNull);
      expect(validateVehicleNumber(''), 'Registration number is required');
      expect(normalizeDocumentCode('  lea   1234 '), 'LEA 1234');
    });
  });

  testWidgets('fields hide licence and registration for a bicycle', (tester) async {
    var vehicle = 'motorcycle';
    final cnic = TextEditingController();
    final licence = TextEditingController();
    final plate = TextEditingController();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 300, // a narrow phone
          child: StatefulBuilder(
            builder: (context, setState) => SingleChildScrollView(
              child: RiderDocumentsFields(
                cnicController: cnic,
                licenceController: licence,
                vehicleNumberController: plate,
                vehicleType: vehicle,
                onVehicleChanged: (v) => setState(() => vehicle = v),
              ),
            ),
          ),
        ),
      ),
    ));

    expect(find.text('Driving licence number'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('Bicycle'));
    await tester.pump();
    expect(vehicle, 'bicycle');
    expect(find.text('Driving licence number'), findsNothing);
    expect(find.text('Vehicle registration number'), findsNothing);

    await tester.enterText(find.byType(TextFormField).first, '3520212345671');
    expect(cnic.text, '35202-1234567-1');
  });
}
