// ══════════════════════════════════════════════════════════════
// Vendra Vendor App - Customer reviews (SRDS §2.3)
// GET /api/vendor/reviews — paged, newest first; meta.count and
// meta.average give the store's overall rating. More load on scroll.
// ══════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:vendra_vendor/vendra_core.dart';

class VendorReviewsScreen extends StatefulWidget {
  const VendorReviewsScreen({super.key});

  @override
  State<VendorReviewsScreen> createState() => _VendorReviewsScreenState();
}

class _VendorReviewsScreenState extends State<VendorReviewsScreen> {
  static const int _pageSize = 20;
  final ApiService _api = ApiService();

  List<ReviewModel> _reviews = [];
  PageMeta _meta = const PageMeta();
  int _count = 0;
  double? _average;
  bool _loading = true;
  bool _loadingMore = false;
  String? _error;
  String? _moreError;

  @override
  void initState() {
    super.initState();
    _load();
  }

  static List<ReviewModel> _parse(dynamic data) =>
      (data as List).map((j) => ReviewModel.fromJson(Map<String, dynamic>.from(j as Map))).toList();

  Future<void> _load() async {
    setState(() {
      _error = null;
      if (_reviews.isEmpty) _loading = true;
    });
    try {
      final res = await _api.get(ApiConfig.vendorReviews, queryParams: {'limit': _pageSize, 'offset': 0});
      final meta = res.data['meta'] is Map ? Map<String, dynamic>.from(res.data['meta']) : const <String, dynamic>{};
      if (!mounted) return;
      setState(() {
        _reviews = _parse(res.data['data']);
        _meta = PageMeta.fromResponse(res.data);
        _count = toInt(meta['count'], _reviews.length);
        _average = toDoubleOrNull(meta['average']);
        _loading = false;
        _moreError = null;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = ApiService.getErrorMessage(e);
        });
      }
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_meta.hasMore) return;
    setState(() {
      _loadingMore = true;
      _moreError = null;
    });
    try {
      final res = await _api.get(ApiConfig.vendorReviews,
          queryParams: {'limit': _pageSize, 'offset': _meta.nextOffset ?? _reviews.length});
      if (!mounted) return;
      final known = _reviews.map((r) => r.id).toSet();
      setState(() {
        _reviews = [..._reviews, ..._parse(res.data['data']).where((r) => !known.contains(r.id))];
        _meta = PageMeta.fromResponse(res.data);
      });
    } catch (e) {
      if (mounted) setState(() => _moreError = ApiService.getErrorMessage(e));
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: Text('Customer reviews', style: GoogleFonts.poppins(fontWeight: FontWeight.w600))),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
          : _error != null && _reviews.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_error!, textAlign: TextAlign.center, style: GoogleFonts.poppins(color: AppColors.textSecondary)),
                        const SizedBox(height: 12),
                        OutlinedButton(onPressed: _load, child: const Text('Retry')),
                      ],
                    ),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: NotificationListener<ScrollNotification>(
                    onNotification: (n) {
                      if (n.metrics.extentAfter < 300 && _meta.hasMore && !_loadingMore && _moreError == null) _loadMore();
                      return false;
                    },
                    child: ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: _reviews.length + 2,
                      itemBuilder: (context, i) {
                        if (i == 0) return _summary();
                        if (i <= _reviews.length) return _reviewCard(_reviews[i - 1]);
                        return _footer();
                      },
                    ),
                  ),
                ),
    );
  }

  Widget _summary() {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8)],
      ),
      child: Row(
        children: [
          Text(_average?.toStringAsFixed(1) ?? '–',
              style: GoogleFonts.poppins(fontSize: 34, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                RatingStars(rating: _average ?? 0, size: 20),
                const SizedBox(height: 2),
                Text(
                  _count == 0 ? 'No reviews yet' : '$_count review${_count == 1 ? '' : 's'} across your products',
                  style: GoogleFonts.poppins(fontSize: 12, color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _reviewCard(ReviewModel r) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(r.productName ?? 'Product #${r.productId}',
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w600)),
              ),
              const SizedBox(width: 8),
              RatingStars(rating: r.rating.toDouble(), size: 15),
            ],
          ),
          if (r.comment != null && r.comment!.trim().isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(r.comment!, style: GoogleFonts.poppins(fontSize: 13, color: AppColors.textPrimary, height: 1.4)),
          ],
          const SizedBox(height: 6),
          Text(
            [
              r.customerName,
              if (r.createdAt != null) DateFormat('d MMM yyyy').format(r.createdAt!),
              if (r.orderId != null) 'Order #${r.orderId}',
            ].join(' · '),
            style: GoogleFonts.poppins(fontSize: 11, color: AppColors.textLight),
          ),
        ],
      ),
    );
  }

  Widget _footer() {
    Widget? child;
    if (_loadingMore) {
      child = const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5));
    } else if (_meta.hasMore) {
      child = Column(
        children: [
          if (_moreError != null)
            Text(_moreError!, textAlign: TextAlign.center, style: GoogleFonts.poppins(fontSize: 12, color: AppColors.error)),
          OutlinedButton(onPressed: _loadMore, child: Text(_moreError != null ? 'Try again' : 'Load more')),
        ],
      );
    } else if (_reviews.isEmpty) {
      child = Padding(
        padding: const EdgeInsets.only(top: 40),
        child: Column(
          children: [
            Icon(Icons.reviews_outlined, size: 52, color: Colors.grey.shade300),
            const SizedBox(height: 8),
            Text('Customers can rate products after a delivered order.',
                textAlign: TextAlign.center, style: GoogleFonts.poppins(fontSize: 12, color: AppColors.textSecondary)),
          ],
        ),
      );
    }
    if (child == null) return const SizedBox(height: 16);
    return Padding(padding: const EdgeInsets.symmetric(vertical: 12), child: Center(child: child));
  }
}
