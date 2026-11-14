// Customer feature logic: reservation countdown (FR02), handover code,
// escrow wording (FR03), live stock labels (FR01), review payloads and the
// product page details (FR06 / SRDS §2.3).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vendra_customer/features/customer/bloc/product_detail_bloc.dart';
import 'package:vendra_customer/features/customer/widgets/handover_code_card.dart';
import 'package:vendra_customer/features/customer/widgets/order_review.dart';
import 'package:vendra_customer/features/customer/widgets/rating_summary.dart';
import 'package:vendra_customer/features/customer/widgets/reservation_countdown.dart';
import 'package:vendra_customer/features/customer/widgets/trust_badges.dart';
import 'package:vendra_customer/vendra_core.dart';

OrderModel _order(Map<String, dynamic> extra) => OrderModel.fromJson({
      'id': 12,
      'status': 'pending',
      'deliveryType': 'delivery',
      'totalAmount': 1000,
      'items': [
        {'productId': 1, 'productName': 'Tea', 'quantity': 1, 'unitPrice': 500},
        {'productId': 2, 'productName': 'Rusk', 'quantity': 2, 'unitPrice': 250},
      ],
      ...extra,
    });

void main() {
  group('reservation countdown', () {
    test('formats minutes and seconds, hours when needed, never negative', () {
      expect(formatCountdown(const Duration(minutes: 4, seconds: 59)), '04:59');
      expect(formatCountdown(const Duration(seconds: 7)), '00:07');
      expect(formatCountdown(const Duration(hours: 1, minutes: 4, seconds: 9)), '1:04:09');
      expect(formatCountdown(const Duration(seconds: -3)), '00:00');
    });

    test('deadline comes from reservationExpiresAt for pending orders only', () {
      final at = DateTime.utc(2026, 11, 15, 10, 5);
      expect(reservationDeadline(_order({'reservationExpiresAt': at.toIso8601String()})), at.toLocal());
      expect(reservationDeadline(_order({'status': 'confirmed', 'reservationExpiresAt': at.toIso8601String()})), isNull);
    });

    test('falls back to createdAt + the store-accept timeout (checkout response)', () {
      final placed = DateTime.utc(2026, 11, 15, 10, 0);
      final o = _order({'createdAt': placed.toIso8601String()});
      expect(reservationDeadline(o, acceptTimeoutMinutes: 5), placed.toLocal().add(const Duration(minutes: 5)));
      expect(reservationDeadline(o, acceptTimeoutMinutes: 0), isNull);
    });

    testWidgets('counts down and asks for a refresh when time is up', (tester) async {
      var now = DateTime(2026, 11, 15, 10, 0, 0);
      final deadline = now.add(const Duration(seconds: 3));
      var expiredCalls = 0;
      final order = _order({'reservationExpiresAt': deadline.toIso8601String()});

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: ReservationCountdown(order: order, compact: true, clock: () => now, onExpired: () => expiredCalls++),
        ),
      ));
      expect(find.textContaining('00:03'), findsOneWidget);
      expect(find.textContaining('while the store confirms'), findsOneWidget);

      now = now.add(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));
      expect(find.textContaining('00:02'), findsOneWidget);

      now = now.add(const Duration(seconds: 2));
      await tester.pump(const Duration(seconds: 1));
      expect(expiredCalls, 1);
      expect(find.textContaining('Reservation time is up'), findsOneWidget);

      // Still pending a few seconds later: no flood of refreshes
      now = now.add(const Duration(seconds: 5));
      await tester.pump(const Duration(seconds: 5));
      expect(expiredCalls, 1);

      // Removing the widget stops its timer
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('hidden for orders that are not pending', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: ReservationCountdown(order: _order({'status': 'confirmed'}))),
      ));
      expect(find.byType(Text), findsNothing);
    });
  });

  group('handover code', () {
    test('shown for open orders that have a code', () {
      expect(showsHandoverCode(_order({'deliveryOtp': '4821'})), isTrue);
      expect(showsHandoverCode(_order({'deliveryOtp': '4821', 'status': 'delivered'})), isFalse);
      expect(showsHandoverCode(_order({})), isFalse);
    });

    test('instruction depends on delivery type', () {
      expect(handoverInstruction(_order({})), contains('rider only when you have your items'));
      expect(handoverInstruction(_order({'deliveryType': 'self_pickup'})), contains('at the counter'));
    });

    test('locked only while otpLockedUntil is in the future', () {
      final now = DateTime(2026, 11, 15, 12);
      final until = now.add(const Duration(minutes: 10));
      final o = _order({'otpLockedUntil': until.toIso8601String()});
      expect(handoverLocked(o, now), isTrue);
      expect(handoverLocked(o, until.add(const Duration(seconds: 1))), isFalse);
      expect(handoverLocked(_order({}), now), isFalse);
    });

    testWidgets('card shows the digits and the lock warning', (tester) async {
      final o = _order({
        'deliveryOtp': '4821',
        'otpLockedUntil': DateTime.now().add(const Duration(minutes: 10)).toIso8601String(),
      });
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: SingleChildScrollView(child: HandoverCodeCard(order: o))),
      ));
      for (final d in ['4', '8', '2', '1']) {
        expect(find.text(d), findsOneWidget);
      }
      expect(find.textContaining('Handover is locked until'), findsOneWidget);
    });
  });

  group('escrow and stock wording', () {
    test('headline follows the escrow status', () {
      expect(escrowTrustHeadline(_order({'escrowStatus': 'held'})), 'Funds held safely by Vendra Escrow until delivery');
      expect(escrowTrustHeadline(_order({'escrowStatus': 'held', 'status': 'delivered'})), contains('dispute window'));
      expect(escrowTrustHeadline(_order({'escrowStatus': 'disputed'})), contains('frozen'));
      expect(escrowTrustHeadline(_order({'escrowStatus': 'released'})), contains('released'));
      expect(escrowTrustHeadline(_order({'escrowStatus': 'refunded'})), contains('refunded'));
    });

    test('dispute window wording', () {
      expect(formatWindow(30), '30-minute');
      expect(formatWindow(120), '2-hour');
      expect(formatWindow(1440), '1-day');
      expect(formatWindow(90), '90-minute');
    });

    test('low-stock signal is kept', () {
      ProductModel p(int stock) => ProductModel(id: 1, vendorId: 1, name: 'x', price: 1, publicStock: stock);
      expect(stockLabel(p(0)), 'Sold out');
      expect(stockLabel(p(3)), 'Only 3 left');
      expect(stockLabel(p(40)), '40 in stock');
    });
  });

  group('review payload', () {
    final delivered = _order({
      'status': 'delivered',
      'canReview': true,
      'rider': {'id': 9, 'name': 'Bilal'},
    });

    test('skips unrated products, trims and caps comments, includes the rider rating', () {
      final body = buildReviewPayload(
        order: delivered,
        ratings: {1: 5, 2: 0},
        comments: {1: '  Fresh and well packed  ', 2: 'ignored'},
        riderRating: 4,
      );
      expect(body['items'], [
        {'productId': 1, 'rating': 5, 'comment': 'Fresh and well packed'},
      ]);
      expect(body['riderRating'], 4);

      final long = buildReviewPayload(order: delivered, ratings: {2: 3}, comments: {2: 'a' * 600});
      expect((long['items'] as List).single['comment'], hasLength(maxReviewComment));
      expect(long.containsKey('riderRating'), isFalse);
    });

    test('no rider rating for self pickup or empty comments', () {
      final pickup = _order({'status': 'delivered', 'deliveryType': 'self_pickup'});
      final body = buildReviewPayload(order: pickup, ratings: {1: 4}, comments: {1: '   '}, riderRating: 5);
      expect(body, {
        'items': [
          {'productId': 1, 'rating': 4},
        ],
      });
    });

    test('order items carry the stars already given', () {
      final o = _order({
        'status': 'delivered',
        'reviewedAt': '2026-11-14T10:00:00Z',
        'riderRating': 5,
        'items': [
          {'productId': 1, 'productName': 'Tea', 'quantity': 1, 'unitPrice': 500, 'myRating': 4, 'myComment': 'Good'},
        ],
      });
      expect(o.canReview, isFalse);
      expect(o.items.single.myRating, 4);
      expect(o.riderRating, 5);
    });
  });

  group('product page details', () {
    final json = {
      'id': 3,
      'vendorId': 1,
      'name': 'Basmati Rice 5kg',
      'price': 2400,
      'publicStock': 0,
      'imageUrl': '/uploads/products/cover.jpg',
      'averageRating': 4.3,
      'ratingCount': 7,
      'images': ['/uploads/products/cover.jpg', '/uploads/products/2.jpg', '/uploads/products/2.jpg'],
      'ratingDistribution': {'5': 4, '4': 1, '3': 1, '2': 0, '1': 1},
      'latestReviews': [
        {
          'id': 10,
          'orderId': 4,
          'productId': 3,
          'rating': 5,
          'comment': 'Great',
          'customerName': 'Ahmed R.',
          'createdAt': '2026-11-10T09:00:00Z',
        },
      ],
    };

    test('parses images (cover first, no duplicates), the breakdown and reviews', () {
      final d = ProductDetails.fromJson(json);
      expect(d.images, ['/uploads/products/cover.jpg', '/uploads/products/2.jpg']);
      expect(d.distribution, {5: 4, 4: 1, 3: 1, 2: 0, 1: 1});
      expect(d.totalRatings, 7);
      expect(d.latestReviews.single.customerName, 'Ahmed R.');
      expect(d.product.isOutOfStock, isTrue);
      expect(d.product.averageRating, 4.3);
    });

    test('no reviews: empty breakdown and zero-safe fractions', () {
      final d = ProductDetails.fromJson({'id': 1, 'vendorId': 1, 'name': 'x', 'price': 1, 'publicStock': 2});
      expect(d.distribution.values.every((n) => n == 0), isTrue);
      expect(d.latestReviews, isEmpty);
      expect(ratingFraction(d.distribution, 5), 0);
      expect(d.images, isEmpty);
    });

    test('breakdown fractions', () {
      expect(ratingFraction({5: 3, 4: 1, 3: 0, 2: 0, 1: 0}, 5), 0.75);
      expect(ratingFraction({5: 3, 4: 1, 3: 0, 2: 0, 1: 0}, 1), 0);
    });
  });

  // Any RenderFlex overflow on a 320 px wide phone fails these
  testWidgets('new widgets fit a narrow phone', (tester) async {
    tester.view.physicalSize = const Size(320, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final product = ProductModel(id: 1, vendorId: 1, name: 'Basmati Rice', price: 2400, publicStock: 3);
    final open = _order({
      'deliveryOtp': '4821',
      'reservationExpiresAt': DateTime.now().add(const Duration(minutes: 4)).toIso8601String(),
      'otpLockedUntil': DateTime.now().add(const Duration(minutes: 10)).toIso8601String(),
    });
    final reviewed = _order({
      'status': 'delivered',
      'reviewedAt': '2026-11-14T10:00:00Z',
      'riderRating': 5,
      'rider': {'id': 9, 'name': 'Bilal Hussain with a long name'},
      'items': [
        {'productId': 1, 'productName': 'A very long product name that keeps going', 'quantity': 1, 'unitPrice': 500, 'myRating': 4, 'myComment': 'Good'},
      ],
    });

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            LiveStockIndicator(product: product),
            LiveStockIndicator(product: product, compact: true),
            const LiveStockNote(),
            const EscrowTrustBadge(),
            const EscrowTrustBadge(compact: true),
            ReservationCountdown(order: open),
            ReservationCountdown(order: open, compact: true),
            HandoverCodeCard(order: open),
            HandoverCodeCard(order: open, compact: true),
            const RatingSummary(average: 4.3, count: 1234, distribution: {5: 900, 4: 200, 3: 100, 2: 20, 1: 14}),
            const RatingSummary(average: null, count: 0, distribution: {}),
            OrderReviewSection(order: reviewed, onReviewed: () {}),
            OrderReviewSection(order: _order({'status': 'delivered', 'canReview': true}), onReviewed: () {}),
          ],
        ),
      ),
    ));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
