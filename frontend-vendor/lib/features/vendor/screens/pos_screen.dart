// ══════════════════════════════════════════════════════════════
// Vendra Vendor App - Walk-in POS Screen (FR01 / FR02)
// Adapted from the Stitch vendra_pos_screen_tablet design:
//   tablet / wide  → product list | current sale (two panes)
//   phone          → product list stacked over a compact sale bar; tapping
//                    the bar expands the sale to the full screen
//
// Every product shows Private / Reserved / Sellable. The numbers are
// live (VendorProductBloc patches them from `stock:vendor` socket
// events), so when a customer orders online the reserved units show up
// here within seconds and the cashier can't sell them.
// ══════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:vendra_vendor/vendra_core.dart';

import '../../auth/bloc/auth_bloc.dart';
import '../../auth/bloc/auth_state.dart' as auth_state;
import '../bloc/pos_bloc.dart';
import '../bloc/vendor_product_bloc.dart';
import '../models/pos_sale_model.dart';
import 'barcode_scanner_screen.dart';

final NumberFormat _money = NumberFormat('#,##0.##');
String _rs(double v) => 'Rs. ${_money.format(v)}';

class PosScreen extends StatefulWidget {
  const PosScreen({super.key});

  @override
  State<PosScreen> createState() => _PosScreenState();
}

class _PosScreenState extends State<PosScreen> {
  final _searchCtrl = TextEditingController();
  String _query = '';
  String? _category; // null = All
  bool _saleExpanded = false; // phone layout: sale pane fills the screen

  static const double _wideBreakpoint = 800;

