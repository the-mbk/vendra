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
import 'api_service.dart';
import 'realtime_service.dart';

class NotificationCenter extends ChangeNotifier {
  static final NotificationCenter _instance = NotificationCenter._internal();
  factory NotificationCenter() => _instance;
  NotificationCenter._internal();

  static final GlobalKey<ScaffoldMessengerState> messengerKey = GlobalKey<ScaffoldMessengerState>();

  final ApiService _api = ApiService();
  StreamSubscription<NotificationModel>? _sub;

  List<NotificationModel> _items = [];
  int _unread = 0;
  bool _loading = false;

  List<NotificationModel> get items => List.unmodifiable(_items);
  int get unreadCount => _unread;
  bool get isLoading => _loading;

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
    notifyListeners();
  }

  Future<void> refresh() async {
    _loading = true;
    notifyListeners();
    try {
      final res = await _api.get(ApiConfig.notifications);
      final data = res.data['data'] as Map<String, dynamic>;
      _items = (data['notifications'] as List<dynamic>)
          .map((n) => NotificationModel.fromJson(Map<String, dynamic>.from(n)))
          .toList();
      _unread = data['unreadCount'] ?? 0;
    } catch (e) {
      debugPrint('Notifications load failed: ${ApiService.getErrorMessage(e)}');
    } finally {
      _loading = false;
      notifyListeners();
    }
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
    messengerKey.currentState
      ?..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.secondary,
        duration: const Duration(seconds: 4),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(n.title, style: const TextStyle(fontWeight: FontWeight.w600, color: Colors.white)),
            if (n.body != null) Text(n.body!, style: const TextStyle(color: Colors.white70, fontSize: 12)),
          ],
        ),
      ));
  }
}
