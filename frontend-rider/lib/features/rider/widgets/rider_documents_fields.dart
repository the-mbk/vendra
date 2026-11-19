// ══════════════════════════════════════════════════════════════
// Vendra Rider App - Rider document fields
// CNIC (auto-formatted 12345-1234567-1), vehicle type, driving licence
// and vehicle registration number. Used at sign-up and by the "Update
// documents" form. Licence and registration are hidden for a bicycle.
// Put inside a Form: every field validates like the server does.
// ══════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:vendra_rider/vendra_core.dart';

import '../models/rider_documents_rules.dart';

class RiderDocumentsFields extends StatelessWidget {
  final TextEditingController cnicController;
  final TextEditingController licenceController;
  final TextEditingController vehicleNumberController;
  final String vehicleType;
  final ValueChanged<String> onVehicleChanged;
  final bool enabled;

  const RiderDocumentsFields({
    super.key,
    required this.cnicController,
    required this.licenceController,
    required this.vehicleNumberController,
    required this.vehicleType,
    required this.onVehicleChanged,
    this.enabled = true,
  });

  static IconData vehicleIcon(String? type) {
    switch (type) {
      case 'bicycle':
        return Icons.pedal_bike;
      case 'car':
        return Icons.directions_car;
      case 'scooter':
        return Icons.moped;
      default:
        return Icons.two_wheeler;
    }
  }

  @override
  Widget build(BuildContext context) {
    final motorised = vehicleNeedsLicence(vehicleType);
    Widget option(String value, String label) => Expanded(
          child: _VehicleOption(
            label: label,
            icon: vehicleIcon(value),
            selected: vehicleType == value || (value == 'motorcycle' && vehicleType == 'motorbike'),
            onTap: enabled ? () => onVehicleChanged(value) : null,
          ),
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _DocField(
          label: 'CNIC',
          hint: '12345-1234567-1',
          controller: cnicController,
          icon: Icons.badge_outlined,
          enabled: enabled,
          keyboardType: TextInputType.number,
          inputFormatters: const [CnicInputFormatter()],
          validator: validateCnic,
        ),
        const SizedBox(height: 16),
        Text('Vehicle', style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w500, color: AppColors.textPrimary)),
        const SizedBox(height: 8),
        // 2 × 2 so the labels fit on narrow phones
        Row(children: [
          option(riderVehicleTypes[0].$1, riderVehicleTypes[0].$2),
          const SizedBox(width: 8),
          option(riderVehicleTypes[1].$1, riderVehicleTypes[1].$2),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          option(riderVehicleTypes[2].$1, riderVehicleTypes[2].$2),
          const SizedBox(width: 8),
          option(riderVehicleTypes[3].$1, riderVehicleTypes[3].$2),
        ]),
        if (motorised) ...[
          const SizedBox(height: 16),
          _DocField(
            label: 'Driving licence number',
            hint: 'e.g. LHR-DL-123456',
            controller: licenceController,
            icon: Icons.credit_card_outlined,
            enabled: enabled,
            validator: validateLicenceNumber,
          ),
          const SizedBox(height: 16),
          _DocField(
            label: 'Vehicle registration number',
            hint: 'e.g. LEA-1234',
            controller: vehicleNumberController,
            icon: Icons.pin_outlined,
            enabled: enabled,
            validator: validateVehicleNumber,
          ),
        ] else ...[
          const SizedBox(height: 10),
          Row(
            children: [
              Icon(Icons.info_outline, size: 16, color: AppColors.textSecondary),
              const SizedBox(width: 6),
              Expanded(
                child: Text('No licence or registration needed for a bicycle.',
                    style: GoogleFonts.poppins(fontSize: 12, color: AppColors.textSecondary)),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

/// Same look as VendraTextField, plus formatting and capitals for document numbers
class _DocField extends StatelessWidget {
  final String label;
  final String hint;
  final TextEditingController controller;
  final IconData icon;
  final bool enabled;
  final TextInputType keyboardType;
  final List<TextInputFormatter>? inputFormatters;
  final String? Function(String?) validator;

  const _DocField({
    required this.label,
    required this.hint,
    required this.controller,
    required this.icon,
    required this.enabled,
    required this.validator,
    this.keyboardType = TextInputType.text,
    this.inputFormatters,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500, color: Colors.black87)),
        const SizedBox(height: 8),
        TextFormField(
          controller: controller,
          enabled: enabled,
          keyboardType: keyboardType,
          textCapitalization: TextCapitalization.characters,
          inputFormatters: inputFormatters,
          validator: validator,
          autovalidateMode: AutovalidateMode.onUserInteraction,
          decoration: InputDecoration(hintText: hint, prefixIcon: Icon(icon, size: 20)),
        ),
      ],
    );
  }
}

class _VehicleOption extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback? onTap;

  const _VehicleOption({required this.label, required this.icon, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      selected: selected,
      button: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
          decoration: BoxDecoration(
            color: selected ? AppColors.secondary.withValues(alpha: 0.08) : Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: selected ? AppColors.secondary : AppColors.hairline, width: selected ? 1.5 : 1),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 20, color: selected ? AppColors.secondary : AppColors.textSecondary),
              const SizedBox(width: 6),
              Flexible(
                child: Text(label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.poppins(
                        fontSize: 12,
                        fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                        color: selected ? AppColors.secondary : AppColors.textSecondary)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
