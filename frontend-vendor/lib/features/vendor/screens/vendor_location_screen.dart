// ══════════════════════════════════════════════════════════════
// Vendra App - Vendor Location Screen
// Vendor sets their shop location on the map.
// A store still waiting for approval moves immediately; an approved
// store's move is sent to the admin and the live location stays put
// until it is approved (the request can be withdrawn meanwhile).
// Pops with a StoreLocationResult after a save.
// ══════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';
import 'package:vendra_vendor/vendra_core.dart';

import '../../auth/bloc/auth_bloc.dart';
import '../../auth/bloc/auth_state.dart' as auth_state;
import '../bloc/store_location_bloc.dart';
import '../models/store_location_status.dart';

/// Marker colour for a location change waiting for the admin
const Color _pendingColor = Color(0xFF8E24AA);

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
  bool _withdrawing = false;
  bool _rejectionDismissed = false;

  @override
  void initState() {
    super.initState();
    if (widget.currentLat != null && widget.currentLng != null) {
      _selectedLocation = LatLng(widget.currentLat!, widget.currentLng!);
    } else {
      _selectedLocation = context.read<StoreLocationBloc>().state.status?.point;
    }
    // Pick up an approval / rejection that happened since the home screen loaded
    context.read<StoreLocationBloc>().add(const StoreLocationRequested());
  }

  /// Approval flag: the location status from /auth/me, else the signed-in user
  bool get _isApproved {
    final status = context.read<StoreLocationBloc>().state.status;
    if (status != null) return status.isApproved;
    final auth = context.read<AuthBloc>().state;
    return auth is auth_state.Authenticated && auth.user.isApproved == true;
  }

  void _showSnack(String message, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: color, behavior: SnackBarBehavior.floating),
    );
  }

  Future<void> _saveLocation() async {
    if (_selectedLocation == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Tap on the map to select your store location'), behavior: SnackBarBehavior.floating),
      );
      return;
    }

    final isApproved = _isApproved;
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
        final data = response.data['data'] is Map<String, dynamic> ? response.data['data'] as Map<String, dynamic> : <String, dynamic>{};
        // 200 = applied now; 202 = waiting for the admin
        final applied = data['applied'] != false && response.statusCode != 202;
        final status = StoreLocationStatus.fromLocationResponse(data, isApproved: isApproved);
        if (!mounted) return;
        context.read<StoreLocationBloc>().add(StoreLocationReplaced(status));
        if (applied) {
          _showSnack('✅ Store location updated successfully!', AppColors.success);
        } else {
          _showSnack(
            response.data['message'] ??
                'Sent to Vendra for approval. Customers and riders keep seeing your current location until an admin approves the change.',
            AppColors.secondary,
          );
        }
        Navigator.pop(
          context,
          StoreLocationResult(applied: applied, message: response.data['message']?.toString() ?? '', status: status),
        );
        return;
      } else {
        if (mounted) _showSnack(response.data['message'] ?? 'Failed to update', AppColors.error);
      }
    } catch (e) {
      if (mounted) _showSnack(ApiService.getErrorMessage(e), AppColors.error);
    }
    if (mounted) setState(() => _saving = false);
  }

  Future<void> _withdrawRequest() async {
    final isApproved = _isApproved;
    setState(() => _withdrawing = true);
    try {
      final response = await ApiService().delete('${ApiConfig.vendorLocation}/request');
      if (response.data['success'] == true) {
        final data = response.data['data'] is Map<String, dynamic> ? response.data['data'] as Map<String, dynamic> : <String, dynamic>{};
        if (!mounted) return;
        context.read<StoreLocationBloc>().add(
              StoreLocationReplaced(StoreLocationStatus.fromLocationResponse(data, isApproved: isApproved)),
            );
        _showSnack(response.data['message'] ?? 'Location change withdrawn.', AppColors.success);
      } else {
        if (mounted) _showSnack(response.data['message'] ?? 'Failed to withdraw the request', AppColors.error);
      }
    } catch (e) {
      if (mounted) _showSnack(ApiService.getErrorMessage(e), AppColors.error);
    }
    if (mounted) setState(() => _withdrawing = false);
  }

  String _saveLabel(StoreLocationStatus? status, bool approved) {
    if (!approved) return 'Save location';
    return (status?.hasLocation ?? true) ? 'Request location change' : 'Send location for approval';
  }

  Widget _pendingBanner(PendingStoreLocation pending) {
    final when = pending.requestedAt != null ? DateFormat('MMM dd, hh:mm a').format(pending.requestedAt!) : 'recently';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: AppColors.warning.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.warning),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.hourglass_top, size: 20, color: Color(0xFF8A6D00)),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Waiting for admin approval: new location requested $when',
                      style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w600, color: const Color(0xFF8A6D00)),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        const Icon(Icons.location_on, size: 16, color: _pendingColor),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            pending.address ??
                                '${pending.latitude.toStringAsFixed(6)}, ${pending.longitude.toStringAsFixed(6)}',
                            style: GoogleFonts.poppins(fontSize: 12, color: AppColors.textPrimary),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Customers and riders keep seeing your current location until it is approved.',
                      style: GoogleFonts.poppins(fontSize: 11, color: AppColors.textSecondary),
                    ),
                  ],
                ),
              ),
            ],
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: _withdrawing || _saving ? null : _withdrawRequest,
              icon: _withdrawing
                  ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.undo, size: 18),
              label: Text('Withdraw request', style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
              style: TextButton.styleFrom(foregroundColor: AppColors.error),
            ),
          ),
        ],
      ),
    );
  }

  Widget _rejectionBanner(String reason) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 6, 4, 6),
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: AppColors.error.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.error.withValues(alpha: 0.5)),
      ),
      child: Row(
        children: [
          const Icon(Icons.warning_amber_rounded, size: 20, color: AppColors.error),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Your last location change was rejected: $reason',
              style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w500, color: AppColors.error),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 18),
            color: AppColors.textSecondary,
            tooltip: 'Dismiss',
            onPressed: () => setState(() => _rejectionDismissed = true),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text('Set Store Location', style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
      ),
      body: BlocBuilder<StoreLocationBloc, StoreLocationState>(
        builder: (context, locationState) {
          final status = locationState.status;
          final pending = status?.pending;
          final rejection = status?.rejectionReason;
          final live = status?.point;
          final authState = context.watch<AuthBloc>().state;
          final approved = status?.isApproved ??
              (authState is auth_state.Authenticated && authState.user.isApproved == true);

          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (pending != null) _pendingBanner(pending),
                if (pending == null && rejection != null && !_rejectionDismissed) _rejectionBanner(rejection),

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
                          approved
                              ? 'Tap on the map to pin your new shop location. Vendra reviews location changes for approved stores — your current location stays live until an admin approves.'
                              : 'Tap on the map to pin your shop location. Customers will see distance from their location to your shop.',
                          style: GoogleFonts.poppins(fontSize: 12, color: Colors.blue.shade800),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 16),

                // Map: the pin is the location being picked; the live store and a pending request are shown too
                MapPickerWidget(
                  initialCenter: _selectedLocation ?? const LatLng(33.6844, 73.0479),
                  initialZoom: 14.0,
                  interactive: true,
                  height: 400,
                  markers: [
                    if (live != null) MapMarkerData(position: live, label: 'Current store location'),
                    if (pending != null)
                      MapMarkerData(
                        position: pending.point,
                        label: 'Requested location (waiting for approval)',
                        icon: Icons.location_on,
                        color: _pendingColor,
                      ),
                  ],
                  onLocationSelected: (latLng) {
                    setState(() => _selectedLocation = latLng);
                  },
                ),

                if (pending != null) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Icon(Icons.storefront, size: 16, color: AppColors.secondary),
                      const SizedBox(width: 4),
                      Text('Current', style: GoogleFonts.poppins(fontSize: 11, color: AppColors.textSecondary)),
                      const SizedBox(width: 14),
                      const Icon(Icons.location_on, size: 16, color: _pendingColor),
                      const SizedBox(width: 4),
                      Text('Requested', style: GoogleFonts.poppins(fontSize: 11, color: AppColors.textSecondary)),
                    ],
                  ),
                ],

                const SizedBox(height: 16),

                // Selected location display
                if (_selectedLocation != null)
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8)],
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

                if (pending != null) ...[
                  const SizedBox(height: 10),
                  Text(
                    'Sending a new request replaces the one waiting for approval.',
                    style: GoogleFonts.poppins(fontSize: 11, color: AppColors.textSecondary),
                  ),
                ],

                const SizedBox(height: 20),

                // Save button
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _saving || _withdrawing ? null : _saveLocation,
                    icon: _saving
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : Icon(approved ? Icons.send : Icons.save),
                    label: Text(
                      _saving ? 'Saving...' : _saveLabel(status, approved),
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
          );
        },
      ),
    );
  }
}
