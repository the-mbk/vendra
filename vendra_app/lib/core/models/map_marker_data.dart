import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

/// Data model for a marker on the map
class MapMarkerData {
  final LatLng position;
  final String? label;
  final IconData? icon;
  final Color? color;

  const MapMarkerData({
    required this.position,
    this.label,
    this.icon,
    this.color,
  });
}
