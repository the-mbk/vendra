// The product page, the store page and how they connect: a home pick opens
// the product page; "Visit store" opens the store (or goes back to it);
// "Write a review" only for a customer with a delivered order to review;
// the store's cover/logo (with fallbacks) and its reviews.
// The catalog API is replaced with a stand-in (CatalogApi.instance).
// Shapes copied from the backend (customer.controller.js).
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vendra_customer/features/customer/bloc/cart_bloc.dart';
import 'package:vendra_customer/features/customer/screens/product_detail_screen.dart';
import 'package:vendra_customer/features/customer/screens/store_reviews_screen.dart';
import 'package:vendra_customer/features/customer/screens/store_screen.dart';
import 'package:vendra_customer/features/customer/services/catalog_api.dart';
import 'package:vendra_customer/features/customer/widgets/home_product_tile.dart';
import 'package:vendra_customer/features/customer/widgets/store_widgets.dart';
import 'package:vendra_customer/vendra_core.dart';

const _storeName = 'Karachi Electronics Hub';

Map<String, dynamic> _productJson({int id = 7, String name = 'Desk Lamp'}) => {
      'id': id,
      'vendorId': 3,
      'storeName': _storeName,
      'storeAddress': 'Saddar, Karachi',
      'storeLogoUrl': null,
      'name': name,
      'description': 'A warm LED lamp',
      'price': 2500,
      'publicStock': 12,
      'imageUrl': null,
      'images': <String>[],
      'averageRating': null,
      'ratingCount': 0,
      'ratingDistribution': {'5': 0, '4': 0, '3': 0, '2': 0, '1': 0},
      'latestReviews': <Map<String, dynamic>>[],
    };

Map<String, dynamic> _review(int id, {String product = 'Desk Lamp', int productId = 7, int rating = 5}) => {
      'id': id,
      'orderId': 40 + id,
      'productId': productId,
      'productName': product,
      'rating': rating,
      'comment': 'Review number $id',
      'customerName': 'Ahmed R.',
      'createdAt': '2026-11-10T10:00:00Z',
    };

Map<String, dynamic> _storeJson({String? logoUrl, String? coverUrl, bool withReviews = true}) => {
      'id': 3,
      'storeName': _storeName,
      'storeAddress': 'Saddar, Karachi',
      'ownerName': 'Owner',
      'ownerPhone': '03001234567',
      'latitude': null,
      'longitude': null,
      'logoUrl': logoUrl,
      'coverUrl': coverUrl,
      'averageRating': withReviews ? 4.5 : null,
      'ratingCount': withReviews ? 2 : 0,
      'ratingDistribution': withReviews ? {'5': 1, '4': 1, '3': 0, '2': 0, '1': 0} : {},
      'latestReviews': withReviews ? [_review(1), _review(2, product: 'USB Cable', productId: 8, rating: 4)] : [],
      'products': [_productJson()],
    };

class _FakeCatalog extends CatalogApi {
  int? reviewOrder;
  Map<String, dynamic> storeJson;
  final List<int> ordersOpened = [];
  int productLoads = 0;
  int storeLoads = 0;

  _FakeCatalog() : storeJson = _storeJson();

  @override
  Future<Map<String, dynamic>> product(int id) async {
    productLoads++;
    return _productJson(id: id);
  }

  @override
  Future<int?> reviewOrderId(int productId) async => reviewOrder;

  @override
  Future<OrderModel> order(int id) async {
    ordersOpened.add(id);
    return OrderModel.fromJson({
      'id': id,
      'status': 'delivered',
      'deliveryType': 'pickup',
      'canReview': true,
      'storeName': _storeName,
      'totalAmount': 2500,
      'items': [
        {'productId': 7, 'productName': 'Desk Lamp', 'quantity': 1, 'unitPrice': 2500},
      ],
    });
  }

  @override
  Future<Map<String, dynamic>> store(int vendorId) async {
    storeLoads++;
    return storeJson;
  }

  @override
  Future<(List<ReviewModel>, PageMeta)> storeReviews(int vendorId, {int limit = 20, int offset = 0}) async {
    final reviews = [for (var i = 1; i <= 3; i++) ReviewModel.fromJson(_review(i, product: 'Product $i'))];
    return (reviews, const PageMeta());
  }
}

final _product = ProductModel.fromJson(_productJson());