  @override
  void initState() {
    super.initState();
    context.read<PosBloc>().add(PosStarted());
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _refreshStock() => context.read<VendorProductBloc>().add(const FetchVendorProducts(silent: true));

  /// Enter in the search box: a numeric code is treated as a barcode
  /// (this is also how USB/Bluetooth scanners "type" into the field)
  void _onSearchSubmitted(String text) {
    final value = text.trim();
    if (value.isEmpty) return;
    if (RegExp(r'^\d{4,}$').hasMatch(value)) {
      context.read<PosBloc>().add(PosBarcodeSubmitted(value));
      _clearSearch();
      return;
    }
    final matches = _filtered(context.read<VendorProductBloc>().products);
    if (matches.length == 1) {
      context.read<PosBloc>().add(PosAddProduct(matches.first));
      _clearSearch();
    }
  }

  void _clearSearch() {
    _searchCtrl.clear();
    setState(() => _query = '');
  }

  Future<void> _scan() async {
    final bloc = context.read<PosBloc>();
    final code = await scanBarcode(context);
    if (code != null) bloc.add(PosBarcodeSubmitted(code));
  }

  Future<void> _typeBarcode() async {
    final bloc = context.read<PosBloc>();
    final code = await enterBarcodeManually(context);
    if (code != null) bloc.add(PosBarcodeSubmitted(code));
  }

  List<ProductModel> _filtered(List<ProductModel> products) {
    final q = _query.toLowerCase();
    return products.where((p) {
      if (_category != null && (p.categoryName ?? 'Other') != _category) return false;
      if (q.isEmpty) return true;
      return p.name.toLowerCase().contains(q) || (p.barcode ?? '').contains(q);
    }).toList();
  }

  // ── Notices: 409 RESERVED_STOCK dialog, everything else as a snackbar ──
  void _onNotice(BuildContext context, PosNotice notice) {
    if (notice.code == 'RESERVED_STOCK') {
      _refreshStock();
      _showReservedDialog(context, notice);
      return;
    }
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(notice.message),
        backgroundColor: notice.isError ? AppColors.error : AppColors.success,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ));
  }

  void _showReservedDialog(BuildContext context, PosNotice notice) {
    final bloc = context.read<PosBloc>();
    final sellable = notice.sellable ?? 0;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        icon: const Icon(Icons.lock_outline, color: AppColors.reservedAmber, size: 36),
        title: Text('Reserved for online orders', style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Server message, e.g. Only 3 "X" can be sold — 2 are reserved for online orders.
            Text(notice.message, textAlign: TextAlign.center, style: GoogleFonts.poppins(fontSize: 14)),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _MiniStat(label: 'Sellable', value: '$sellable', color: AppColors.stockGreen),
                const SizedBox(width: 8),
                _MiniStat(label: 'Reserved', value: '${notice.reserved ?? 0}', color: AppColors.reservedAmber),
              ],
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK')),
          if (notice.productId != null)
            ElevatedButton(
              onPressed: () {
                bloc.add(PosSetQuantity(notice.productId!, sellable));
                Navigator.pop(ctx);
              },
              style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12)),
              child: Text(sellable > 0 ? 'Sell $sellable instead' : 'Remove item'),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MultiBlocListener(
      listeners: [
        BlocListener<PosBloc, PosState>(
          listenWhen: (a, b) => b.notice != null && a.notice?.id != b.notice?.id,
          listener: (context, state) => _onNotice(context, state.notice!),
        ),
        BlocListener<PosBloc, PosState>(
          listenWhen: (a, b) => b.receipt != null && a.receipt?.id != b.receipt?.id,
          listener: (context, state) {
            // Realtime usually beats us to it; this covers a dropped socket
            _refreshStock();
            setState(() => _saleExpanded = true);
          },
        ),
      ],
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildHeader(context),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  if (constraints.maxWidth >= _wideBreakpoint) {
                    final saleWidth = (constraints.maxWidth * 0.4).clamp(340.0, 460.0);
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(child: _buildProductPane(context)),
                        const VerticalDivider(width: 1),
                        SizedBox(width: saleWidth, child: const _SalePane(compact: false)),
                      ],
                    );
                  }
                  if (_saleExpanded) {
                    return _SalePane(compact: false, onToggle: () => setState(() => _saleExpanded = false));
                  }
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(child: _buildProductPane(context)),
                      _SalePane(compact: true, onToggle: () => setState(() => _saleExpanded = true)),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Header: title + today's walk-in totals ──
  Widget _buildHeader(BuildContext context) {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppColors.secondary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.point_of_sale, color: AppColors.secondary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: BlocBuilder<AuthBloc, auth_state.AuthState>(
              builder: (context, state) {
                final store = state is auth_state.Authenticated ? state.user.storeName ?? 'My Store' : 'My Store';
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Walk-in POS', style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.w600)),
                    Text(store,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.poppins(fontSize: 12, color: AppColors.textSecondary)),
                  ],
                );
              },
            ),
          ),
          BlocBuilder<PosBloc, PosState>(
            buildWhen: (a, b) => a.todayCount != b.todayCount || a.todayTotal != b.todayTotal,
            builder: (context, state) => InkWell(
              borderRadius: BorderRadius.circular(20),
              onTap: () => _showTodaySales(context),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.green.shade50,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.green.shade200),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text('Today · ${state.todayCount} sale${state.todayCount == 1 ? '' : 's'}',
                        style: GoogleFonts.poppins(fontSize: 11, color: Colors.green.shade800)),
                    Text(_rs(state.todayTotal),
                        style: GoogleFonts.poppins(
                            fontSize: 14, fontWeight: FontWeight.w700, color: Colors.green.shade800)),
                  ],
                ),
              ),
            ),
          ),
          IconButton(
            tooltip: "Today's walk-in sales",
            icon: const Icon(Icons.receipt_long_outlined),
            onPressed: () => _showTodaySales(context),
          ),
        ],
      ),
    );
  }

  void _showTodaySales(BuildContext context) {
    final bloc = context.read<PosBloc>()..add(PosLoadToday());
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => BlocProvider.value(value: bloc, child: const _TodaySalesSheet()),
    );
  }

  // ── Left / top pane: search, scan, category chips, products ──
  Widget _buildProductPane(BuildContext context) {
    return BlocBuilder<VendorProductBloc, VendorProductState>(
      builder: (context, productState) {
        final productBloc = context.read<VendorProductBloc>();
        final all = productBloc.products;
        final categories = all.map((p) => p.categoryName ?? 'Other').toSet().toList()..sort();
        final visible = _filtered(all);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: BlocBuilder<PosBloc, PosState>(
                buildWhen: (a, b) => a.isLookingUp != b.isLookingUp,
                builder: (context, pos) => TextField(
                  controller: _searchCtrl,
                  onChanged: (v) => setState(() => _query = v.trim()),
                  onSubmitted: _onSearchSubmitted,
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: Colors.white,
                    hintText: 'Search products or type a barcode + Enter',
                    prefixIcon: const Icon(Icons.search, size: 20),
                    suffixIcon: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (pos.isLookingUp)
                          const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 8),
                            child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                          ),
                        if (_query.isNotEmpty)
                          IconButton(icon: const Icon(Icons.close, size: 18), onPressed: _clearSearch),
                        IconButton(
                          tooltip: 'Type a barcode',
                          icon: const Icon(Icons.keyboard_outlined, color: AppColors.secondary),
                          onPressed: _typeBarcode,
                        ),
                        if (cameraScanSupported)
                          IconButton(
                            tooltip: 'Scan with camera',
                            icon: const Icon(Icons.qr_code_scanner, color: AppColors.secondary),
                            onPressed: _scan,
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            if (categories.length > 1)
              SizedBox(
                height: 44,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  children: [
                    _categoryChip('All', _category == null, () => setState(() => _category = null)),
                    for (final c in categories)
                      _categoryChip(c, _category == c, () => setState(() => _category = c)),
                  ],
                ),
              ),
            Expanded(child: _buildProductGrid(context, productBloc, productState, visible)),
          ],
        );
      },
    );
  }

  Widget _categoryChip(String label, bool selected, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.only(right: 8, bottom: 4),
      child: ChoiceChip(
        label: Text(label, style: GoogleFonts.poppins(fontSize: 12, color: selected ? Colors.white : AppColors.textPrimary)),
        selected: selected,
        onSelected: (_) => onTap(),
        selectedColor: AppColors.secondary,
        backgroundColor: Colors.white,
        showCheckmark: false,
        side: BorderSide(color: selected ? AppColors.secondary : Colors.grey.shade300),
      ),
    );
  }

  Widget _buildProductGrid(
    BuildContext context,
    VendorProductBloc productBloc,
    VendorProductState productState,
    List<ProductModel> visible,
  ) {
    if (!productBloc.hasLoaded) {
      if (productState is VendorProductError) {
        return Center(child: Text(productState.message, textAlign: TextAlign.center));
      }
      return const LoadingShimmer(isGrid: false, itemCount: 4);
    }
    if (visible.isEmpty) {
      return Center(
        child: Text(
          productBloc.products.isEmpty ? 'No products yet — add some from the Home tab.' : 'No products match.',
          style: GoogleFonts.poppins(color: AppColors.textSecondary),
        ),
      );
    }
    return BlocBuilder<PosBloc, PosState>(
      buildWhen: (a, b) => a.lines != b.lines,
      builder: (context, pos) => RefreshIndicator(
        onRefresh: () async => _refreshStock(),
        child: GridView.builder(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 260,
            mainAxisExtent: 160,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
          ),
          itemCount: visible.length,
          itemBuilder: (context, i) {
            final p = visible[i];
            return _PosProductTile(
              product: p,
              inSale: pos.quantityOf(p.id),
              onAdd: () => context.read<PosBloc>().add(PosAddProduct(p)),
            );
          },
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════
// Product tile: price + Private / Reserved / Sellable
// ══════════════════════════════════════════════════════════════
class _PosProductTile extends StatelessWidget {
  final ProductModel product;
  final int inSale;
  final VoidCallback onAdd;

  const _PosProductTile({required this.product, required this.inSale, required this.onAdd});

  @override
  Widget build(BuildContext context) {
    final sellable = product.sellableInStore;
    final soldOut = sellable <= 0;
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onAdd,
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: inSale > 0 ? AppColors.primary : Colors.grey.shade200,
              width: inSale > 0 ? 1.5 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 44,
                    height: 44,
                    child: ProductImage(product: product, iconSize: 20, borderRadius: BorderRadius.circular(8)),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      product.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w500, height: 1.3),
                    ),
                  ),
                  if (inSale > 0)
                    Container(
                      margin: const EdgeInsets.only(left: 6),
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(color: AppColors.primary, borderRadius: BorderRadius.circular(10)),
                      child: Text('×$inSale',
                          style: GoogleFonts.poppins(fontSize: 11, color: Colors.white, fontWeight: FontWeight.w600)),
                    ),
                ],
              ),
              const Spacer(),
              Row(
                children: [
                  Expanded(
                    child: Text(_rs(product.price),
                        style: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.primary)),
                  ),
                  Container(
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(
                      color: soldOut ? Colors.grey.shade400 : AppColors.secondary,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.add, color: Colors.white, size: 18),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  _StockPill(label: 'Private', value: product.privateStock, color: AppColors.secondary),
                  const SizedBox(width: 4),
                  _StockPill(label: 'Reserved', value: product.reservedQuantity, color: AppColors.reservedAmber),
                  const SizedBox(width: 4),
                  _StockPill(
                    label: 'Sellable',
                    value: sellable,
                    color: soldOut ? AppColors.stockRed : AppColors.stockGreen,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StockPill extends StatelessWidget {
  final String label;
  final int value;
  final Color color;
  const _StockPill({required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 3),
        decoration: BoxDecoration(color: color.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(6)),
        child: Column(
          children: [
            Text('$value', style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w700, color: color, height: 1.2)),
            Text(label, style: GoogleFonts.poppins(fontSize: 9, color: color, height: 1.2)),
          ],
        ),
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  const _MiniStat({required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
      child: Column(
        children: [
          Text(value, style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.w700, color: color)),
          Text(label, style: GoogleFonts.poppins(fontSize: 11, color: color)),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════
// Current sale pane (right pane on tablets, bottom panel on phones)
// ══════════════════════════════════════════════════════════════
class _SalePane extends StatelessWidget {
  /// Collapsed summary bar (phone): header + total + complete, no line list
  final bool compact;
  /// Phone only: expand / collapse between the bar and the full-screen sale
  final VoidCallback? onToggle;

  const _SalePane({required this.compact, this.onToggle});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<PosBloc, PosState>(
      builder: (context, pos) {
        final productBloc = context.watch<VendorProductBloc>();

        final body = pos.receipt != null && pos.isEmpty
            ? _ReceiptView(sale: pos.receipt!)
            : pos.isEmpty
                ? _emptySale()
                : ListView.separated(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    itemCount: pos.lines.length,
                    separatorBuilder: (_, __) => const Divider(height: 16),
                    itemBuilder: (context, i) {
                      final line = pos.lines[i];
                      return _SaleLineRow(line: line, product: productBloc.productById(line.productId));
                    },
                  );

        final pane = Column(
          mainAxisSize: compact ? MainAxisSize.min : MainAxisSize.max,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header
            InkWell(
              onTap: onToggle,
              child: Padding(
                padding: EdgeInsets.fromLTRB(16, compact ? 10 : 16, 8, compact ? 6 : 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Current Sale', style: GoogleFonts.poppins(fontSize: compact ? 15 : 20, fontWeight: FontWeight.w600)),
                          Text(
                            pos.isEmpty ? 'No items' : '${pos.unitCount} unit${pos.unitCount == 1 ? '' : 's'} · ${pos.lines.length} product${pos.lines.length == 1 ? '' : 's'}',
                            style: GoogleFonts.poppins(fontSize: 12, color: AppColors.textSecondary),
                          ),
                        ],
                      ),
                    ),
                    if (!pos.isEmpty)
                      IconButton(
                        tooltip: 'Clear sale',
                        icon: const Icon(Icons.delete_outline, color: AppColors.textSecondary),
                        onPressed: () => context.read<PosBloc>().add(PosClearSale()),
                      ),
                    if (onToggle != null)
                      IconButton(
                        tooltip: compact ? 'Expand' : 'Back to products',
                        icon: Icon(compact ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down),
                        onPressed: onToggle,
                      ),
                  ],
                ),
              ),
            ),
            const Divider(height: 1),
            if (!compact) Expanded(child: body),
            // Footer: total + complete
            Container(
              color: AppColors.secondary.withValues(alpha: 0.04),
              padding: EdgeInsets.fromLTRB(16, compact ? 10 : 16, 16, compact ? 12 : 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Text('Total', style: GoogleFonts.poppins(fontSize: compact ? 16 : 20, fontWeight: FontWeight.w600)),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerRight,
                          child: Text(_rs(pos.total),
                              style: GoogleFonts.poppins(
                                  fontSize: compact ? 20 : 26, fontWeight: FontWeight.w700, color: AppColors.secondary)),
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: compact ? 8 : 12),
                  VendraButton(
                    text: 'Complete sale',
                    icon: Icons.check_circle_outline,
                    isLoading: pos.isSubmitting,
                    onPressed: pos.isEmpty ? null : () => context.read<PosBloc>().add(PosCompleteSale()),
                  ),
                ],
              ),
            ),
          ],
        );

        if (!compact) return ColoredBox(color: Colors.white, child: pane);
        return Material(
          elevation: 12,
          color: Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
          clipBehavior: Clip.antiAlias,
          child: pane,
        );
      },
    );
  }

  Widget _emptySale() {
    return Center(
      child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.shopping_basket_outlined, size: 48, color: Colors.grey.shade300),
          const SizedBox(height: 8),
          Text('Tap a product or scan a barcode to start a sale',
              textAlign: TextAlign.center, style: GoogleFonts.poppins(fontSize: 13, color: AppColors.textSecondary)),
        ],
      ),
      ),
    );
  }
}

