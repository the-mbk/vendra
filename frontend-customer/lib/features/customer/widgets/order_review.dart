// ══════════════════════════════════════════════════════════════
// Vendra Customer App - Reviews & ratings (SRDS §2.3)
// Delivered orders with canReview get a "Rate your order" action. The
// sheet takes 1–5 stars (+ optional comment, ≤500 chars) per product and,
// for a delivery with a rider, a rider rating, then posts
// POST /api/customer/orders/:id/review once. Reviewed orders show the
// stars the customer gave (myRating / riderRating).
// ══════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:vendra_customer/vendra_core.dart';

const maxReviewComment = 500;

/// Rider ratings only apply to delivery orders a rider handled
bool canRateRider(OrderModel o) => o.isDelivery && o.rider != null;

/// One row per product (an order shouldn't repeat a product, but be safe)
List<OrderItemModel> reviewableItems(OrderModel o) {
  final seen = <int>{};
  return o.items.where((i) => seen.add(i.productId)).toList();
}

/// The review request body. Products left at 0 stars are skipped; comments are
/// trimmed (empty ones dropped) and capped at [maxReviewComment] characters.
Map<String, dynamic> buildReviewPayload({
  required OrderModel order,
  required Map<int, int> ratings,
  Map<int, String> comments = const {},
  int? riderRating,
}) {
  final items = <Map<String, dynamic>>[];
  for (final item in reviewableItems(order)) {
    final rating = ratings[item.productId] ?? 0;
    if (rating < 1 || rating > 5) continue;
    var comment = (comments[item.productId] ?? '').trim();
    if (comment.length > maxReviewComment) comment = comment.substring(0, maxReviewComment);
    items.add({
      'productId': item.productId,
      'rating': rating,
      if (comment.isNotEmpty) 'comment': comment,
    });
  }
  return {
    'items': items,
    if (canRateRider(order) && riderRating != null && riderRating >= 1 && riderRating <= 5) 'riderRating': riderRating,
  };
}

/// Opens the review sheet. Resolves to true when the order should be
/// refreshed (review saved, or the server says it was already reviewed).
Future<bool> showOrderReviewSheet(BuildContext context, OrderModel order) async {
  final result = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (_) => _OrderReviewSheet(order: order),
  );
  return result == true;
}

class _OrderReviewSheet extends StatefulWidget {
  final OrderModel order;
  const _OrderReviewSheet({required this.order});

  @override
  State<_OrderReviewSheet> createState() => _OrderReviewSheetState();
}

class _OrderReviewSheetState extends State<_OrderReviewSheet> {
  final Map<int, int> _ratings = {};
  final Map<int, TextEditingController> _comments = {};
  int _riderRating = 0;
  bool _submitting = false;
  String? _error;

  late final List<OrderItemModel> _items = reviewableItems(widget.order);

  @override
  void initState() {
    super.initState();
    for (final item in _items) {
      _comments[item.productId] = TextEditingController();
    }
  }

  @override
  void dispose() {
    for (final c in _comments.values) {
      c.dispose();
    }
    super.dispose();
  }

  bool get _canSubmit => !_submitting && _ratings.values.any((r) => r > 0);

