// ══════════════════════════════════════════════════════════════
// Vendra App - Add/Edit Product Screen
// Form for vendor to create or update products
// ══════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../config/app_theme.dart';
import '../../../core/models/product_model.dart';
import '../../../core/widgets/vendra_button.dart';
import '../../../core/widgets/vendra_text_field.dart';
import '../bloc/vendor_product_bloc.dart';

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

  bool get isEditing => widget.product != null;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.product?.name ?? '');
    _descCtrl = TextEditingController(text: widget.product?.description ?? '');
    _priceCtrl = TextEditingController(text: widget.product?.price.toStringAsFixed(0) ?? '');
    _stockCtrl = TextEditingController(text: widget.product?.privateStock.toString() ?? '');
    _bufferCtrl = TextEditingController(text: widget.product?.buffer.toString() ?? '5');
    _barcodeCtrl = TextEditingController(text: widget.product?.barcode ?? '');
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

  void _submit() {
    if (!_formKey.currentState!.validate()) return;

    if (isEditing) {
      context.read<VendorProductBloc>().add(UpdateVendorProduct(
            id: widget.product!.id,
            name: _nameCtrl.text,
            description: _descCtrl.text,
            price: double.parse(_priceCtrl.text),
            privateStock: int.parse(_stockCtrl.text),
            buffer: int.parse(_bufferCtrl.text),
            barcode: _barcodeCtrl.text.isEmpty ? null : _barcodeCtrl.text,
          ));
    } else {
      context.read<VendorProductBloc>().add(AddVendorProduct(
            name: _nameCtrl.text,
            description: _descCtrl.text.isEmpty ? null : _descCtrl.text,
            price: double.parse(_priceCtrl.text),
            privateStock: int.parse(_stockCtrl.text),
            buffer: int.parse(_bufferCtrl.text),
            barcode: _barcodeCtrl.text.isEmpty ? null : _barcodeCtrl.text,
          ));
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<VendorProductBloc, VendorProductState>(
      listener: (context, state) {
        if (state is VendorProductActionSuccess) {
          Navigator.pop(context);
        } else if (state is VendorProductError) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(state.message), backgroundColor: AppColors.error, behavior: SnackBarBehavior.floating),
          );
        }
      },
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          title: Text(isEditing ? 'Edit Product' : 'Add Product',
              style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
          actions: [
            if (isEditing)
              IconButton(
                icon: const Icon(Icons.delete_outline, color: AppColors.stockRed),
                onPressed: () {
                  showDialog(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: const Text('Delete Product?'),
                      content: const Text('This action cannot be undone.'),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
                        TextButton(
                          onPressed: () {
                            context.read<VendorProductBloc>().add(DeleteVendorProduct(id: widget.product!.id));
                            Navigator.pop(ctx);
                            Navigator.pop(context);
                          },
                          child: const Text('Delete', style: TextStyle(color: AppColors.stockRed)),
                        ),
                      ],
                    ),
                  );
                },
              ),
          ],
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                VendraTextField(
                  label: 'Product Name',
                  hint: 'e.g., Premium Basmati Rice 5kg',
                  controller: _nameCtrl,
                  prefixIcon: Icons.inventory_2_outlined,
                  validator: (v) => (v == null || v.isEmpty) ? 'Required' : null,
                ),
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
                  keyboardType: TextInputType.number,
                  prefixIcon: Icons.attach_money,
                  validator: (v) {
                    if (v == null || v.isEmpty) return 'Required';
                    if (double.tryParse(v) == null) return 'Enter a valid price';
                    return null;
                  },
                ),
                const SizedBox(height: 16),

                // Stock & Buffer side by side
                Row(
                  children: [
                    Expanded(
                      child: VendraTextField(
                        label: 'Private Stock',
                        hint: 'Total units',
                        controller: _stockCtrl,
                        keyboardType: TextInputType.number,
                        prefixIcon: Icons.warehouse_outlined,
                        validator: (v) {
                          if (v == null || v.isEmpty) return 'Required';
                          if (int.tryParse(v) == null) return 'Invalid';
                          return null;
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: VendraTextField(
                        label: 'Buffer',
                        hint: 'Safety margin',
                        controller: _bufferCtrl,
                        keyboardType: TextInputType.number,
                        prefixIcon: Icons.shield_outlined,
                        validator: (v) {
                          if (v == null || v.isEmpty) return 'Required';
                          if (int.tryParse(v) == null) return 'Invalid';
                          return null;
                        },
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 8),

                // Public stock preview
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.secondary.withOpacity(0.05),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.info_outline, size: 18, color: AppColors.secondary),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Public Stock = Private Stock − Buffer − Reserved',
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
                  prefixIcon: Icons.qr_code_2,
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.qr_code_scanner, color: AppColors.secondary),
                    onPressed: () {
                      // Barcode scanner placeholder
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Barcode scanner — Coming Soon'), behavior: SnackBarBehavior.floating),
                      );
                    },
                  ),
                ),

                const SizedBox(height: 32),

                BlocBuilder<VendorProductBloc, VendorProductState>(
                  builder: (context, state) {
                    return VendraButton(
                      text: isEditing ? 'Update Product' : 'Add Product',
                      icon: isEditing ? Icons.check : Icons.add,
                      isLoading: state is VendorProductLoading,
                      onPressed: _submit,
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