class _SaleLineRow extends StatelessWidget {
  final PosLine line;
  final ProductModel? product; // live stock numbers
  const _SaleLineRow({required this.line, this.product});

  Future<void> _editQuantity(BuildContext context) async {
    final bloc = context.read<PosBloc>();
    final text = await showDialog<String>(
      context: context,
      builder: (_) => TextPromptDialog(
        title: line.name,
        label: 'Quantity',
        initialValue: '${line.quantity}',
        confirmLabel: 'Set',
      ),
    );
    final value = int.tryParse(text ?? '');
    if (value != null && value >= 0) bloc.add(PosSetQuantity(line.productId, value));
  }

  @override
  Widget build(BuildContext context) {
    final bloc = context.read<PosBloc>();
    final sellable = product?.sellableInStore;
    final overLimit = sellable != null && line.quantity > sellable;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            SizedBox(
              width: 40,
              height: 40,
              child: product != null
                  ? ProductImage(product: product!, iconSize: 18, borderRadius: BorderRadius.circular(8))
                  : DecoratedBox(
                      decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(8)),
                      child: Icon(Icons.inventory_2_outlined, size: 18, color: Colors.grey.shade400),
                    ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(line.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w500)),
                  Text(_rs(line.unitPrice), style: GoogleFonts.poppins(fontSize: 12, color: AppColors.textSecondary)),
                ],
              ),
            ),
            _RoundIcon(icon: Icons.remove, onTap: () => bloc.add(PosSetQuantity(line.productId, line.quantity - 1))),
            InkWell(
              onTap: () => _editQuantity(context),
              child: SizedBox(
                width: 40,
                child: Text('${line.quantity}',
                    textAlign: TextAlign.center, style: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w600)),
              ),
            ),
            _RoundIcon(icon: Icons.add, onTap: () => bloc.add(PosSetQuantity(line.productId, line.quantity + 1))),
            SizedBox(
              width: 92,
              child: Text(_rs(line.total),
                  textAlign: TextAlign.right, style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w600)),
            ),
          ],
        ),
        if (product != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              overLimit
                  ? 'Only ${product!.sellableInStore} sellable — ${product!.reservedQuantity} reserved for online orders'
                  : 'Sellable ${product!.sellableInStore} · Reserved ${product!.reservedQuantity}',
              style: GoogleFonts.poppins(
                fontSize: 11,
                color: overLimit ? AppColors.reservedAmber : AppColors.textLight,
                fontWeight: overLimit ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ),
      ],
    );
  }
}

