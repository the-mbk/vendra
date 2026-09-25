// ══════════════════════════════════════════════════════════════
// Vendra App - Pagination metadata
// Paged endpoints return { data: [...], meta: { limit, offset, hasMore, nextOffset } }.
// Load the next page with ?offset=nextOffset while hasMore is true.
// ══════════════════════════════════════════════════════════════

import 'json_utils.dart';

class PageMeta {
  final int limit;
  final int offset;
  final bool hasMore;
  final int? nextOffset;

  const PageMeta({this.limit = 20, this.offset = 0, this.hasMore = false, this.nextOffset});

  factory PageMeta.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const PageMeta();
    return PageMeta(
      limit: toInt(json['limit'], 20),
      offset: toInt(json['offset']),
      hasMore: json['hasMore'] == true,
      nextOffset: toIntOrNull(json['nextOffset']),
    );
  }

  /// Reads `meta` from a full response body (`response.data`)
  factory PageMeta.fromResponse(dynamic body) =>
      PageMeta.fromJson(body is Map && body['meta'] is Map ? Map<String, dynamic>.from(body['meta']) : null);
}
