import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

/// Data model for a marker on the map
class MapMarkerData {
  final LatLng position;
  final String? label;
  final IconData? icon;
  final Color? color;

  /// Called when the marker is tapped (e.g. open that store)
  final VoidCallback? onTap;

  const MapMarkerData({
    required this.position,
    this.label,
    this.icon,
    this.color,
    this.onTap,
  });
}