  Future<void> _submit() async {
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    setState(() {
      _submitting = true;
      _error = null;
    });
    final body = buildReviewPayload(
      order: widget.order,
      ratings: _ratings,
      comments: _comments.map((id, c) => MapEntry(id, c.text)),
      riderRating: _riderRating > 0 ? _riderRating : null,
    );
    try {
      final res = await ApiService().post(ApiConfig.reviewOrder(widget.order.id), data: body);
      if (res.data is Map && res.data['success'] == false) {
        throw Exception(res.data['message'] ?? 'Could not save your review');
      }
      navigator.pop(true);
      messenger.showSnackBar(const SnackBar(
        content: Text('Thanks for your review!'),
        backgroundColor: AppColors.stockGreen,
        behavior: SnackBarBehavior.floating,
      ));
    } catch (e) {
      final code = ApiService.getErrorCode(e);
      if (code == 'ALREADY_REVIEWED' || code == 'NOT_DELIVERED') {
        // Nothing to fix in the form: close and let the caller refresh the order
        navigator.pop(true);
        messenger.showSnackBar(SnackBar(
          content: Text(code == 'ALREADY_REVIEWED'
              ? 'You have already reviewed this order.'
              : 'You can rate this order once it has been delivered.'),
          behavior: SnackBarBehavior.floating,
        ));
        return;
      }
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = ApiService.getErrorMessage(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final order = widget.order;
    final media = MediaQuery.of(context);
    return Padding(
      padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: media.size.height * 0.9),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 8, 4),
                child: Column(
                  children: [
                    Container(
                      width: 40,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 8),
                      decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)),
                    ),
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Rate your order',
                                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                              Text(
                                '#VDR-${order.id.toString().padLeft(5, '0')}${order.storeName != null ? ' · ${order.storeName}' : ''}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          tooltip: 'Close',
                          onPressed: _submitting ? null : () => Navigator.pop(context, false),
                          icon: const Icon(Icons.close),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
                  children: [
                    for (final item in _items) _productRow(item),
                    if (canRateRider(order)) _riderRow(order.rider!),
                    const Text(
                      'Rate at least one product. Your first name and initial are shown with your review.',
                      style: TextStyle(fontSize: 11, color: AppColors.textLight),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 10, 20, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (_error != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text(_error!, style: const TextStyle(fontSize: 12, color: AppColors.error)),
                      ),
                    VendraButton(
                      text: 'Submit review',
                      icon: Icons.star_rounded,
                      isLoading: _submitting,
                      onPressed: _canSubmit ? _submit : null,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _productRow(OrderItemModel item) {
    final rating = _ratings[item.productId] ?? 0;
    final thumb = ProductModel(
      id: item.productId,
      vendorId: widget.order.vendorId ?? 0,
      name: item.productName ?? 'Product',
      price: item.unitPrice,
      publicStock: 0,
      imageUrl: item.imageUrl,
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SizedBox(
                width: 44,
                height: 44,
                child: ProductImage(product: thumb, iconSize: 20, borderRadius: BorderRadius.circular(8)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  item.productName ?? 'Product',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Center(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: RatingInput(
                value: rating,
                size: 32,
                onChanged: _submitting ? (_) {} : (v) => setState(() => _ratings[item.productId] = v),
              ),
            ),
          ),
          if (rating > 0) ...[
            const SizedBox(height: 6),
            TextField(
              controller: _comments[item.productId],
              enabled: !_submitting,
              maxLength: maxReviewComment,
              maxLines: 3,
              minLines: 1,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                hintText: 'Add a comment (optional)',
                isDense: true,
                contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _riderRow(OrderRider rider) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.secondary.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Row(
            children: [
              const Icon(Icons.delivery_dining, color: AppColors.secondary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'How was your rider, ${rider.name ?? 'your rider'}?',
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: RatingInput(
              value: _riderRating,
              size: 32,
              onChanged: _submitting ? (_) {} : (v) => setState(() => _riderRating = v),
            ),
          ),
          const Text('Optional', style: TextStyle(fontSize: 11, color: AppColors.textLight)),
        ],
      ),
    );
  }
}

/// "Rate your order" for a reviewable order, or the stars already given
class OrderReviewSection extends StatelessWidget {
  final OrderModel order;

  /// Called after the sheet closes with something saved — refresh the order
  final VoidCallback onReviewed;

  /// Tighter layout for order cards
  final bool compact;

  const OrderReviewSection({super.key, required this.order, required this.onReviewed, this.compact = false});

  @override
  Widget build(BuildContext context) {
    if (order.status != 'delivered') return const SizedBox.shrink();

    if (order.canReview) {
      return SizedBox(
        width: double.infinity,
        child: ElevatedButton.icon(
          onPressed: () async {
            if (await showOrderReviewSheet(context, order)) onReviewed();
          },
          icon: const Icon(Icons.star_rounded, size: 18),
          label: const Text('Rate your order'),
          style: ElevatedButton.styleFrom(
            backgroundColor: starColor,
            foregroundColor: AppColors.textPrimary,
            padding: EdgeInsets.symmetric(vertical: compact ? 10 : 14),
          ),
        ),
      );
    }

    if (order.reviewedAt == null) return const SizedBox.shrink();
    final rated = order.items.where((i) => i.myRating != null).toList();
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.rate_review_outlined, size: 16, color: AppColors.textSecondary),
            const SizedBox(width: 6),
            Text('Your review',
                style: TextStyle(fontSize: compact ? 12 : 15, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
          ],
        ),
        const SizedBox(height: 6),
        for (final item in rated)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(item.productName ?? 'Product',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 12, color: AppColors.textPrimary)),
                    ),
                    const SizedBox(width: 8),
                    RatingStars(rating: item.myRating!.toDouble(), size: 14),
                  ],
                ),
                if ((item.myComment ?? '').isNotEmpty)
                  Text('“${item.myComment}”',
                      maxLines: compact ? 2 : 4,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 11, fontStyle: FontStyle.italic, color: AppColors.textSecondary)),
              ],
            ),
          ),
        if (order.riderRating != null)
          Row(
            children: [
              const Icon(Icons.delivery_dining, size: 14, color: AppColors.secondary),
              const SizedBox(width: 4),
              Expanded(
                child: Text('Rider ${order.rider?.name ?? ''}'.trim(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12, color: AppColors.textPrimary)),
              ),
              RatingStars(rating: order.riderRating!.toDouble(), size: 14),
            ],
          ),
        if (rated.isEmpty && order.riderRating == null)
          const Text('Thanks — your review was saved.', style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
      ],
    );

    if (compact) return content;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: content,
    );
  }
}