class _RoundIcon extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _RoundIcon({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      customBorder: const CircleBorder(),
      onTap: onTap,
      child: Container(
        width: 30,
        height: 30,
        decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: Colors.grey.shade400)),
        child: Icon(icon, size: 16, color: AppColors.textPrimary),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════
// Receipt summary after "Complete sale"
// ══════════════════════════════════════════════════════════════
class _ReceiptView extends StatelessWidget {
  final PosSale sale;
  const _ReceiptView({required this.sale});

  @override
  Widget build(BuildContext context) {
    return ListView(
      shrinkWrap: true,
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          children: [
            const Icon(Icons.check_circle, color: AppColors.success, size: 28),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Sale #${sale.id} completed', style: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w600)),
                  Text(
                    DateFormat('d MMM yyyy, h:mm a').format(sale.createdAt ?? DateTime.now()),
                    style: GoogleFonts.poppins(fontSize: 12, color: AppColors.textSecondary),
                  ),
                ],
              ),
            ),
          ],
        ),
        const Divider(height: 24),
        for (final item in sale.items)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text('${item.quantity} × ${item.productName}',
                          style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w500)),
                    ),
                    Text(_rs(item.total), style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w600)),
                  ],
                ),
                if (item.privateStockAfter != null)
                  Text(
                    'Stock now: private ${item.privateStockAfter} · reserved ${item.reservedQuantity ?? 0} · public ${item.publicStockAfter ?? 0}',
                    style: GoogleFonts.poppins(fontSize: 11, color: AppColors.textLight),
                  ),
              ],
            ),
          ),
        const Divider(height: 16),
        Row(
          children: [
            Expanded(
              child: Text('Paid (walk-in)', style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w600)),
            ),
            Text(_rs(sale.totalAmount),
                style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.success)),
          ],
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: () => context.read<PosBloc>().add(PosReceiptDismissed()),
          icon: const Icon(Icons.add_shopping_cart),
          label: const Text('New sale'),
          style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 12)),
        ),
      ],
    );
  }
}

