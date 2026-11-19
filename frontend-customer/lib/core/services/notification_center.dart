// ══════════════════════════════════════════════════════════════
// Vendra App - Notification Center (FR09)
// Holds the inbox + unread count, stays live through RealtimeService,
// and shows a banner for each new notification.
//
// Wire it up once in main.dart:
//   MaterialApp(scaffoldMessengerKey: NotificationCenter.messengerKey, ...)
// then after login:  NotificationCenter().start();
// and on logout:     NotificationCenter().stop();
// ══════════════════════════════════════════════════════════════

import 'dart:async';

import 'package:flutter/material.dart';

import '../../config/api_config.dart';
import '../../config/app_theme.dart';
import '../models/notification_model.dart';
import '../models/page_meta.dart';
import '../widgets/notification_bell.dart' show notificationStyleFor;
import 'api_service.dart';
import 'realtime_service.dart';

class NotificationCenter extends ChangeNotifier {
  static final NotificationCenter _instance = NotificationCenter._internal();
  factory NotificationCenter() => _instance;
  NotificationCenter._internal();

  static final GlobalKey<ScaffoldMessengerState> messengerKey = GlobalKey<ScaffoldMessengerState>();

  final ApiService _api = ApiService();
  StreamSubscription<NotificationModel>? _sub;

  static const int _pageSize = 30;

  List<NotificationModel> _items = [];
  int _unread = 0;
  bool _loading = false;
  bool _loadingMore = false;
  PageMeta _meta = const PageMeta();

  List<NotificationModel> get items => List.unmodifiable(_items);
  int get unreadCount => _unread;
  bool get isLoading => _loading;
  bool get isLoadingMore => _loadingMore;
  /// Older notifications are waiting on the server
  bool get hasMore => _meta.hasMore;

  /// Loads the inbox and listens for new notifications.
  Future<void> start() async {
    await RealtimeService().connect();
    _sub ??= RealtimeService().notifications.listen(_onNew);
    await refresh();
  }

  void stop() {
    _sub?.cancel();
    _sub = null;
    _items = [];
    _unread = 0;
    _meta = const PageMeta();
    notifyListeners();
  }

  Future<void> refresh() async {
    _loading = true;
    notifyListeners();
    try {
      final res = await _api.get(ApiConfig.notifications, queryParams: {'limit': _pageSize});
      final data = res.data['data'] as Map<String, dynamic>;
      _items = _parse(data);
      _unread = data['unreadCount'] ?? 0;
      _meta = PageMeta.fromResponse(res.data);
    } catch (e) {
      debugPrint('Notifications load failed: ${ApiService.getErrorMessage(e)}');
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  /// Next page of older notifications (the inbox keeps every alert, not just the latest)
  Future<void> loadMore() async {
    if (_loadingMore || !_meta.hasMore || _meta.nextOffset == null) return;
    _loadingMore = true;
    notifyListeners();
    try {
      // Offset counts from the newest; realtime arrivals since the last page shift it, so skip repeats
      final res = await _api.get(ApiConfig.notifications, queryParams: {'limit': _pageSize, 'offset': _meta.nextOffset});
      final data = res.data['data'] as Map<String, dynamic>;
      final known = _items.map((n) => n.id).toSet();
      _items = [..._items, ..._parse(data).where((n) => !known.contains(n.id))];
      _unread = data['unreadCount'] ?? _unread;
      _meta = PageMeta.fromResponse(res.data);
    } catch (e) {
      debugPrint('Older notifications failed: ${ApiService.getErrorMessage(e)}');
    } finally {
      _loadingMore = false;
      notifyListeners();
    }
  }

  List<NotificationModel> _parse(Map<String, dynamic> data) => (data['notifications'] as List<dynamic>)
      .map((n) => NotificationModel.fromJson(Map<String, dynamic>.from(n)))
      .toList();

  /// Marks one notification read (when it's opened)
  Future<void> markRead(NotificationModel n) async {
    if (n.isRead) return;
    _items = _items.map((x) => x.id == n.id ? x.markRead() : x).toList();
    if (_unread > 0) _unread -= 1;
    notifyListeners();
    try {
      await _api.put(ApiConfig.notificationRead(n.id));
    } catch (_) {}
  }

  Future<void> markAllRead() async {
    if (_unread == 0) return;
    _items = _items.map((n) => n.markRead()).toList();
    _unread = 0;
    notifyListeners();
    try {
      await _api.put(ApiConfig.notificationsReadAll);
    } catch (_) {}
  }

  void _onNew(NotificationModel n) {
    _items = [n, ..._items];
    _unread += 1;
    notifyListeners();
    // Same icon / accent as the inbox row, on a dark navy (light theme) or raised slate (dark theme) banner
    final style = notificationStyleFor(n.type);
    messengerKey.currentState
      ?..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.isDark ? AppColors.darkSurfaceMuted : AppColors.navy,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        duration: const Duration(seconds: 4),
        content: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(10)),
              child: Icon(style.icon, color: Colors.white, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(n.title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.white)),
                  if (n.body != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(n.body!,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 13, height: 1.35)),
                    ),
                ],
              ),
            ),
          ],
        ),
      ));
  }
}
