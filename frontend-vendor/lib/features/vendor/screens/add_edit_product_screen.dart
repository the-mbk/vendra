// ══════════════════════════════════════════════════════════════
// Vendra App - Add/Edit Product Screen (FR06 / FR01)
// Form for vendor to create or update products: category (from
// GET /api/categories), camera barcode scan, and an optional buffer
// (empty = platform default from GET /api/public-config), and a photo
// (gallery everywhere, camera where supported) that is uploaded right
// after the product is saved — or removed on save.
// New products wait for admin approval before customers can see them.
// ══════════════════════════════════════════════════════════════

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:vendra_vendor/vendra_core.dart';
import '../bloc/vendor_product_bloc.dart';
import '../models/product_photo.dart';
import 'barcode_scanner_screen.dart';

class AddEditProductScreen extends StatefulWidget {
  final ProductModel? product; // null = add, non-null = edit

  const AddEditProductScreen({super.key, this.product});

  @override
  State<AddEditProductScreen> createState() => _AddEditProductScreenState();
}

class _AddEditProductScreenState extends State<AddEditProductScreen> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nameCtrl;
  late TextEditingController _descCtrl;
  late TextEditingController _priceCtrl;
  late TextEditingController _stockCtrl;
  late TextEditingController _bufferCtrl;
  late TextEditingController _barcodeCtrl;

  List<CategoryModel> _categories = [];
  int? _categoryId;
  int? _defaultBuffer; // platform policy, from /api/public-config
  String? _stockError; // server-side BELOW_RESERVED message

  final _picker = ImagePicker();
  ProductPhoto? _photo; // picked, uploaded on save
  bool _removePhoto = false; // delete the saved photo on save

  bool get isEditing => widget.product != null;

  @override
  void initState() {
    super.initState();
    final p = widget.product;
    _nameCtrl = TextEditingController(text: p?.name ?? '');
    _descCtrl = TextEditingController(text: p?.description ?? '');
    _priceCtrl = TextEditingController(text: p?.price.toStringAsFixed(0) ?? '');
    _stockCtrl = TextEditingController(text: p?.privateStock.toString() ?? '');
    _bufferCtrl = TextEditingController(text: p?.buffer.toString() ?? '');
    _barcodeCtrl = TextEditingController(text: p?.barcode ?? '');
    _categoryId = p?.categoryId;
    _loadLookups();
  }

  Future<void> _loadLookups() async {
    final api = ApiService();
    try {
      final res = await api.get(ApiConfig.categories);
      final list = (res.data['data'] as List<dynamic>)
          .map((c) => CategoryModel.fromJson(Map<String, dynamic>.from(c)))
          .toList();
      if (mounted) setState(() => _categories = list);
    } catch (_) {}
    try {
      final res = await api.get(ApiConfig.publicConfig);
      final value = toIntOrNull((res.data['data'] as Map)['defaultBuffer']);
      if (mounted) setState(() => _defaultBuffer = value);
    } catch (_) {}
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _descCtrl.dispose();
    _priceCtrl.dispose();
    _stockCtrl.dispose();
    _bufferCtrl.dispose();
    _barcodeCtrl.dispose();
    super.dispose();
  }

  bool get _cameraAvailable => !kIsWeb && _picker.supportsImageSource(ImageSource.camera);

  Future<void> _pickPhoto(ImageSource source) async {
    try {
      // Gallery on mobile, a file chooser on web / desktop
      final file = await _picker.pickImage(source: source, maxWidth: 1600, maxHeight: 1600, imageQuality: 85);
      if (file == null) return;
      final bytes = await file.readAsBytes();
      if (!mounted) return;
      if (bytes.length > ProductPhoto.maxBytes) {
        _snack('That photo is over 5 MB — please choose a smaller one.', error: true);
        return;
      }
      final name = file.name.isNotEmpty ? file.name : 'product_${DateTime.now().millisecondsSinceEpoch}.jpg';
      setState(() {
        _photo = ProductPhoto(name: name, bytes: bytes, mimeType: ProductPhoto.mimeFor(name, file.mimeType));
        _removePhoto = false;
      });
    } catch (e) {
      if (mounted) _snack('Could not open photos: $e', error: true);
    }
  }

  void _clearPhoto() {
    setState(() {
      if (_photo != null) {
        _photo = null; // drop the unsaved pick; a saved photo stays
      } else {
        _removePhoto = true;
      }
    });
  }

  void _snack(String message, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message),
      backgroundColor: error ? AppColors.error : null,
      behavior: SnackBarBehavior.floating,
    ));
  }

  Future<void> _scanBarcode() async {
    final code = await scanBarcode(context);
    if (code != null && mounted) setState(() => _barcodeCtrl.text = code);
  }

  void _submit() {
    setState(() => _stockError = null);
    if (!_formKey.currentState!.validate()) return;

    final bufferText = _bufferCtrl.text.trim();
    // Empty buffer → platform default (server applies it on create; on edit we send the policy value)
    final int? buffer = bufferText.isEmpty ? (isEditing ? _defaultBuffer : null) : int.parse(bufferText);
    final barcode = _barcodeCtrl.text.trim().isEmpty ? null : _barcodeCtrl.text.trim();

    if (isEditing) {
      context.read<VendorProductBloc>().add(UpdateVendorProduct(
            id: widget.product!.id,
            name: _nameCtrl.text.trim(),
            description: _descCtrl.text,
            price: double.parse(_priceCtrl.text),
            privateStock: int.parse(_stockCtrl.text),
            buffer: buffer,
            barcode: barcode,
            categoryId: _categoryId,
            photo: _photo,
            removePhoto: _removePhoto,
          ));
    } else {
      context.read<VendorProductBloc>().add(AddVendorProduct(
            name: _nameCtrl.text.trim(),
            description: _descCtrl.text.isEmpty ? null : _descCtrl.text,
            price: double.parse(_priceCtrl.text),
            privateStock: int.parse(_stockCtrl.text),
            buffer: buffer,
            barcode: barcode,
            categoryId: _categoryId,
            photo: _photo,
          ));
    }
  }

  void _confirmDelete(ProductModel live) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Product?'),
        content: Text(live.hasReservations
            ? '${live.reservedQuantity} unit(s) are reserved for open online orders, so the server will refuse '
                'until those orders are finished.'
            : 'This action cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              // Stay on this screen: on success the listener pops, on 409 it shows why
              context.read<VendorProductBloc>().add(DeleteVendorProduct(id: live.id));
            },
            child: const Text('Delete', style: TextStyle(color: AppColors.stockRed)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<VendorProductBloc, VendorProductState>(
      listener: (context, state) {
        if (state is VendorProductActionSuccess) {
          // Root messenger: the snackbar survives the pop
          final messenger = ScaffoldMessenger.of(context);
          if (state.photoError == null) {
            messenger.showSnackBar(
              SnackBar(content: Text(state.message), backgroundColor: AppColors.success, behavior: SnackBarBehavior.floating),
            );
          } else {
            // The product itself is saved — only the photo step failed
            messenger.showSnackBar(SnackBar(
              content: Text('Product saved, but the photo wasn\'t updated: ${state.photoError} '
                  'Open the product to try again.'),
              backgroundColor: AppColors.error,
              behavior: SnackBarBehavior.floating,
              duration: const Duration(seconds: 8),
            ));
          }
          Navigator.pop(context);
        } else if (state is VendorProductError) {
          if (state.code == 'BELOW_RESERVED') setState(() => _stockError = state.message);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(state.message), backgroundColor: AppColors.error, behavior: SnackBarBehavior.floating),
          );
        }
      },
      builder: (context, state) {
        final bloc = context.read<VendorProductBloc>();
        // Live copy of the product being edited (reserved units change as orders arrive)
        final live = isEditing ? (bloc.productById(widget.product!.id) ?? widget.product!) : null;

        return Scaffold(
          backgroundColor: AppColors.background,
          appBar: AppBar(
            title: Text(isEditing ? 'Edit Product' : 'Add Product', style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
            actions: [
              if (live != null)
                IconButton(
                  icon: const Icon(Icons.delete_outline, color: AppColors.stockRed),
                  onPressed: () => _confirmDelete(live),
                ),
            ],
          ),
          body: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (live != null && !live.isApproved) ...[
                        _approvalBanner(),
                        const SizedBox(height: 16),
                      ],
                      if (live != null) ...[
                        _liveStockCard(live),
                        const SizedBox(height: 16),
                      ],

                      _photoSection(live),
                      const SizedBox(height: 16),

                      VendraTextField(
                        label: 'Product Name',
                        hint: 'e.g., Premium Basmati Rice 5kg',
                        controller: _nameCtrl,
                        prefixIcon: Icons.inventory_2_outlined,
                        validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                      ),
                      const SizedBox(height: 16),

                      _categoryDropdown(),
                      const SizedBox(height: 16),

                      VendraTextField(
                        label: 'Description',
                        hint: 'Product description...',
                        controller: _descCtrl,
                        maxLines: 3,
                        prefixIcon: Icons.description_outlined,
                      ),
                      const SizedBox(height: 16),

                      VendraTextField(
                        label: 'Price (Rs.)',
                        hint: 'e.g., 1250',
                        controller: _priceCtrl,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        prefixIcon: Icons.payments_outlined,
                        validator: (v) {
                          if (v == null || v.isEmpty) return 'Required';
                          final price = double.tryParse(v);
                          if (price == null || price < 0) return 'Enter a valid price';
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),

                      // Stock & Buffer side by side
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: VendraTextField(
                              label: 'Private Stock',
                              hint: 'Units on hand',
                              controller: _stockCtrl,
                              keyboardType: TextInputType.number,
                              prefixIcon: Icons.warehouse_outlined,
                              validator: (v) {
                                if (v == null || v.isEmpty) return 'Required';
                                final n = int.tryParse(v);
                                if (n == null || n < 0) return 'Invalid';
                                return null;
                              },
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: VendraTextField(
                              label: 'Buffer (optional)',
                              hint: _defaultBuffer != null ? 'Default: $_defaultBuffer' : 'Platform default',
                              controller: _bufferCtrl,
                              keyboardType: TextInputType.number,
                              prefixIcon: Icons.shield_outlined,
                              validator: (v) {
                                if (v == null || v.trim().isEmpty) return null; // default
                                final n = int.tryParse(v.trim());
                                if (n == null || n < 0) return 'Invalid';
                                return null;
                              },
                            ),
                          ),
                        ],
                      ),
                      if (_stockError != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 6, left: 4),
                          child: Text(_stockError!,
                              style: GoogleFonts.poppins(fontSize: 12, color: AppColors.error, fontWeight: FontWeight.w500)),
                        ),

                      const SizedBox(height: 8),

                      // Stock formula + buffer hint
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppColors.secondary.withValues(alpha: 0.05),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(Icons.info_outline, size: 18, color: AppColors.secondary),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Public Stock = Private Stock − Buffer − Reserved.\n'
                                'The buffer is kept back for walk-in customers. Leave it empty to use the '
                                'platform default${_defaultBuffer != null ? ' ($_defaultBuffer units)' : ''}.',
                                style: GoogleFonts.poppins(fontSize: 12, color: AppColors.secondary),
                              ),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 16),

                      // Barcode
                      VendraTextField(
                        label: 'Barcode (Optional)',
                        hint: 'Scan or enter barcode',
                        controller: _barcodeCtrl,
                        keyboardType: TextInputType.number,
                        prefixIcon: Icons.qr_code_2,
                        suffixIcon: IconButton(
                          tooltip: 'Scan barcode',
                          icon: const Icon(Icons.qr_code_scanner, color: AppColors.secondary),
                          onPressed: _scanBarcode,
                        ),
                      ),

                      if (!isEditing) ...[
                        const SizedBox(height: 12),
                        Text(
                          'New products are reviewed by an admin before they appear in the marketplace. '
                          'You can still sell them at the counter right away.',
                          style: GoogleFonts.poppins(fontSize: 11, color: AppColors.textSecondary),
                        ),
                      ],

                      const SizedBox(height: 32),

                      VendraButton(
                        text: isEditing ? 'Update Product' : 'Add Product',
                        icon: isEditing ? Icons.check : Icons.add,
                        isLoading: state is VendorProductLoading,
                        onPressed: _submit,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _categoryDropdown() {
    // Keep the current category selectable even before the list has loaded
    final known = _categories.any((c) => c.id == _categoryId);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Category',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500, color: Colors.black87)),
        const SizedBox(height: 8),
        DropdownButtonFormField<int?>(
          key: ValueKey('cat-${_categories.length}'),
          initialValue: known ? _categoryId : null,
          isExpanded: true,
          decoration: const InputDecoration(prefixIcon: Icon(Icons.category_outlined, size: 20)),
          hint: Text(
            _categories.isEmpty
                ? (widget.product?.categoryName ?? 'Loading categories…')
                : 'Choose a category',
          ),
          items: [
            const DropdownMenuItem<int?>(value: null, child: Text('No category')),
            for (final c in _categories)
              DropdownMenuItem<int?>(
                value: c.id,
                child: Row(
                  children: [
                    Icon(c.iconData, size: 18, color: AppColors.secondary),
                    const SizedBox(width: 8),
                    Flexible(child: Text(c.name, overflow: TextOverflow.ellipsis)),
                  ],
                ),
              ),
          ],
          onChanged: (v) => setState(() => _categoryId = v),
        ),
      ],
    );
  }

  /// Current / picked photo with choose, take and remove actions
  Widget _photoSection(ProductModel? live) {
    final hasSaved = live?.imageUrl != null && live!.imageUrl!.isNotEmpty && !_removePhoto;
    Widget preview;
    if (_photo != null) {
      preview = Image.memory(
        _photo!.bytes,
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
        // e.g. HEIC can't be previewed everywhere — it still uploads
        errorBuilder: (_, __, ___) => _photoPlaceholder(Icons.image_outlined, _photo!.name),
      );
    } else if (hasSaved) {
      preview = ProductImage(product: live, iconSize: 36);
    } else {
      preview = _photoPlaceholder(Icons.add_a_photo_outlined, 'No photo');
    }

    String? note;
    if (_photo != null) {
      note = isEditing ? 'New photo — uploaded when you save.' : 'Uploaded when you add the product.';
    } else if (_removePhoto) {
      note = 'Photo will be removed when you save.';
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: SizedBox(width: 104, height: 104, child: preview),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Product photo', style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w600)),
                Text('JPEG, PNG, WebP or HEIC · up to 5 MB',
                    style: GoogleFonts.poppins(fontSize: 11, color: AppColors.textSecondary)),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 4,
                  children: [
                    TextButton.icon(
                      onPressed: () => _pickPhoto(ImageSource.gallery),
                      icon: const Icon(Icons.photo_library_outlined, size: 18),
                      label: Text(_photo != null || hasSaved ? 'Change' : 'Choose photo'),
                    ),
                    if (_cameraAvailable)
                      TextButton.icon(
                        onPressed: () => _pickPhoto(ImageSource.camera),
                        icon: const Icon(Icons.photo_camera_outlined, size: 18),
                        label: const Text('Take photo'),
                      ),
                    if (_photo != null || hasSaved)
                      TextButton.icon(
                        onPressed: _clearPhoto,
                        style: TextButton.styleFrom(foregroundColor: AppColors.stockRed),
                        icon: const Icon(Icons.delete_outline, size: 18),
                        label: const Text('Remove photo'),
                      ),
                    if (_removePhoto && _photo == null)
                      TextButton(
                        onPressed: () => setState(() => _removePhoto = false),
                        child: const Text('Undo'),
                      ),
                  ],
                ),
                if (note != null)
                  Text(note, style: GoogleFonts.poppins(fontSize: 11, color: AppColors.secondary)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _photoPlaceholder(IconData icon, String label) {
    return Container(
      color: AppColors.secondary.withValues(alpha: 0.06),
      alignment: Alignment.center,
      padding: const EdgeInsets.all(6),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 30, color: AppColors.secondary.withValues(alpha: 0.6)),
          const SizedBox(height: 4),
          Text(label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.poppins(fontSize: 10, color: AppColors.textSecondary)),
        ],
      ),
    );
  }

  Widget _approvalBanner() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.warning.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.warning),
      ),
      child: Row(
        children: [
          const Icon(Icons.hourglass_top, color: Color(0xFF8A6D00), size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Awaiting admin approval — customers can\'t see this product yet.',
              style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w600, color: const Color(0xFF8A6D00)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _liveStockCard(ProductModel p) {
    Widget cell(String label, int value, Color color) => Expanded(
          child: Column(
            children: [
              Text('$value', style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.w700, color: color)),
              Text(label, style: GoogleFonts.poppins(fontSize: 11, color: AppColors.textSecondary)),
            ],
          ),
        );
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
      child: Column(
        children: [
          Row(
            children: [
              cell('Private', p.privateStock, AppColors.secondary),
              cell('Buffer', p.buffer, Colors.blueGrey),
              cell('Reserved', p.reservedQuantity, AppColors.reservedAmber),
              cell('Public', p.publicStock, AppColors.stockGreen),
            ],
          ),
          if (p.hasReservations)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                '${p.reservedQuantity} unit(s) are reserved for online orders — private stock can\'t go below that.',
                textAlign: TextAlign.center,
                style: GoogleFonts.poppins(fontSize: 11, color: AppColors.reservedAmber),
              ),
            ),
        ],
      ),
    );
  }
}
