// Tests for the admin approval gate: the rider profile's approval fields,
// which states may go online, and the Home card for pending / rejected
// documents.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vendra_rider/features/rider/bloc/rider_home_bloc.dart';
import 'package:vendra_rider/features/rider/models/rider_models.dart';
import 'package:vendra_rider/features/rider/widgets/approval_status_card.dart';

void main() {
  test('profile carries the approval status and documents', () {
    final p = RiderProfile.fromJson(const {
      'isOnline': false,
      'vehicleType': 'motorcycle',
      'cnic': '35202-1234567-1',
      'licenseNumber': 'LHR-DL-123456',
      'vehicleNumber': 'LEA-1234',
      'approvalStatus': 'rejected',
      'rejectionReason': 'Licence photo is blurry',
    });
    expect(p.approvalStatus, 'rejected');
    expect(p.rejectionReason, 'Licence photo is blurry');
    expect(p.documents.cnic, '35202-1234567-1');
    expect(p.documents.vehicleNumber, 'LEA-1234');
  });

  test('only an approved rider may go online', () {
    expect(const RiderHomeState(approvalStatus: 'approved').isApproved, isTrue);
    expect(const RiderHomeState(approvalStatus: 'pending').isApproved, isFalse);
    expect(const RiderHomeState(approvalStatus: 'pending').isPendingApproval, isTrue);
    expect(const RiderHomeState(approvalStatus: 'rejected').isRejected, isTrue);
  });

  testWidgets('pending shows "Documents under review"', (tester) async {
    var checked = false;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: ApprovalStatusCard(status: 'pending', onCheckStatus: () => checked = true)),
    ));
    expect(find.text('Documents under review'), findsOneWidget);
    expect(find.text('Update documents'), findsNothing);
    await tester.tap(find.text('Check status'));
    expect(checked, isTrue);
  });

  testWidgets('rejected shows the reason and "Update documents"', (tester) async {
    var opened = false;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: ApprovalStatusCard(
            status: 'rejected',
            rejectionReason: 'Licence photo is blurry',
            onUpdateDocuments: () => opened = true,
          ),
        ),
      ),
    ));
    expect(find.text('Documents not approved'), findsOneWidget);
    expect(find.text('Licence photo is blurry'), findsOneWidget);
    await tester.tap(find.text('Update documents'));
    expect(opened, isTrue);
  });
}
