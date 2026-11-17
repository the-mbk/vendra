// Store pictures on the Profile tab: the owner gets "Change logo" / "Change cover
// photo" (upload → the new pictures + a user refresh), PIN-signed-in staff see the
// header read-only, and a failed upload shows the server's message.
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vendra_vendor/features/vendor/models/product_photo.dart';
import 'package:vendra_vendor/features/vendor/services/store_photo_api.dart';
import 'package:vendra_vendor/features/vendor/widgets/store_photo_header.dart';
import 'package:vendra_vendor/vendra_core.dart';

UserModel _me({String? staffRole, String? logo}) => UserModel.fromJson({
      'id': 2,
      'fullName': 'Usman Ali',
      'email': 'usman@vendor.pk',
      'role': 'vendor',
      'storeName': 'Usman Electronics',
      'storeAddress': 'Shop 4, Hall Road, Lahore',
      'storeLogoUrl': logo,
      'storeCoverUrl': null,
      'staff': staffRole == null ? null : {'id': 5, 'fullName': 'Ali Raza', 'role': staffRole},
      'permissions': staffRole == null ? ['owner'] : ['products.view', 'pos'],
    });

class _FakeApi extends StorePhotoApi {
  final String? error;
  final uploads = <String>[];
  final removed = <StorePhotoKind>[];
  _FakeApi({this.error});

  @override
  Future<StorePictures> upload(StorePhotoKind kind, ProductPhoto photo) async {
    await Future<void>.delayed(const Duration(milliseconds: 10));
    if (error != null) throw StorePhotoException(error!);
    uploads.add('${kind.name}:${photo.name}');
    return kind == StorePhotoKind.logo
        ? const StorePictures(logoUrl: '/uploads/logo.png')
        : const StorePictures(coverUrl: '/uploads/cover.jpg');
  }

  @override
  Future<StorePictures> remove(StorePhotoKind kind) async {
    removed.add(kind);
    return const StorePictures();
  }
}

final _photo = ProductPhoto(name: 'logo.png', bytes: Uint8List.fromList([1, 2, 3]), mimeType: 'image/png');

Widget _host(Widget child) => MaterialApp(home: Scaffold(body: SingleChildScrollView(child: child)));

/// Opens the change sheet's gallery option when there is one (a camera or a photo to remove)
Future<void> _pickFromGallery(WidgetTester tester, String button) async {
  await tester.tap(find.text(button));
  await tester.pumpAndSettle();
  final gallery = find.text('Choose from gallery');
  if (gallery.evaluate().isNotEmpty) {
    await tester.tap(gallery);
    await tester.pump();
  }
}

void main() {
  testWidgets('the owner sees the store header with change buttons', (tester) async {
    await tester.pumpWidget(_host(StorePhotoHeader(user: _me(), api: _FakeApi())));

    expect(find.text('Usman Electronics'), findsOneWidget);
    expect(find.byType(StoreCover), findsOneWidget);
    expect(find.byType(StoreLogo), findsOneWidget);
    expect(find.text('UE'), findsOneWidget); // initials until a logo is uploaded
    expect(find.text('Change logo'), findsOneWidget);
    expect(find.text('Change cover photo'), findsOneWidget);
  });

  testWidgets('staff signed in with a PIN see it read-only', (tester) async {
    await tester.pumpWidget(_host(StorePhotoHeader(user: _me(staffRole: 'cashier'), api: _FakeApi())));

    expect(find.byType(StoreCover), findsOneWidget);
    expect(find.byType(StoreLogo), findsOneWidget);
    expect(find.text('Change logo'), findsNothing);
    expect(find.text('Change cover photo'), findsNothing);
    expect(find.textContaining('Only the store owner'), findsOneWidget);
  });

  testWidgets('uploading a logo shows progress, then the new logo, and refreshes the user', (tester) async {
    final api = _FakeApi();
    var refreshed = 0;
    await tester.pumpWidget(_host(StorePhotoHeader(
      user: _me(),
      api: api,
      onChanged: () => refreshed++,
      pickPhotoOverride: (_) async => _photo,
    )));

    await _pickFromGallery(tester, 'Change logo');
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 20));
    await tester.pump();
    expect(api.uploads, ['logo:logo.png']);
    expect(refreshed, 1);
    expect(find.text('Logo updated'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(tester.widget<StoreLogo>(find.byType(StoreLogo)).logoUrl, '/uploads/logo.png');
  });

  testWidgets('a failed upload shows the error and keeps the old picture', (tester) async {
    var refreshed = 0;
    await tester.pumpWidget(_host(StorePhotoHeader(
      user: _me(),
      api: _FakeApi(error: 'Only JPEG, PNG, WebP or HEIC images are allowed'),
      onChanged: () => refreshed++,
      pickPhotoOverride: (_) async => _photo,
    )));

    await _pickFromGallery(tester, 'Change cover photo');
    await tester.pump(const Duration(milliseconds: 20));
    await tester.pump();

    expect(find.text('Only JPEG, PNG, WebP or HEIC images are allowed'), findsOneWidget);
    expect(refreshed, 0);
    expect(tester.widget<StoreCover>(find.byType(StoreCover)).coverUrl, isNull);
  });

  testWidgets('the owner can remove a logo', (tester) async {
    final api = _FakeApi();
    var refreshed = 0;
    await tester.pumpWidget(_host(StorePhotoHeader(
      user: _me(logo: '/uploads/old.png'),
      api: api,
      onChanged: () => refreshed++,
    )));

    await tester.tap(find.text('Change logo'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove logo'));
    await tester.pumpAndSettle();

    expect(api.removed, [StorePhotoKind.logo]);
    expect(refreshed, 1);
    expect(find.text('Logo removed'), findsOneWidget);
    expect(tester.widget<StoreLogo>(find.byType(StoreLogo)).logoUrl, isNull);
  });

  test('StorePictures reads the API reply', () {
    final p = StorePictures.fromJson({'logoUrl': '/uploads/a.png', 'coverUrl': ''});
    expect(p.logoUrl, '/uploads/a.png');
    expect(p.coverUrl, isNull);
    expect(StorePhotoKind.cover.endpoint, '/api/vendor/store/photos/cover');
    expect(StorePhotoKind.logo.endpoint, '/api/vendor/store/photos/logo');
  });
}
