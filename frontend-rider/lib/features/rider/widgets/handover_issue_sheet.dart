// ══════════════════════════════════════════════════════════════
// Vendra Rider App - Customer unavailable at handover (FR08)
// The alternative to the handover code when nobody takes the parcel:
// a photo of the door / gate plus the rider's GPS fix and the time, filed
// as a "customer_unavailable" dispute. The server checks the rider is
// inside the delivery geofence; the order is NOT marked delivered and the
// escrow stays frozen until an admin decides (refund or try again).
// ══════════════════════════════════════════════════════════════

import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:vendra_rider/vendra_core.dart';

import '../models/rider_models.dart';
import '../services/rider_location_service.dart';

/// True when the report was filed
Future<bool> showHandoverIssueSheet(BuildContext context, RiderOrder order) async {
  final filed = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _HandoverIssueSheet(order: order),
  );
  return filed == true;
}

class _HandoverIssueSheet extends StatefulWidget {
  final RiderOrder order;
  const _HandoverIssueSheet({required this.order});

  @override
  State<_HandoverIssueSheet> createState() => _HandoverIssueSheetState();
}

class _HandoverIssueSheetState extends State<_HandoverIssueSheet> {
  static const _reasons = [
    'No one answered the door',
    'Customer phone switched off',
    'Customer refused the parcel',
    'Address could not be accessed',
  ];

  final _picker = ImagePicker();
  final _note = TextEditingController();
  String _reason = _reasons.first;
  Uint8List? _photo;
  String _photoName = 'door.jpg';
  bool _sending = false;
  String? _error;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _pick(ImageSource source) async {
    try {
      final file = await _picker.pickImage(source: source, maxWidth: 1600, imageQuality: 80);
      if (file == null) return;
      final bytes = await file.readAsBytes();
      if (!mounted) return;
      setState(() {
        _photo = bytes;
        _photoName = file.name.isNotEmpty ? file.name : 'door.jpg';
        _error = null;
      });
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not open the camera. Choose a photo from the gallery instead.');
    }
  }

  static String _mimeFor(String name) {
    final ext = name.split('.').last.toLowerCase();
    return switch (ext) {
      'png' => 'image/png',
      'webp' => 'image/webp',
      'heic' || 'heif' => 'image/heic',
      _ => 'image/jpeg',
    };
  }

  Future<void> _submit() async {
    final photo = _photo;
    if (photo == null || _sending) return;
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      final fix = await RiderLocationService().currentFix(fresh: true);
      final at = DateFormat('d MMM yyyy, h:mm a').format(DateTime.now());
      final note = _note.text.trim();
      final description = '$_reason. Reported by the rider at the drop-off on $at, GPS '
          '${fix.point.latitude.toStringAsFixed(6)}, ${fix.point.longitude.toStringAsFixed(6)}'
          '${fix.manual ? ' (simulated position)' : ''}.${note.isEmpty ? '' : ' Note: $note'}';
      final form = FormData()
        ..fields.addAll([
          MapEntry('orderId', widget.order.id.toString()),
          const MapEntry('issueType', 'customer_unavailable'),
          MapEntry('description', description),
          MapEntry('lat', fix.point.latitude.toString()),
          MapEntry('lng', fix.point.longitude.toString()),
        ])
        ..files.add(MapEntry(
          'evidence',
          MultipartFile.fromBytes(photo, filename: _photoName, contentType: DioMediaType.parse(_mimeFor(_photoName))),
        ));
      await ApiService().postMultipart(ApiConfig.disputes, form);
      if (mounted) Navigator.pop(context, true);
    } on LocationUnavailable catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (mounted) setState(() => _error = ApiService.getErrorMessage(e));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Customer unavailable', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
            const SizedBox(height: 6),
            Text(
              'Photograph the customer\'s door or gate. Your GPS position and the time are attached automatically. '
              'The order is not marked delivered: payment stays frozen in escrow until an admin reviews the report. '
              'Keep the parcel safe meanwhile.',
              style: TextStyle(fontSize: 12, height: 1.45, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final r in _reasons)
                  ChoiceChip(
                    label: Text(r),
                    selected: _reason == r,
                    showCheckmark: false,
                    selectedColor: AppColors.secondary,
                    labelStyle: TextStyle(fontSize: 12, color: _reason == r ? Colors.white : AppColors.textPrimary),
                    onSelected: _sending ? null : (_) => setState(() => _reason = r),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            if (_photo != null)
              Stack(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.memory(_photo!, height: 180, width: double.infinity, fit: BoxFit.cover),
                  ),
                  Positioned(
                    right: 8,
                    top: 8,
                    child: IconButton.filledTonal(
                      tooltip: 'Remove photo',
                      onPressed: _sending ? null : () => setState(() => _photo = null),
                      icon: const Icon(Icons.close, size: 18),
                    ),
                  ),
                ],
              )
            else
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _pick(ImageSource.camera),
                      style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
                      icon: const Icon(Icons.photo_camera_outlined),
                      label: const Text('Take photo'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _pick(ImageSource.gallery),
                      style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
                      icon: const Icon(Icons.photo_library_outlined),
                      label: const Text('Gallery'),
                    ),
                  ),
                ],
              ),
            const SizedBox(height: 12),
            TextField(
              controller: _note,
              enabled: !_sending,
              maxLines: 2,
              decoration: const InputDecoration(labelText: 'Note for the admin (optional)'),
            ),
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(_error!, style: const TextStyle(fontSize: 12, color: AppColors.error)),
            ],
            const SizedBox(height: 16),
            VendraButton(
              text: 'Send report to admin',
              icon: Icons.gavel_outlined,
              isLoading: _sending,
              onPressed: _photo == null ? null : _submit,
            ),
          ],
        ),
      ),
    );
  }
}
