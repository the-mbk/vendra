// ══════════════════════════════════════════════════════════════
// Vendra App - Realtime Service (Socket.IO)
// One socket per app. Connect after login (with the JWT) or anonymously
// for public stock updates; disconnect on logout.
//
// Server events → streams:
//   notification     → notifications       (FR09)
//   order:update     → orderUpdates        status / escrow changes
//   stock:update     → stockUpdates        public stock (marketplace)
//   stock:vendor     → vendorStock         private/reserved (vendor POS)
//   rider:location   → riderLocations      live rider position (customer map)
//   task:new         → newTasks            ready orders (riders)
//   task:taken       → takenTasks          another rider accepted
//   catalog:update   → catalogUpdates      products approved/hidden
// ══════════════════════════════════════════════════════════════

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:socket_io_client/socket_io_client.dart' as sio;

import '../../config/api_config.dart';
import '../models/json_utils.dart';
import '../models/notification_model.dart';
import 'storage_service.dart';

class OrderUpdateEvent {
  final int orderId;
  final String status;
  final String? escrowStatus;
  final int? riderUserId;
  OrderUpdateEvent(this.orderId, this.status, this.escrowStatus, this.riderUserId);
}

class StockUpdateEvent {
  final int productId;
  final int vendorId;
  final int publicStock;
  StockUpdateEvent(this.productId, this.vendorId, this.publicStock);
}

class VendorStockEvent {
  final int productId;
  final int privateStock;
  final int reservedQuantity;
  final int buffer;
  final int publicStock;
  VendorStockEvent(this.productId, this.privateStock, this.reservedQuantity, this.buffer, this.publicStock);
}

class RiderLocationEvent {
  final int orderId;
  final double lat;
  final double lng;
  final DateTime? at;
  RiderLocationEvent(this.orderId, this.lat, this.lng, this.at);
}

class RealtimeService {
  static final RealtimeService _instance = RealtimeService._internal();
  factory RealtimeService() => _instance;
  RealtimeService._internal();

  sio.Socket? _socket;
  String? _token;

  final _notifications = StreamController<NotificationModel>.broadcast();
  final _orderUpdates = StreamController<OrderUpdateEvent>.broadcast();
  final _stockUpdates = StreamController<StockUpdateEvent>.broadcast();
  final _vendorStock = StreamController<VendorStockEvent>.broadcast();
  final _riderLocations = StreamController<RiderLocationEvent>.broadcast();
  final _newTasks = StreamController<int>.broadcast();
  final _takenTasks = StreamController<int>.broadcast();
  final _catalogUpdates = StreamController<void>.broadcast();
  final _connected = ValueNotifier<bool>(false);

  Stream<NotificationModel> get notifications => _notifications.stream;
  Stream<OrderUpdateEvent> get orderUpdates => _orderUpdates.stream;
  Stream<StockUpdateEvent> get stockUpdates => _stockUpdates.stream;
  Stream<VendorStockEvent> get vendorStock => _vendorStock.stream;
  Stream<RiderLocationEvent> get riderLocations => _riderLocations.stream;
  Stream<int> get newTasks => _newTasks.stream;
  Stream<int> get takenTasks => _takenTasks.stream;
  Stream<void> get catalogUpdates => _catalogUpdates.stream;
  ValueListenable<bool> get connected => _connected;

  /// Connects (or reconnects) using the stored JWT. Safe to call repeatedly.
  Future<void> connect({bool anonymous = false}) async {
    final token = anonymous ? null : await StorageService.getToken();
    if (_socket != null && token == _token) {
      if (_socket!.disconnected) _socket!.connect();
      return;
    }
    disconnect();
    _token = token;

    final builder = sio.OptionBuilder()
        .setTransports(['websocket'])
        .disableAutoConnect()
        .enableReconnection();
    if (token != null && token.isNotEmpty) builder.setAuth({'token': token});

    final socket = sio.io(ApiConfig.socketUrl, builder.build());
    _socket = socket;

    socket.onConnect((_) => _connected.value = true);
    socket.onDisconnect((_) => _connected.value = false);
    socket.onConnectError((e) => debugPrint('Realtime connect error: $e'));

    socket.on('notification', (d) => _notifications.add(NotificationModel.fromJson(_map(d))));
    socket.on('order:update', (d) {
      final m = _map(d);
      _orderUpdates.add(OrderUpdateEvent(toInt(m['orderId']), m['status'] ?? '', m['escrowStatus'], toIntOrNull(m['riderUserId'])));
    });
    socket.on('stock:update', (d) {
      final m = _map(d);
      _stockUpdates.add(StockUpdateEvent(toInt(m['productId']), toInt(m['vendorId']), toInt(m['publicStock'])));
    });
    socket.on('stock:vendor', (d) {
      final m = _map(d);
      _vendorStock.add(VendorStockEvent(toInt(m['productId']), toInt(m['privateStock']),
          toInt(m['reservedQuantity']), toInt(m['buffer']), toInt(m['publicStock'])));
    });
    socket.on('rider:location', (d) {
      final m = _map(d);
      _riderLocations.add(RiderLocationEvent(toInt(m['orderId']), toDouble(m['lat']), toDouble(m['lng']), toDate(m['at'])));
    });
    socket.on('task:new', (d) => _newTasks.add(toInt(_map(d)['orderId'])));
    socket.on('task:taken', (d) => _takenTasks.add(toInt(_map(d)['orderId'])));
    socket.on('catalog:update', (_) => _catalogUpdates.add(null));

    socket.connect();
  }

  void disconnect() {
    _socket?.dispose();
    _socket = null;
    _token = null;
    _connected.value = false;
  }

  static Map<String, dynamic> _map(dynamic d) =>
      d is Map ? Map<String, dynamic>.from(d) : <String, dynamic>{};
}