// ══════════════════════════════════════════════════════════════
// Today's walk-in sales (GET /api/vendor/pos/sales)
// ══════════════════════════════════════════════════════════════
class _TodaySalesSheet extends StatelessWidget {
  const _TodaySalesSheet();

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      maxChildSize: 0.9,
      builder: (context, scroll) => BlocBuilder<PosBloc, PosState>(
        builder: (context, pos) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text("Today's walk-in sales",
                        style: GoogleFonts.poppins(fontSize: 17, fontWeight: FontWeight.w600)),
                  ),
                  Text('${pos.todayCount} · ${_rs(pos.todayTotal)}',
                      style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.success)),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: pos.isLoadingToday && pos.todaySales.isEmpty
                  ? const Center(child: CircularProgressIndicator())
                  : pos.todaySales.isEmpty
                      ? Center(
                          child: Text('No walk-in sales yet today.',
                              style: GoogleFonts.poppins(color: AppColors.textSecondary)))
                      : ListView.separated(
                          controller: scroll,
                          padding: const EdgeInsets.all(16),
                          itemCount: pos.todaySales.length,
                          separatorBuilder: (_, __) => const Divider(height: 20),
                          itemBuilder: (context, i) {
                            final s = pos.todaySales[i];
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Text('Sale #${s.id}', style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
                                    const SizedBox(width: 8),
                                    if (s.createdAt != null)
                                      Text(DateFormat('h:mm a').format(s.createdAt!),
                                          style: GoogleFonts.poppins(fontSize: 12, color: AppColors.textLight)),
                                    const Spacer(),
                                    Text(_rs(s.totalAmount), style: GoogleFonts.poppins(fontWeight: FontWeight.w700)),
                                  ],
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  s.items.map((it) => '${it.quantity}× ${it.productName}').join(', '),
                                  style: GoogleFonts.poppins(fontSize: 12, color: AppColors.textSecondary),
                                ),
                              ],
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }
}
