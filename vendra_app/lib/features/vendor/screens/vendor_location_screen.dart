// ══════════════════════════════════════════════════════════════
// Vendra App - Vendor Location Screen
// Vendor sets their shop location on the map
// ══════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:latlong2/latlong.dart';
import '../../../config/app_theme.dart';
import '../../../core/widgets/map_picker_widget.dart';
import '../../../core/services/api_service.dart';
import '../../../config/api_config.dart';

class VendorLocationScreen extends StatefulWidget {
  final double? currentLat;
  final double? currentLng;

  const VendorLocationScreen({super.key, this.currentLat, this.currentLng});

  @override
  State<VendorLocationScreen> createState() => _VendorLocationScreenState();
}

class _VendorLocationScreenState extends State<VendorLocationScreen> {
  LatLng? _selectedLocation;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    if (widget.currentLat != null && widget.currentLng != null) {
      _selectedLocation = LatLng(widget.currentLat!, widget.currentLng!);
    }
  }

  Future<void> _saveLocation() async {
    if (_selectedLocation == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Tap on the map to select your store location'), behavior: SnackBarBehavior.floating),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      final response = await ApiService().put(
        ApiConfig.vendorLocation,
        data: {
          'latitude': _selectedLocation!.latitude,
          'longitude': _selectedLocation!.longitude,
        },
      );

      if (response.data['success'] == true) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('✅ Store location updated successfully!'),
              backgroundColor: AppColors.success,
              behavior: SnackBarBehavior.floating,
            ),
          );
          Navigator.pop(context, _selectedLocation);
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(response.data['message'] ?? 'Failed to update'),
              backgroundColor: AppColors.error,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(ApiService.getErrorMessage(e)),
            backgroundColor: AppColors.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
    if (mounted) setState(() => _saving = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text('Set Store Location', style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Instructions
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFE3F2FD),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.blue.shade200),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline, color: Colors.blue.shade700, size: 22),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Tap on the map to pin your shop location. Customers will see distance from their location to your shop.',
                      style: GoogleFonts.poppins(fontSize: 12, color: Colors.blue.shade800),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // Map
            MapPickerWidget(
              initialCenter: _selectedLocation ?? const LatLng(33.6844, 73.0479),
              initialZoom: 14.0,
              interactive: true,
              height: 400,
              onLocationSelected: (latLng) {
                setState(() => _selectedLocation = latLng);
              },
            ),

            const SizedBox(height: 16),

            // Selected location display
            if (_selectedLocation != null)
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8)],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Selected Location', style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        const Icon(Icons.location_on, size: 18, color: AppColors.primary),
                        const SizedBox(width: 8),
                        Text(
                          'Lat: ${_selectedLocation!.latitude.toStringAsFixed(6)}',
                          style: GoogleFonts.poppins(fontSize: 13),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        const Icon(Icons.location_on, size: 18, color: AppColors.secondary),
                        const SizedBox(width: 8),
                        Text(
                          'Lng: ${_selectedLocation!.longitude.toStringAsFixed(6)}',
                          style: GoogleFonts.poppins(fontSize: 13),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

            const SizedBox(height: 20),

            // Save button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _saving ? null : _saveLocation,
                icon: _saving
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.save),
                label: Text(
                  _saving ? 'Saving...' : 'Save Store Location',
                  style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),

            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}
