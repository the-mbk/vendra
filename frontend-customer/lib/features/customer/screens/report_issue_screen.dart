// ══════════════════════════════════════════════════════════════
// Vendra Customer App - Report an Issue (FR08)
// Two steps, as in the Stitch dispute mockup:
//   1. What went wrong? (issue type)
//   2. Describe it (≥ 10 chars) + up to 4 evidence photos
// Submitting freezes the order's escrow until an admin decides.
// ══════════════════════════════════════════════════════════════

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:vendra_customer/vendra_core.dart';

import '../bloc/dispute_bloc.dart';
import '../bloc/order_bloc.dart';

class ReportIssueScreen extends StatelessWidget {
  final OrderModel order;
  const ReportIssueScreen({super.key, required this.order});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => ReportIssueBloc(),
      child: _ReportIssueView(order: order),
    );
  }
}

class _ReportIssueView extends StatefulWidget {
  final OrderModel order;
  const _ReportIssueView({required this.order});

  @override
  State<_ReportIssueView> createState() => _ReportIssueViewState();
}

class _ReportIssueViewState extends State<_ReportIssueView> {
  static const _minDescription = 10;

  final _descriptionController = TextEditingController();
  final _picker = ImagePicker();
  final List<EvidencePhoto> _photos = [];

  int _step = 0;
  String? _issueType;

  /// Customers can't raise "problem with the customer"
  static final Map<String, String> _issueTypes = Map.fromEntries(
    DisputeModel.issueTypes.entries.where((e) => e.key != 'customer_issue'),
  );

  static const Map<String, IconData> _issueIcons = {
    'item_not_received': Icons.inventory_2_outlined,
    'damaged_item': Icons.broken_image_outlined,
    'wrong_item': Icons.swap_horiz,
    'missing_items': Icons.remove_shopping_cart_outlined,
    'quality_issue': Icons.thumb_down_alt_outlined,
    'rider_issue': Icons.delivery_dining_outlined,
    'other': Icons.help_outline,
  };

  @override
  void dispose() {
    _descriptionController.dispose();
    super.dispose();
  }

  bool get _cameraAvailable =>
      !kIsWeb && _picker.supportsImageSource(ImageSource.camera);

  Future<void> _addPhotos(ImageSource source) async {
    final remaining = EvidencePhoto.maxCount - _photos.length;
    if (remaining <= 0) return;
    try {
      final List<XFile> picked;
      if (source == ImageSource.camera) {
        final shot = await _picker.pickImage(source: ImageSource.camera, imageQuality: 80, maxWidth: 1920);
        picked = shot == null ? const [] : [shot];
      } else {
        // Gallery on mobile, file chooser on web/desktop
        picked = await _picker.pickMultiImage(imageQuality: 80, maxWidth: 1920, limit: remaining > 1 ? remaining : null);
      }

      var skippedLarge = 0;
      final added = <EvidencePhoto>[];
      for (final file in picked.take(remaining)) {
        final bytes = await file.readAsBytes();
        if (bytes.length > EvidencePhoto.maxBytes) {
          skippedLarge++;
          continue;
        }
        added.add(EvidencePhoto(
          name: file.name.isNotEmpty ? file.name : 'evidence_${DateTime.now().millisecondsSinceEpoch}.jpg',
          bytes: bytes,
          mimeType: EvidencePhoto.mimeFor(file.name, file.mimeType),
        ));
      }
      if (!mounted) return;
      setState(() => _photos.addAll(added));
      if (skippedLarge > 0 || picked.length > remaining) {
        _snack(skippedLarge > 0
            ? '$skippedLarge photo(s) skipped — each must be under 5 MB.'
            : 'Only ${EvidencePhoto.maxCount} photos can be attached.');
      }
    } catch (e) {
      if (mounted) _snack('Could not open photos: $e', error: true);
    }
  }

