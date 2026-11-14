// Shop staff: which tabs each role gets, the signed-in label, the PIN pad's
// 4–6 digit buffer and the staff row parsing.
import 'package:flutter_test/flutter_test.dart';
import 'package:vendra_vendor/features/staff/models/pin_buffer.dart';
import 'package:vendra_vendor/features/staff/models/staff_member.dart';
import 'package:vendra_vendor/features/staff/permissions.dart';
import 'package:vendra_vendor/vendra_core.dart';

/// /api/auth/me for the owner (staff null) or a staff member with the server's permissions
UserModel _me({String? role}) => UserModel.fromJson({
      'id': 2,
      'fullName': 'Usman Ali',
      'email': 'usman@vendor.pk',
      'role': 'vendor',
      'storeName': 'Usman Electronics',
      'staff': role == null ? null : {'id': 5, 'fullName': 'Ali Raza', 'role': role},
      'permissions': switch (role) {
        'cashier' => ['products.view', 'pos'],
        'packer' => ['products.view', 'orders.view', 'orders.fulfil'],
        'inventory_manager' => ['products.view', 'products.manage', 'ledger', 'orders.view'],
        _ => ['products.view', 'products.manage', 'pos', 'orders.view', 'orders.fulfil', 'ledger', 'owner'],
      },
    });

void main() {
  group('visibleTabs', () {
    test('the owner gets every tab', () {
      expect(visibleTabs(_me()), VendorTab.values);
    });

    test('a cashier gets POS but no orders or ledger', () {
      expect(visibleTabs(_me(role: 'cashier')), [VendorTab.home, VendorTab.pos, VendorTab.profile]);
    });

    test('a packer gets orders only', () {
      expect(visibleTabs(_me(role: 'packer')), [VendorTab.home, VendorTab.orders, VendorTab.profile]);
    });

    test('an inventory manager gets orders (view) and the ledger', () {
      expect(visibleTabs(_me(role: 'inventory_manager')),
          [VendorTab.home, VendorTab.orders, VendorTab.ledger, VendorTab.profile]);
    });
  });

  test('owner-only and fulfil permissions follow the role', () {
    expect(_me().can(Perm.owner), isTrue);
    expect(_me(role: 'cashier').can(Perm.owner), isFalse);
    expect(_me(role: 'packer').can(Perm.ordersFulfil), isTrue);
    expect(_me(role: 'inventory_manager').can(Perm.ordersFulfil), isFalse);
    expect(_me(role: 'inventory_manager').can(Perm.productsManage), isTrue);
    expect(_me(role: 'cashier').can(Perm.productsManage), isFalse);
  });

  test('signedInLabel names the person and role', () {
    expect(signedInLabel(_me()), 'Usman Ali · Owner');
    expect(signedInLabel(_me(role: 'cashier')), 'Ali Raza · Cashier');
    expect(signedInLabel(_me(role: 'inventory_manager')), 'Ali Raza · Inventory Manager');
  });

  group('PinBuffer', () {
    test('OK opens at 4 digits and the buffer stops at 6', () {
      final pin = PinBuffer();
      for (final d in ['1', '2', '3']) {
        pin.add(d);
      }
      expect(pin.canSubmit, isFalse);
      pin.add('4');
      expect(pin.canSubmit, isTrue);
      expect(pin.add('5'), isTrue);
      expect(pin.add('6'), isTrue);
      expect(pin.isFull, isTrue);
      expect(pin.add('7'), isFalse);
      expect(pin.value, '123456');
    });

    test('ignores non-digits; backspace and clear', () {
      final pin = PinBuffer();
      expect(pin.add('a'), isFalse);
      expect(pin.add('12'), isFalse);
      pin
        ..add('9')
        ..add('8')
        ..backspace();
      expect(pin.value, '9');
      pin.clear();
      expect(pin.isEmpty, isTrue);
      pin.backspace(); // no-op when empty
      expect(pin.value, '');
    });
  });

  test('validatePin accepts 4–6 digits only', () {
    expect(validatePin('1111'), isNull);
    expect(validatePin('123456'), isNull);
    expect(validatePin('123'), isNotNull);
    expect(validatePin('1234567'), isNotNull);
    expect(validatePin('12a4'), isNotNull);
    expect(validatePin(''), isNotNull);
    expect(validatePin('', required: false), isNull);
  });

  test('StaffMember parses a staff row and knows a lockout', () {
    final locked = StaffMember.fromJson({
      'id': 3,
      'fullName': 'Kashif Mehmood',
      'role': 'inventory_manager',
      'isActive': true,
      'lastLoginAt': null,
      'lockedUntil': DateTime.now().add(const Duration(minutes: 4)).toUtc().toIso8601String(),
    });
    expect(locked.roleInfo.label, 'Inventory Manager');
    expect(locked.isLocked, isTrue);

    final removed = StaffMember.fromJson({'id': '4', 'fullName': 'Sana Iqbal', 'role': 'packer', 'isActive': false});
    expect(removed.id, 4);
    expect(removed.isActive, isFalse);
    expect(removed.isLocked, isFalse);
    expect(staffRoleOf('mystery').label, 'mystery');
  });
}
