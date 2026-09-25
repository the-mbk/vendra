// ══════════════════════════════════════════════════════════════
// Vendra Customer App - My Disputes (FR08)
// GET /api/disputes/mine — status, outcome, admin note and evidence
// ══════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:vendra_customer/vendra_core.dart';

import '../../../config/app_routes.dart';
import '../bloc/dispute_bloc.dart';
import '../widgets/order_status_widgets.dart';

class MyDisputesScreen extends StatelessWidget {
  const MyDisputesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => MyDisputesBloc()..add(const FetchMyDisputes()),
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(title: Text('My Disputes', style: GoogleFonts.poppins(fontWeight: FontWeight.w600))),
        body: BlocBuilder<MyDisputesBloc, MyDisputesState>(
          builder: (context, state) {
            if (state.loading && state.disputes.isEmpty) {
              return const Center(child: CircularProgressIndicator(color: AppColors.primary));
            }
            if (state.error != null && state.disputes.isEmpty) {
              return _message(
                context,
                icon: Icons.error_outline,
                text: state.error!,
                action: TextButton(
                  onPressed: () => context.read<MyDisputesBloc>().add(const FetchMyDisputes()),
                  child: const Text('Retry'),
                ),
              );
            }
            if (state.disputes.isEmpty) {
              return _message(
                context,
                icon: Icons.gavel_outlined,
                text: 'No disputes yet.\nIf an order has a problem, open it and tap "Report an issue".',
              );
            }
            return RefreshIndicator(
              color: AppColors.primary,
              onRefresh: () async => context.read<MyDisputesBloc>().add(const FetchMyDisputes(silent: true)),
              child: ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: state.disputes.length,
                separatorBuilder: (_, __) => const SizedBox(height: 12),
                itemBuilder: (context, i) => _DisputeCard(dispute: state.disputes[i]),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _message(BuildContext context, {required IconData icon, required String text, Widget? action}) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 56, color: Colors.grey.shade300),
            const SizedBox(height: 12),
            Text(text, textAlign: TextAlign.center, style: GoogleFonts.poppins(color: AppColors.textSecondary)),
            if (action != null) action,
          ],
        ),
      ),
    );
  }
}

class _DisputeCard extends StatelessWidget {
  final DisputeModel dispute;
  const _DisputeCard({required this.dispute});

  Color get _color {
    if (dispute.status == 'open') return AppColors.reservedAmber;
    return dispute.resolution == 'refund' ? AppColors.secondary : Colors.teal.shade700;
  }

  String get _outcome {
    // Refunds always go back to the customer's wallet
    if (dispute.status == 'resolved' && dispute.resolution == 'refund') return 'Resolved — refunded to your wallet';
    return dispute.outcomeText;
  }

  @override
  Widget build(BuildContext context) {
    final dateFmt = DateFormat('d MMM yyyy, h:mm a');
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Order #VDR-${dispute.orderId.toString().padLeft(5, '0')}',
                  style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w600),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: _color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  dispute.status == 'open' ? 'Open' : 'Resolved',
                  style: GoogleFonts.poppins(fontSize: 11, fontWeight: FontWeight.w600, color: _color),
                ),
              ),
            ],
          ),
          if (dispute.storeName != null)
            Text(dispute.storeName!, style: GoogleFonts.poppins(fontSize: 12, color: AppColors.textSecondary)),
          const SizedBox(height: 10),
          Row(
            children: [
              const Icon(Icons.report_problem_outlined, size: 16, color: AppColors.textSecondary),
              const SizedBox(width: 6),
              Expanded(
                child: Text(dispute.issueLabel, style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w500)),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(dispute.description, style: GoogleFonts.poppins(fontSize: 12, color: AppColors.textPrimary)),
          if (dispute.evidenceUrls.isNotEmpty) ...[
            const SizedBox(height: 10),
            SizedBox(
              height: 64,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: dispute.evidenceUrls.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (context, i) {
                  final url = ApiConfig.fileUrl(dispute.evidenceUrls[i]);
                  return GestureDetector(
                    onTap: () => _openPhoto(context, url),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: Image.network(
                        url,
                        width: 64,
                        height: 64,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Container(
                          width: 64,
                          height: 64,
                          color: Colors.grey.shade200,
                          child: const Icon(Icons.broken_image_outlined, color: AppColors.textLight),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: _color.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_outcome, style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w600, color: _color)),
                if (dispute.status == 'open' && dispute.heldAmount > 0)
                  Text('Rs. ${dispute.heldAmount.toStringAsFixed(0)} frozen in escrow',
                      style: GoogleFonts.poppins(fontSize: 11, color: AppColors.textSecondary)),
                if (dispute.adminNote != null && dispute.adminNote!.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text('Admin note: ${dispute.adminNote}',
                        style: GoogleFonts.poppins(fontSize: 11, color: AppColors.textPrimary)),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Text(
                  [
                    if (dispute.createdAt != null) 'Opened ${dateFmt.format(dispute.createdAt!)}',
                    if (dispute.resolvedAt != null) 'Resolved ${dateFmt.format(dispute.resolvedAt!)}',
                  ].join(' · '),
                  style: GoogleFonts.poppins(fontSize: 10, color: AppColors.textLight),
                ),
              ),
              TextButton(
                onPressed: () => Navigator.pushNamed(context, AppRoutes.orderTracking, arguments: dispute.orderId),
                child: const Text('View order'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _openPhoto(BuildContext context, String url) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        insetPadding: const EdgeInsets.all(16),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          children: [
            InteractiveViewer(child: Image.network(url, fit: BoxFit.contain)),
            Positioned(
              top: 4,
              right: 4,
              child: IconButton.filled(
                onPressed: () => Navigator.pop(ctx),
                icon: const Icon(Icons.close),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