  void _choosePhotoSource() {
    if (!_cameraAvailable) {
      _addPhotos(ImageSource.gallery);
      return;
    }
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Take a photo'),
              onTap: () {
                Navigator.pop(ctx);
                _addPhotos(ImageSource.camera);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Choose from gallery'),
              onTap: () {
                Navigator.pop(ctx);
                _addPhotos(ImageSource.gallery);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _snack(String message, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message),
      backgroundColor: error ? AppColors.error : null,
      behavior: SnackBarBehavior.floating,
    ));
  }

  void _submit() {
    final text = _descriptionController.text.trim();
    if (text.length < _minDescription) {
      _snack('Please describe the problem in at least $_minDescription characters.', error: true);
      return;
    }
    context.read<ReportIssueBloc>().add(SubmitDisputeRequested(
          orderId: widget.order.id,
          issueType: _issueType!,
          description: text,
          photos: List.of(_photos),
        ));
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<ReportIssueBloc, ReportIssueState>(
      listener: (context, state) {
        if (state is ReportIssueSuccess) {
          context.read<OrderBloc>().add(const FetchCustomerOrders(silent: true));
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(state.message),
            backgroundColor: AppColors.stockGreen,
            behavior: SnackBarBehavior.floating,
          ));
          Navigator.pop(context, true);
        } else if (state is ReportIssueFailure) {
          _snack(state.message, error: true);
        }
      },
      builder: (context, state) {
        final submitting = state is ReportIssueSubmitting;
        return PopScope(
          canPop: _step == 0 && !submitting,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop && _step == 1 && !submitting) setState(() => _step = 0);
          },
          child: Scaffold(
            backgroundColor: AppColors.background,
            appBar: AppBar(
              title: Text('Report an Issue', style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
              centerTitle: true,
            ),
            body: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _escrowBanner(),
                const SizedBox(height: 16),
                Text('Order details', style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                _orderCard(),
                const SizedBox(height: 20),
                _stepHeader(),
                const SizedBox(height: 16),
                if (_step == 0) _issueTypeStep() else _detailsStep(),
              ],
            ),
            bottomNavigationBar: SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: _step == 0
                    ? VendraButton(
                        text: 'Continue',
                        icon: Icons.arrow_forward,
                        onPressed: _issueType == null ? null : () => setState(() => _step = 1),
                      )
                    : Row(
                        children: [
                          Expanded(
                            flex: 2,
                            child: VendraButton(
                              text: 'Back',
                              isOutlined: true,
                              onPressed: submitting ? null : () => setState(() => _step = 0),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            flex: 3,
                            child: VendraButton(
                              text: 'Submit',
                              icon: Icons.send_outlined,
                              isLoading: submitting,
                              onPressed: _submit,
                            ),
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

  Widget _escrowBanner() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFEBF0FA),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.secondary.withValues(alpha: 0.15)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const CircleAvatar(
            radius: 20,
            backgroundColor: AppColors.stockGreen,
            child: Icon(Icons.shield_outlined, color: Colors.white, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Payment securely held',
                    style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.secondary)),
                const SizedBox(height: 2),
                Text(
                  'Your Rs. ${widget.order.totalAmount.toStringAsFixed(0)} stays frozen in escrow until an admin resolves this dispute.',
                  style: GoogleFonts.poppins(fontSize: 12, color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _orderCard() {
    final order = widget.order;
    final first = order.items.isNotEmpty ? order.items.first : null;
    final more = order.items.length - 1;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(color: const Color(0xFFF5F0E8), borderRadius: BorderRadius.circular(10)),
            child: Icon(Icons.shopping_bag_outlined, color: Colors.grey.shade500),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(order.storeName ?? 'Store', style: GoogleFonts.poppins(fontSize: 11, color: AppColors.textSecondary)),
                Text(
                  first?.productName ?? 'Order items',
                  style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w600),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  [
                    if (first != null) 'Qty: ${first.quantity}',
                    if (more > 0) '+$more more',
                    'Order #VDR-${order.id.toString().padLeft(5, '0')}',
                  ].join(' • '),
                  style: GoogleFonts.poppins(fontSize: 12, color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _stepHeader() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Step ${_step + 1} of 2',
                style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.secondary)),
            Text(_step == 0 ? 'Issue type' : 'Issue details',
                style: GoogleFonts.poppins(fontSize: 12, color: AppColors.textSecondary)),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: (_step + 1) / 2,
            minHeight: 6,
            backgroundColor: AppColors.secondary.withValues(alpha: 0.1),
            valueColor: const AlwaysStoppedAnimation(AppColors.secondary),
          ),
        ),
      ],
    );
  }

  Widget _issueTypeStep() {
    final entries = _issueTypes.entries.toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('What went wrong?', style: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w600)),
        const SizedBox(height: 10),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: entries.length,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: 1.45,
          ),
          itemBuilder: (context, i) {
            final e = entries[i];
            final selected = _issueType == e.key;
            return InkWell(
              onTap: () => setState(() => _issueType = e.key),
              borderRadius: BorderRadius.circular(12),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: selected ? AppColors.secondary.withValues(alpha: 0.08) : Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: selected ? AppColors.secondary : Colors.grey.shade300,
                    width: selected ? 2 : 1,
                  ),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(_issueIcons[e.key] ?? Icons.help_outline,
                        color: selected ? AppColors.secondary : AppColors.textSecondary),
                    const SizedBox(height: 8),
                    Text(
                      e.value,
                      textAlign: TextAlign.center,
                      style: GoogleFonts.poppins(
                        fontSize: 12,
                        fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                        color: selected ? AppColors.secondary : AppColors.textPrimary,
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _detailsStep() {
    final length = _descriptionController.text.trim().length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: AppColors.secondary.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(_issueIcons[_issueType] ?? Icons.help_outline, size: 16, color: AppColors.secondary),
              const SizedBox(width: 6),
              Text(_issueTypes[_issueType] ?? '',
                  style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.secondary)),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Text('Describe the issue', style: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        TextField(
          controller: _descriptionController,
          onChanged: (_) => setState(() {}),
          maxLines: 5,
          maxLength: 1000,
          style: GoogleFonts.poppins(fontSize: 13),
          decoration: InputDecoration(
            hintText: 'E.g. I ordered the 128 GB model but received the 64 GB one…',
            filled: true,
            fillColor: Colors.white,
            helperText: length < _minDescription ? 'At least $_minDescription characters ($length so far)' : null,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
        const SizedBox(height: 12),
        Text('Attach evidence (optional, up to ${EvidencePhoto.maxCount})',
            style: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        Text('Photos of the item, packaging or label help the admin decide faster.',
            style: GoogleFonts.poppins(fontSize: 12, color: AppColors.textSecondary)),
        const SizedBox(height: 10),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            if (_photos.length < EvidencePhoto.maxCount) _addPhotoTile(),
            for (var i = 0; i < _photos.length; i++) _photoTile(i),
          ],
        ),
      ],
    );
  }

  Widget _addPhotoTile() {
    return InkWell(
      onTap: _choosePhotoSource,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: 80,
        height: 80,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.shade400),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.add_a_photo_outlined, color: AppColors.textSecondary),
            const SizedBox(height: 4),
            Text('Add photo', style: GoogleFonts.poppins(fontSize: 10, color: AppColors.textSecondary)),
          ],
        ),
      ),
    );
  }

  Widget _photoTile(int index) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Image.memory(_photos[index].bytes, width: 80, height: 80, fit: BoxFit.cover),
        ),
        Positioned(
          top: -8,
          right: -8,
          child: GestureDetector(
            onTap: () => setState(() => _photos.removeAt(index)),
            child: const CircleAvatar(
              radius: 12,
              backgroundColor: AppColors.error,
              child: Icon(Icons.close, size: 14, color: Colors.white),
            ),
          ),
        ),
      ],
    );
  }
}
