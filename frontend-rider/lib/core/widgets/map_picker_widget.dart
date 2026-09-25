// ══════════════════════════════════════════════════════════════
// Vendra App - Map Picker Widget
// Reusable OpenStreetMap-based location picker
// Used by: vendor location setup, customer delivery address
// ══════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../config/app_theme.dart';
import '../models/map_marker_data.dart';

export '../models/map_marker_data.dart';

class MapPickerWidget extends StatefulWidget {
  /// Initial center of the map
  final LatLng initialCenter;

  /// Initial zoom level
  final double initialZoom;

  /// Whether the user can tap to pick a location
  final bool interactive;

  /// Callback when a location is selected
  final ValueChanged<LatLng>? onLocationSelected;

  /// Optional list of markers to display (e.g., vendor locations)
  final List<MapMarkerData>? markers;

  /// Height of the map widget; double.infinity fills the parent (which must be bounded)
  final double height;

  /// Whether to show the "Confirm" button
  final bool showConfirmButton;

  /// Label for confirm button
  final String confirmLabel;

  const MapPickerWidget({
    super.key,
    this.initialCenter = const LatLng(33.6844, 73.0479), // Islamabad default
    this.initialZoom = 13.0,
    this.interactive = true,
    this.onLocationSelected,
    this.markers,
    this.height = 300,
    this.showConfirmButton = false,
    this.confirmLabel = 'Confirm Location',
  });

  @override
  State<MapPickerWidget> createState() => _MapPickerWidgetState();
}

class _MapPickerWidgetState extends State<MapPickerWidget> {
  late LatLng _selectedLocation;
  late MapController _mapController;

  @override
  void initState() {
    super.initState();
    _selectedLocation = widget.initialCenter;
    _mapController = MapController();
  }

  @override
  Widget build(BuildContext context) {
    final map = Container(
      height: widget.height.isFinite ? widget.height : null,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade300),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: widget.initialCenter,
              initialZoom: widget.initialZoom,
              onTap: widget.interactive
                  ? (tapPosition, point) {
                      setState(() => _selectedLocation = point);
                      widget.onLocationSelected?.call(point);
                    }
                  : null,
            ),
            children: [
              // OpenStreetMap tile layer
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.vendra.app',
              ),

              // Custom markers
              if (widget.markers != null && widget.markers!.isNotEmpty)
                MarkerLayer(
                  markers: widget.markers!
                      .map((m) => Marker(
                            point: m.position,
                            width: 40,
                            height: 40,
                            child: Tooltip(
                              message: m.label ?? '',
                              child: m.onTap == null
                                  ? _markerIcon(m)
                                  : MouseRegion(
                                      cursor: SystemMouseCursors.click,
                                      child: GestureDetector(onTap: m.onTap, child: _markerIcon(m)),
                                    ),
                            ),
                          ))
                      .toList(),
                ),

              // Selected location marker (only when interactive)
              if (widget.interactive)
                MarkerLayer(
                  markers: [
                    Marker(
                      point: _selectedLocation,
                      width: 50,
                      height: 50,
                      child: const Icon(
                        Icons.location_pin,
                        color: AppColors.primary,
                        size: 42,
                      ),
                    ),
                  ],
                ),
            ],
          ),

          // Coordinates display
          Positioned(
            bottom: 8,
            left: 8,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.9),
                borderRadius: BorderRadius.circular(8),
                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 4)],
              ),
              child: Text(
                '${_selectedLocation.latitude.toStringAsFixed(4)}, ${_selectedLocation.longitude.toStringAsFixed(4)}',
                style: GoogleFonts.poppins(fontSize: 11, color: AppColors.textSecondary),
              ),
            ),
          ),

          // Zoom controls
          Positioned(
            right: 8,
            top: 8,
            child: Column(
              children: [
                _zoomButton(Icons.add, () {
                  _mapController.move(
                    _mapController.camera.center,
                    _mapController.camera.zoom + 1,
                  );
                }),
                const SizedBox(height: 4),
                _zoomButton(Icons.remove, () {
                  _mapController.move(
                    _mapController.camera.center,
                    _mapController.camera.zoom - 1,
                  );
                }),
              ],
            ),
          ),
        ],
      ),
    );

    // A Column gives its children unbounded height, so a full-size map is returned on its own
    if (!widget.showConfirmButton) return map;

    return Column(
      children: [
        map,
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: () => widget.onLocationSelected?.call(_selectedLocation),
            icon: const Icon(Icons.check, size: 18),
            label: Text(widget.confirmLabel, style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ),
      ],
    );
  }

  Widget _markerIcon(MapMarkerData m) =>
      Icon(m.icon ?? Icons.storefront, color: m.color ?? AppColors.secondary, size: 32);

  Widget _zoomButton(IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(6),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.15), blurRadius: 4)],
        ),
        child: Icon(icon, size: 18, color: AppColors.textPrimary),
      ),
    );
  }
}
