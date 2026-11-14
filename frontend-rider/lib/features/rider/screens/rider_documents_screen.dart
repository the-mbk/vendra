// ══════════════════════════════════════════════════════════════
// Vendra Rider App - Update documents
// CNIC, vehicle, licence and registration (PUT /api/rider/documents).
// A rejected rider goes back into the review queue; an approved rider
// who changes anything is reviewed again and taken offline, so they are
// warned first (openRiderDocuments).
// ══════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:vendra_rider/vendra_core.dart';

import '../bloc/rider_home_bloc.dart';
import '../models/rider_documents_rules.dart';
import '../widgets/rider_documents_fields.dart';

/// Opens the form (needs a RiderHomeBloc above [context]). An approved
/// rider confirms first, since saving changes sends them back for review.
Future<void> openRiderDocuments(BuildContext context) async {
  final bloc = context.read<RiderHomeBloc>();
  final state = bloc.state;
  if (state.activeOrderId != null) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(
        content: Text('Finish your active delivery before changing your documents.'),
        backgroundColor: AppColors.error,
        behavior: SnackBarBehavior.floating,
      ));
    return;
  }
  if (state.isApproved) {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Edit documents?', style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
        content: Text(
          'You are approved to deliver. If you change your documents an admin must review them again: '
          'you will go offline and cannot take deliveries until they are approved.',
          style: GoogleFonts.poppins(fontSize: 13, color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Edit anyway')),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
  }
  await Navigator.of(context).push(MaterialPageRoute<void>(
    builder: (_) => BlocProvider<RiderHomeBloc>.value(value: bloc, child: const RiderDocumentsScreen()),
  ));
}

class RiderDocumentsScreen extends StatefulWidget {
  const RiderDocumentsScreen({super.key});

  @override
  State<RiderDocumentsScreen> createState() => _RiderDocumentsScreenState();
}

class _RiderDocumentsScreenState extends State<RiderDocumentsScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _cnic;
  late final TextEditingController _licence;
  late final TextEditingController _vehicleNumber;
  late String _vehicleType;
  late final int _savedNonce;

  /// The bloc keeps the last error; only show one from this screen's own submit
  bool _submitted = false;

  @override
  void initState() {
    super.initState();
    final state = context.read<RiderHomeBloc>().state;
    final docs = state.documents;
    _cnic = TextEditingController(text: formatCnic(docs.cnic ?? ''));
    _licence = TextEditingController(text: docs.licenseNumber ?? '');
    _vehicleNumber = TextEditingController(text: docs.vehicleNumber ?? '');
    final type = state.vehicleType;
    _vehicleType = type == null || type == 'motorbike' ? 'motorcycle' : type;
    _savedNonce = state.documentsSavedNonce;
  }

  @override
  void dispose() {
    _cnic.dispose();
    _licence.dispose();
    _vehicleNumber.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    final motorised = vehicleNeedsLicence(_vehicleType);
    setState(() => _submitted = true);
    context.read<RiderHomeBloc>().add(RiderDocumentsSubmitted(
          cnic: formatCnic(_cnic.text),
          vehicleType: _vehicleType,
          licenseNumber: motorised ? normalizeDocumentCode(_licence.text) : null,
          vehicleNumber: motorised ? normalizeDocumentCode(_vehicleNumber.text) : null,
        ));
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<RiderHomeBloc, RiderHomeState>(
      listenWhen: (a, b) => a.documentsSavedNonce != b.documentsSavedNonce,
      listener: (context, state) {
        // Saved: Home shows the server's message and the new status
        if (state.documentsSavedNonce != _savedNonce) Navigator.of(context).pop();
      },
      builder: (context, state) {
        final saving = state.savingDocuments;
        return Scaffold(
          backgroundColor: AppColors.background,
          appBar: AppBar(title: const Text('Rider documents')),
          body: SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _StatusNote(state: state),
                    const SizedBox(height: 12),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(18),
                        child: RiderDocumentsFields(
                          cnicController: _cnic,
                          licenceController: _licence,
                          vehicleNumberController: _vehicleNumber,
                          vehicleType: _vehicleType,
                          enabled: !saving,
                          onVehicleChanged: (v) => setState(() => _vehicleType = v),
                        ),
                      ),
                    ),
                    if (_submitted && state.documentsError != null) ...[
                      const SizedBox(height: 12),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.error_outline, size: 18, color: AppColors.error),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(state.documentsError!,
                                style: GoogleFonts.poppins(fontSize: 13, color: AppColors.error)),
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 20),
                    VendraButton(
                      text: state.isApproved ? 'Save and send for review' : 'Send for review',
                      icon: Icons.send,
                      isLoading: saving,
                      onPressed: _submit,
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _StatusNote extends StatelessWidget {
  final RiderHomeState state;
  const _StatusNote({required this.state});

  @override
  Widget build(BuildContext context) {
    final (IconData icon, Color color, String text) = switch (state.approvalStatus) {
      'rejected' => (
          Icons.assignment_late_outlined,
          AppColors.error,
          'Not approved${state.rejectionReason != null ? ': ${state.rejectionReason}' : ''}. '
              'Correct your documents and send them again.'
        ),
      'pending' => (
          Icons.hourglass_top_rounded,
          AppColors.reservedAmber,
          'Under review. Sending changes keeps you in the queue with the new details.'
        ),
      _ => (
          Icons.warning_amber_rounded,
          AppColors.reservedAmber,
          'Changing your documents sends them for review again. You will be offline until an admin approves them.'
        ),
    };
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text, style: GoogleFonts.poppins(fontSize: 13, height: 1.4, color: AppColors.textPrimary)),
          ),
        ],
      ),
    );
  }
}
