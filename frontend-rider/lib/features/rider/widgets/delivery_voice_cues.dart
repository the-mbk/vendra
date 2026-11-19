// ══════════════════════════════════════════════════════════════
// Vendra Rider App - speaks the delivery's voice cues as the rider moves
// (location updates) and as the delivery advances (order changes).
// ══════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../models/rider_models.dart';
import '../services/rider_location_service.dart';
import '../services/voice_cues.dart';

class DeliveryVoiceCues extends StatefulWidget {
  final RiderOrder order;
  final double geofenceMeters;
  final Widget child;
  const DeliveryVoiceCues({super.key, required this.order, required this.geofenceMeters, required this.child});

  @override
  State<DeliveryVoiceCues> createState() => _DeliveryVoiceCuesState();
}

class _DeliveryVoiceCuesState extends State<DeliveryVoiceCues> {
  final _location = RiderLocationService();
  final _voice = VoiceCues();

  @override
  void initState() {
    super.initState();
    _location.addListener(_check);
    _voice.init().then((_) => _check());
  }

  @override
  void didUpdateWidget(DeliveryVoiceCues old) {
    super.didUpdateWidget(old);
    if (old.order.step != widget.order.step || old.order.id != widget.order.id) _check();
  }

  @override
  void dispose() {
    _location.removeListener(_check);
    super.dispose();
  }

  void _check() {
    final here = _location.position;
    double? to(LatLng? p) => here == null || p == null ? null : const Distance().as(LengthUnit.Meter, here, p);
    _voice.say(voiceCueFor(
      widget.order,
      metersToStore: to(widget.order.storePoint),
      metersToCustomer: to(widget.order.customerPoint),
      geofenceMeters: widget.geofenceMeters,
    ));
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