/// A 360 px wide phone, so overflows show up as errors
void _phone(WidgetTester tester) {
  tester.view.physicalSize = const Size(360 * 3, 780 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
}

Future<void> _pump(WidgetTester tester, Widget home) async {
  await tester.pumpWidget(BlocProvider(
    create: (_) => CartBloc(),
    child: MaterialApp(home: home),
  ));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

/// Lets a page transition finish (pumpAndSettle would wait forever on the live-stock dot)
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// Scrolls the page until [finder] is on screen
Future<void> _reveal(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pump();
}

/// The page's vertical scroll view (the product photos scroll sideways)
final _pageScroll = find.byWidgetPredicate((w) => w is Scrollable && w.axisDirection == AxisDirection.down).first;

void main() {
  late _FakeCatalog catalog;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    catalog = _FakeCatalog();
    CatalogApi.instance = catalog;
  });

  tearDown(() => CatalogApi.instance = const CatalogApi());

  testWidgets("a home pick opens the product's page, showing the store logo", (tester) async {
    _phone(tester);
    await _pump(tester, Scaffold(body: ListView(children: [HomeProductTile(product: _product, distance: '1.2 km')])));

    // Store logo (initials without a logo) next to the store name
    expect(find.text('KE'), findsOneWidget);
    expect(find.text(_storeName), findsOneWidget);

    await tester.tap(find.text('Desk Lamp'));
    await _settle(tester);

    expect(find.byType(ProductDetailScreen), findsOneWidget);
    expect(find.byType(StoreScreen), findsNothing);
    expect(find.text('Product Details'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the product page shows its store and "Visit store" opens the store page', (tester) async {
    _phone(tester);
    await _pump(tester, ProductDetailScreen(product: _product));

    expect(find.text('Sold by'), findsOneWidget);
    expect(find.text('Visit store'), findsOneWidget);
    expect(find.textContaining('Saddar, Karachi'), findsOneWidget);
    // No dead share / favourite buttons
    expect(find.byIcon(Icons.share_outlined), findsNothing);
    expect(find.byIcon(Icons.favorite_border), findsNothing);

    await _reveal(tester, find.text('Visit store'));
    await tester.tap(find.text('Visit store'));
    await _settle(tester);

    expect(find.byType(StoreScreen), findsOneWidget);
    expect(catalog.storeLoads, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('"Visit store" goes back when the page was opened from that store', (tester) async {
    _phone(tester);
    await _pump(
      tester,
      Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => ProductDetailScreen(product: _product, openedFromStore: true)),
              ),
              child: const Text('the store page'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('the store page'));
    await _settle(tester);
    expect(find.byType(ProductDetailScreen), findsOneWidget);

    await _reveal(tester, find.text('Visit store'));
    await tester.tap(find.text('Visit store'));
    await _settle(tester);

    expect(find.byType(ProductDetailScreen), findsNothing);
    expect(find.byType(StoreScreen), findsNothing);
    expect(find.text('the store page'), findsOneWidget);
  });

  testWidgets('"Write a review" is hidden without an order to review', (tester) async {
    _phone(tester);
    await _pump(tester, ProductDetailScreen(product: _product));

    await _reveal(tester, find.text('Ratings & reviews'));
    expect(find.text('Write a review'), findsNothing);
    expect(find.textContaining('Customers who buy this can rate it'), findsOneWidget);
  });

  testWidgets('"Write a review" opens the review sheet for the delivered order', (tester) async {
    _phone(tester);
    catalog.reviewOrder = 55;
    await _pump(tester, ProductDetailScreen(product: _product));

    await _reveal(tester, find.text('Write a review'));
    expect(find.textContaining('yours can be the first'), findsOneWidget);

    await tester.tap(find.text('Write a review'));
    await _settle(tester);

    expect(catalog.ordersOpened, [55]);
    expect(find.text('Rate your order'), findsOneWidget);
    expect(find.text('Desk Lamp'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the store page shows the cover and logo fallbacks and the store reviews', (tester) async {
    _phone(tester);
    await _pump(tester, const StoreScreen(vendorId: 3, storeName: _storeName));

    // No cover / logo uploaded: brand gradient and initials
    final cover = tester.widget<StoreCover>(find.byType(StoreCover));
    expect(cover.coverUrl, isNull);
    expect(cover.shade, isTrue);
    final logo = tester.widget<StoreLogo>(find.byType(StoreLogo).first);
    expect(logo.logoUrl, isNull);
    expect(logo.ring, isTrue);
    expect(find.text('KE'), findsOneWidget);

    await tester.scrollUntilVisible(find.text('See all reviews (2) ›'), 300, scrollable: _pageScroll);
    expect(find.text('Store reviews'), findsOneWidget);
    // Each review says which product it's about
    expect(find.text('Review number 1'), findsOneWidget);
    expect(find.text('USB Cable'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await _reveal(tester, find.text('See all reviews (2) ›'));
    await tester.tap(find.text('See all reviews (2) ›'));
    await _settle(tester);

    expect(find.byType(StoreReviewsScreen), findsOneWidget);
    expect(find.text('Product 3'), findsOneWidget);
    expect(find.text('Review number 3'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the store page passes uploaded cover and logo through', (tester) async {
    _phone(tester);
    catalog.storeJson = _storeJson(logoUrl: '/uploads/logo.png', coverUrl: '/uploads/cover.jpg', withReviews: false);
    await _pump(tester, const StoreScreen(vendorId: 3, storeName: _storeName));

    expect(tester.widget<StoreCover>(find.byType(StoreCover)).coverUrl, '/uploads/cover.jpg');
    expect(tester.widget<StoreLogo>(find.byType(StoreLogo).first).logoUrl, '/uploads/logo.png');

    await tester.scrollUntilVisible(find.text('Store reviews'), 300, scrollable: _pageScroll);
    expect(find.textContaining('No reviews yet'), findsWidgets);
    expect(find.textContaining('See all reviews'), findsNothing);
  });

  testWidgets('store search cards show the cover banner and logo without overflowing', (tester) async {
    _phone(tester);
    var opened = 0;
    await _pump(
      tester,
      Scaffold(
        body: SizedBox(
          height: StoreBannerCard.height,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              StoreBannerCard(
                storeName: 'A store with a very long name that keeps on going',
                subtitle: '2.9 km · 30 products · pickup only',
                warn: true,
                onTap: () => opened++,
              ),
              StoreBannerCard(storeName: _storeName, coverUrl: '/uploads/c.jpg', logoUrl: '/uploads/l.png', onTap: () {}),
            ],
          ),
        ),
      ),
    );
    expect(find.byType(StoreCover), findsNWidgets(2));
    expect(find.text('AS'), findsOneWidget); // initials fallback
    await tester.tap(find.text('AS'));
    expect(opened, 1);
    expect(tester.takeException(), isNull);
  });

  test('distance labels', () {
    expect(distanceLabel(0.85), '850 m');
    expect(distanceLabel(2.44), '2.4 km');
    expect(haversineKm(33.6844, 73.0479, 33.6844, 73.0479), 0);
  });
}
