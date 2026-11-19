// ══════════════════════════════════════════════════════════════
// Vendra Customer App - Note for the rider (delivery orders)
// "Gate code 402", "Leave it with the guard": sent with the order and
// shown only to the rider who accepts it. Chips add the usual notes.
// ══════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:vendra_customer/vendra_core.dart';

const riderNoteMaxLength = 200;

const riderNoteSuggestions = [
  'Leave it at the door',
  'Please don\'t ring the bell',
  'Hand it to the guard',
  'Call out at the gate',
];

/// [current] with [suggestion] added as its own sentence (unchanged if already there)
String addRiderNote(String current, String suggestion) {
  final text = current.trim();
  if (text.toLowerCase().contains(suggestion.toLowerCase())) return text;
  if (text.isEmpty) return suggestion;
  final joined = '${text.endsWith('.') ? text : '$text.'} $suggestion';
  return joined.length <= riderNoteMaxLength ? joined : text;
}

class RiderNoteField extends StatelessWidget {
  final TextEditingController controller;
  const RiderNoteField({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Note for the rider (optional)',
              style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
          const SizedBox(height: 2),
          Text('Only the rider who takes your order sees it.',
              style: GoogleFonts.poppins(fontSize: 12, color: AppColors.textSecondary)),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              for (final s in riderNoteSuggestions)
                ActionChip(
                  label: Text(s),
                  onPressed: () {
                    final next = addRiderNote(controller.text, s);
                    controller.value = TextEditingValue(text: next, selection: TextSelection.collapsed(offset: next.length));
                  },
                ),
            ],
          ),
          const SizedBox(height: 10),
          TextField(
            controller: controller,
            maxLength: riderNoteMaxLength,
            minLines: 1,
            maxLines: 3,
            decoration: const InputDecoration(hintText: 'e.g. Gate code 402, second floor'),
          ),
        ],
      ),
    );
  }
}
